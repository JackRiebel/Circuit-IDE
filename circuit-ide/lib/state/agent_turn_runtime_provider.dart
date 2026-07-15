import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/studio_turn_runner.dart';
import '../agent/studio_agent_environment.dart';
import '../agent/config/models_config.dart';
import '../agent/delegation/subagent_delegation_service.dart';
import '../agent/intent/intent_model_classifier.dart';
import '../agent/providers/provider_interface.dart';
import '../agent/security/agent_tool_permission_policy.dart';
import '../agent/tools/tool_executor.dart';
import '../agent/tools/tool_registry.dart';
import '../enums/connection_status.dart';
import '../enums/event_type.dart';
import '../models/agent_preflight.dart';
import '../models/agent_tool_permission.dart';
import '../models/accepted_plan_context.dart';
import '../models/agent_config_model.dart';
import '../models/chat_message.dart';
import '../models/confirmation_request.dart';
import '../models/context_attachment.dart';
import '../models/provider_lifecycle_event.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_shell.dart';
import '../models/studio_turn.dart';
import '../models/workspace_context.dart';
import '../models/turn_intent.dart';
import '../services/event_bus.dart';
import '../services/provider_image_input_builder.dart';
import 'agent_connector_network_review.dart';
import 'agent_workspace_provider.dart';
import 'command_run_provider.dart';
import 'connection_provider.dart' show connectionStatusProvider;
import 'studio_provider_connection.dart';
import 'settings_provider.dart';
import 'patch_proposal_provider.dart';
import 'studio_request_lifecycle_provider.dart';
import 'studio_thread_provider.dart';
import 'studio_turn_provider.dart';
import 'workspace_context_provider.dart';

part 'agent_turn_runtime_approvals.dart';

enum AgentTurnPhase {
  idle,
  preflighting,
  buildingContext,
  providerRequest,
  streaming,
  toolDecision,
  approvalWait,
  toolExecution,
  patchProposal,
  verification,
  completed,
  failed,
  cancelled,
}

final studioAgentEnvironmentOverrideProvider =
    Provider<StudioAgentEnvironment?>((ref) => null);

final studioTurnTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 4),
);

/// Kept injectable so the routing contract can be evaluated offline without a
/// connected provider. Production uses the constrained typed classifier.
final intentModelClassifierProvider = Provider<IntentModelClassifier>(
  (ref) => const IntentModelClassifier(),
);

class AgentTurnSession {
  final String requestId;
  final String threadId;
  final String? taskId;
  final String model;
  final TurnIntent intent;
  final String workspaceRoot;
  final String? customAgentId;
  final AgentTurnPhase phase;
  final DateTime startedAt;
  final String? lastError;

  const AgentTurnSession({
    required this.requestId,
    required this.threadId,
    this.taskId,
    required this.model,
    required this.intent,
    required this.workspaceRoot,
    this.customAgentId,
    required this.phase,
    required this.startedAt,
    this.lastError,
  });

  AgentTurnSession copyWith({AgentTurnPhase? phase, String? lastError}) {
    return AgentTurnSession(
      requestId: requestId,
      threadId: threadId,
      taskId: taskId,
      model: model,
      intent: intent,
      workspaceRoot: workspaceRoot,
      customAgentId: customAgentId,
      phase: phase ?? this.phase,
      startedAt: startedAt,
      lastError: lastError ?? this.lastError,
    );
  }
}

// ADR-0006: every agent run is scoped through the Studio turn runtime.
class AgentTurnRuntimeState {
  final Map<String, AgentTurnSession> activeSessions;

  const AgentTurnRuntimeState({this.activeSessions = const {}});

  bool get hasActiveStudioRequest => activeSessions.isNotEmpty;

  AgentTurnSession? sessionFor(String requestId) => activeSessions[requestId];

  AgentTurnRuntimeState copyWith({
    Map<String, AgentTurnSession>? activeSessions,
  }) {
    return AgentTurnRuntimeState(
      activeSessions: activeSessions ?? this.activeSessions,
    );
  }
}

class AgentTurnRuntime extends _AgentTurnRuntimeApprovalController {
  final _runners = <String, StudioTurnRunner>{};
  final _runtimeEvents = <String, EventBus>{};
  final _ownedRuntimeEvents = <String, EventBus>{};

  @override
  AgentTurnRuntimeState build() => const AgentTurnRuntimeState();

  Future<IntentRoutingDecision> resolveIntentRouting({
    required String prompt,
    required StudioPromptMode promptMode,
    required bool planModeEnabled,
  }) {
    final deterministicDecision = IntentClassifier.classifyDecision(
      prompt,
      promptMode: promptMode,
      planModeEnabled: planModeEnabled,
    );
    if (state.hasActiveStudioRequest) {
      return Future.value(
        deterministicDecision.safeFallback(
          'Intent routing was deferred because another Studio request is active; continuing as Ask.',
        ),
      );
    }
    final environmentOverride = ref.read(
      studioAgentEnvironmentOverrideProvider,
    );
    final provider =
        environmentOverride?.provider ??
        ref.read(studioAgentConnectionProvider).provider;
    final model =
        environmentOverride?.model ?? ref.read(settingsProvider).ciscoModel;
    return ref
        .read(intentModelClassifierProvider)
        .resolve(
          deterministicDecision: deterministicDecision,
          prompt: prompt,
          provider: provider,
          model: model,
        );
  }

  Future<AgentPreflightResult> preflightMessage(
    String content,
    List<ContextAttachment> attachments, {
    bool requiresTools = false,
  }) async {
    final issues = <AgentPreflightIssue>[];
    final settings = ref.read(settingsProvider);
    final connectionStatus = ref.read(connectionStatusProvider);
    final studioConnection = ref.read(studioAgentConnectionProvider);
    final hasProvider = studioConnection.provider != null;
    final workspace = ref.read(workspaceContextProvider);
    final selectedModel = settings.ciscoModel;
    final cachedModelInfo = settings.connectorModels
        .map((model) => model.toModelInfo())
        .where((model) => model.id == selectedModel)
        .firstOrNull;
    final modelInfo = cachedModelInfo ?? ModelsConfig.getModel(selectedModel);
    final contextWindow = modelInfo?.contextWindow ?? 120000;
    final estimatedTokens = _estimateTokens(
      _buildMessageWithContext(content, attachments),
    );

    if (state.hasActiveStudioRequest) {
      issues.add(
        const AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message: 'A Studio request is already running.',
          recoveryAction: AgentPreflightRecoveryAction.waitForRequest,
        ),
      );
    }

    if (connectionStatus != ConnectionStatus.connected && !hasProvider) {
      final looksCredentialRelated =
          settings.connectorHealthStatus ==
              ConnectorHealthStatus.credentialsMissing ||
          settings.connectorHealthStatus == ConnectorHealthStatus.tokenFailed ||
          (settings.connectorHealthMessage ?? '').toLowerCase().contains(
            'credential',
          ) ||
          (settings.connectorHealthMessage ?? '').toLowerCase().contains(
            'auth',
          );
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message: looksCredentialRelated
              ? 'Circuit credentials need attention. Check Settings before sending.'
              : 'AI is not connected. Reconnect before sending.',
          recoveryAction: looksCredentialRelated
              ? AgentPreflightRecoveryAction.openSettings
              : AgentPreflightRecoveryAction.reconnect,
        ),
      );
    }

    final availableModels = [
      ...ModelsConfig.ciscoModels,
      ...settings.connectorModels.map((model) => model.toModelInfo()),
    ];
    final modelAvailable = availableModels.any(
      (model) => model.id == selectedModel,
    );
    if (!modelAvailable) {
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message: 'Selected model "$selectedModel" is not available.',
          recoveryAction: AgentPreflightRecoveryAction.openSettings,
        ),
      );
    } else if (requiresTools && modelInfo?.supportsTools != true) {
      issues.add(
        const AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message:
              'The selected model does not advertise tool calling. Choose a tools-capable model or use Chat mode.',
          recoveryAction: AgentPreflightRecoveryAction.openSettings,
        ),
      );
    }
    final imageWithoutHashBoundOcrFallback = attachments.any(
      (attachment) =>
          attachment.type == ContextAttachmentType.image &&
          !ProviderImageInputBuilder.hasHashBoundOcrProvenance(attachment),
    );
    if (imageWithoutHashBoundOcrFallback &&
        modelInfo?.supportsImageInput != true) {
      issues.add(
        const AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message:
              'The selected model does not advertise image input. Remove the image, attach verified OCR text, or choose a vision-capable model.',
          recoveryAction: AgentPreflightRecoveryAction.openSettings,
        ),
      );
    }

    if (workspace.rootPath == null) {
      issues.add(
        const AgentPreflightIssue(
          severity: AgentPreflightSeverity.warning,
          message: 'No project folder is selected. This will be chat-only.',
          recoveryAction: AgentPreflightRecoveryAction.waitForWorkspace,
        ),
      );
    } else if (workspace.status == WorkspaceLifecycleStatus.loading ||
        workspace.status == WorkspaceLifecycleStatus.indexing) {
      issues.add(
        const AgentPreflightIssue(
          severity: AgentPreflightSeverity.warning,
          message: 'Workspace context is still refreshing.',
          recoveryAction: AgentPreflightRecoveryAction.waitForWorkspace,
        ),
      );
    }

    if (estimatedTokens > contextWindow) {
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message:
              'Context is too large for $selectedModel ($estimatedTokens / $contextWindow tokens).',
          recoveryAction: AgentPreflightRecoveryAction.reduceContext,
        ),
      );
    } else if (estimatedTokens > contextWindow * 0.8) {
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.warning,
          message:
              'Context is close to the limit ($estimatedTokens / $contextWindow tokens).',
          recoveryAction: AgentPreflightRecoveryAction.reduceContext,
        ),
      );
    }

    return AgentPreflightResult(
      issues: issues,
      estimatedTokens: estimatedTokens,
      contextWindow: contextWindow,
      checkedAt: DateTime.now(),
    );
  }

  bool handlePendingApprovalText(String text) {
    final pending = _activePendingApproval();
    if (pending == null) return false;
    final compact = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (compact.isEmpty) return false;
    if (_isSimpleApprovalRejection(compact)) {
      rejectApproval(pending.approvalId!);
      return true;
    }
    if (_isSimpleTurnApproval(compact)) {
      approveForTurn(pending.approvalId!);
      return true;
    }
    if (_isSimpleOneShotApproval(compact)) {
      approveOnce(pending.approvalId!);
      return true;
    }
    return false;
  }

  bool _isSimpleApprovalRejection(String text) {
    return RegExp(
      r'^(reject|deny|decline|cancel|stop)( (it|this|request|action))?( please)?$',
    ).hasMatch(text);
  }

  bool _isSimpleTurnApproval(String text) {
    return RegExp(
      r'^(approve|approved|yes|y|ok|okay|proceed|continue|do it|go ahead)( (for )?(this )?turn)( please)?$',
    ).hasMatch(text);
  }

  bool _isSimpleOneShotApproval(String text) {
    return RegExp(
      r'^(approve|approved|yes|y|ok|okay|proceed|continue|do it|go ahead)( (it|this|request|action))?( please)?$',
    ).hasMatch(text);
  }

  Future<void> startTurn({
    required String requestId,
    required String threadId,
    required String? taskId,
    required String outboundText,
    required List<ContextAttachment> attachments,
    required List<ChatMessage> modelHistory,
    required AgentToolMode toolMode,
    required TurnIntent intent,
    AcceptedPlanContext? acceptedPlan,
    required String model,
    required String retryPrompt,
    String? displayTitle,
    required bool finishTask,
    AgentConfigModel? customAgent,
    String? workspaceRoot,
  }) async {
    if (state.activeSessions.containsKey(requestId)) {
      return;
    }
    if (state.activeSessions.isNotEmpty) {
      const message =
          'A request is already running. Wait for it to finish or cancel it before sending another.';
      _failBeforeStart(
        requestId: requestId,
        threadId: threadId,
        taskId: taskId,
        finishTask: finishTask,
        message: message,
      );
      return;
    }
    final connection = ref.read(studioAgentConnectionProvider);
    final environmentOverride = ref.read(
      studioAgentEnvironmentOverrideProvider,
    );
    final provider = environmentOverride?.provider ?? connection.provider;
    final workspace = ref.read(workspaceContextProvider);
    // A task may be bound to an isolated Git worktree. Never derive the tool
    // root from the visible project tree when the caller supplied that task
    // root; every read, command, patch, and permission check below is built
    // from this one value.
    final workingDir =
        environmentOverride?.workspaceRoot ??
        workspaceRoot ??
        workspace.rootPath;
    final effectiveWorkingDir =
        (workingDir == null || workingDir.trim().isEmpty) &&
            toolMode == AgentToolMode.chat
        ? Directory.systemTemp.path
        : workingDir;
    final normalizedWorkingDir = effectiveWorkingDir?.trim() ?? '';
    final finalContent = _buildMessageWithContext(outboundText, attachments);
    if (provider == null || normalizedWorkingDir.isEmpty) {
      final message = provider == null
          ? 'Circuit AI is not connected.'
          : 'No workspace is bound to this Studio turn.';
      _failBeforeStart(
        requestId: requestId,
        threadId: threadId,
        taskId: taskId,
        finishTask: finishTask,
        message: message,
      );
      return;
    }
    final runtimeEvents = environmentOverride?.events ?? EventBus();
    final ownsRuntimeEvents = environmentOverride == null;
    final workspaceState = ref.read(agentWorkspaceProvider);
    final taskPolicy = taskId == null
        ? null
        : workspaceState.tasks
              .where((task) => task.id == taskId)
              .firstOrNull
              ?.policy;
    final projectPolicy = workspaceState.projectPolicy;
    final environment =
        environmentOverride ??
        StudioAgentEnvironment(
          provider: provider,
          model: model,
          workspaceRoot: normalizedWorkingDir,
          permissionPolicy: AgentToolPermissionPolicy(
            workingDir: normalizedWorkingDir,
            networkDisposition: projectPolicy.externalNetwork,
            networkRules: projectPolicy.networkRules.isNotEmpty
                ? projectPolicy.networkRules
                : taskPolicy?.networkRules ?? const [],
          ),
          events: runtimeEvents,
          onProviderEvent: (_) {},
        );
    final settings = ref.read(settingsProvider);
    final selectedModelInfo =
        settings.connectorModels
            .where((candidate) => candidate.id == model)
            .firstOrNull
            ?.toModelInfo() ??
        ModelsConfig.getModel(model);
    final selectedCapabilities = capabilitiesForSelectedModel(
      environment.provider.capabilities,
      selectedModelInfo,
    );
    final imageInputs = await const ProviderImageInputBuilder().build(
      attachments: attachments,
      capabilities: selectedCapabilities,
    );
    if (imageInputs.hasErrors) {
      _failBeforeStart(
        requestId: requestId,
        threadId: threadId,
        taskId: taskId,
        finishTask: finishTask,
        message: imageInputs.errors.join(' '),
      );
      return;
    }
    ref
        .read(studioRequestLifecycleProvider.notifier)
        .attachRuntimeEvents(requestId, environment.events);
    ref
        .read(commandRunProvider.notifier)
        .attachRuntimeEvents(requestId, environment.events);
    _runtimeEvents[requestId] = environment.events;
    if (ownsRuntimeEvents) {
      _ownedRuntimeEvents[requestId] = environment.events;
    }
    state = state.copyWith(
      activeSessions: {
        ...state.activeSessions,
        requestId: AgentTurnSession(
          requestId: requestId,
          threadId: threadId,
          taskId: taskId,
          model: model,
          intent: intent,
          workspaceRoot: environment.workspaceRoot,
          customAgentId: customAgent?.id,
          phase: AgentTurnPhase.providerRequest,
          startedAt: DateTime.now(),
        ),
      },
    );
    final turnRef = ref.read(studioTurnProvider).refForRequest(requestId);
    if (acceptedPlan != null) {
      ref
          .read(studioTurnProvider.notifier)
          .startAcceptedPlanImplementation(requestId, acceptedPlan);
      if (acceptedPlan.verificationRequested) {
        ref
            .read(studioTurnProvider.notifier)
            .markAcceptedPlanVerificationRequested(requestId);
      }
    }
    final initialConnectorNetworkPolicy =
        ProviderConnectorNetworkPolicy.snapshot(
          networkDisposition: environment.permissionPolicy.networkDisposition,
          networkRules: environment.permissionPolicy.networkRules,
        );
    StudioTurnRunner? runner;
    final requestTimeout = _timeoutFor(customAgent);

    try {
      final connectorNetworkPolicy = await reviewProviderConnectorNetworkPolicy(
        requestId: requestId,
        provider: environment.provider,
        policy: initialConnectorNetworkPolicy,
        onConfirmationNeeded: (request) =>
            _handleConfirmationNeeded(requestId, request, environment.events),
      );
      final delegationService = SubagentDelegationService(
        provider: environment.provider,
        workingDir: environment.workspaceRoot,
        model: environment.model,
        connectorNetworkPolicy: connectorNetworkPolicy,
      );
      final executor = ToolExecutor(
        workingDir: environment.workspaceRoot,
        networkDisposition: environment.permissionPolicy.networkDisposition,
        networkRules: environment.permissionPolicy.networkRules,
        autoApprove: false,
        onConfirmationNeeded: (request) =>
            _handleConfirmationNeeded(requestId, request, environment.events),
        onToolCallUpdate: (toolCall) {
          final type = switch (toolCall.status.name) {
            'success' => EventType.toolCallCompleted,
            'error' => EventType.toolCallError,
            'cancelled' => EventType.toolCallError,
            _ => EventType.toolCallStarted,
          };
          environment.events.emit(type, {
            'toolCall': toolCall,
            'requestId': requestId,
          });
        },
        onSubagentDelegation: delegationService.delegate,
        onCancelSubagents: delegationService.cancel,
      );
      runner = StudioTurnRunner(
        provider: environment.provider,
        workingDir: environment.workspaceRoot,
        events: environment.events,
        model: environment.model,
        toolExecutor: executor,
        connectorNetworkPolicy: connectorNetworkPolicy,
        approvalGrantProvider: () => _turnApprovalGrantKeys[requestId] != null
            ? ApprovalGrant.turn
            : ApprovalGrant.none,
        approvalGrantKeyProvider: () => _turnApprovalGrantKeys[requestId],
      );
      _runners[requestId] = runner;
      final result = await runner
          .run(
            requestId: requestId,
            turnId: turnRef?.turnId,
            userMessage: finalContent,
            history: modelHistory,
            toolMode: toolMode,
            intent: intent,
            acceptedPlan: acceptedPlan,
            images: imageInputs.images,
            reasoningEnabled:
                settings.thinkingMode && selectedCapabilities.supportsReasoning,
            customAgent: customAgent,
          )
          .timeout(requestTimeout);
      _setAcceptedPlanState(requestId, turnRef, result.acceptedPlanState);
      ref
          .read(studioThreadProvider.notifier)
          .updateTokenUsage(threadId, result.usage);
      ref
          .read(studioThreadProvider.notifier)
          .complete(threadId, tokenUsage: result.usage);
      ref
          .read(studioRequestLifecycleProvider.notifier)
          .completeRequest(requestId);
    } on TimeoutException {
      final timeoutLabel = requestTimeout.inSeconds % 60 == 0
          ? '${requestTimeout.inMinutes} minutes'
          : '${requestTimeout.inSeconds} seconds';
      final message =
          'Request timed out after $timeoutLabel. Try again or check the Circuit AI connection.';
      runner?.cancel();
      _rejectPendingApprovalsForRequest(requestId);
      environment.events.emit(EventType.providerLifecycle, {
        'event': ProviderLifecycleEvent(
          requestId: requestId,
          turnId: turnRef?.turnId,
          kind: ProviderLifecycleEventKind.timeout,
          timestamp: DateTime.now(),
          model: model,
          detail: message,
        ),
        'requestId': requestId,
      });
      ref.read(studioThreadProvider.notifier).fail(threadId, message);
      ref
          .read(studioRequestLifecycleProvider.notifier)
          .failRequest(requestId, message);
      if (finishTask && taskId != null) {
        ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
      }
      if (acceptedPlan != null) {
        _setAcceptedPlanState(requestId, turnRef, AcceptedPlanState.failed);
      }
    } on StudioTurnCancelledException {
      _rejectPendingApprovalsForRequest(requestId);
      ref
          .read(studioRequestLifecycleProvider.notifier)
          .cancelRequest(requestId);
    } catch (error) {
      _rejectPendingApprovalsForRequest(requestId);
      final message = error.toString().replaceFirst('Exception: ', '');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!ref.mounted || !state.activeSessions.containsKey(requestId)) {
        return;
      }
      final activePatch = ref.read(patchProposalProvider).active;
      final hasActivePatchFromRequest =
          activePatch != null &&
          activePatch.runId == requestId &&
          activePatch.applyStatus == null;
      final activePatchHasDuplicateTargets =
          hasActivePatchFromRequest &&
          _hasDuplicatePatchTargets(activePatch.edits);
      final shouldRequestPatchRevision =
          error is StudioTurnOutcomeValidationException &&
          hasActivePatchFromRequest &&
          intent != TurnIntent.plan;
      if (error is StudioTurnOutcomeValidationException &&
          hasActivePatchFromRequest &&
          intent == TurnIntent.plan &&
          (activePatch.isPlanOnly == false ||
              _isThinPlanOnlyArtifact(activePatch))) {
        ref
            .read(patchProposalProvider.notifier)
            .discardActiveForRequest(
              requestId,
              message: 'Plan proposal discarded because it was not reviewable.',
            );
      }
      if (shouldRequestPatchRevision) {
        ref
            .read(patchProposalProvider.notifier)
            .requestRevision(
              PatchProposalRevisionRequest(
                patchSetId: activePatch.id,
                prompt: activePatchHasDuplicateTargets
                    ? '$message\n\nThis proposal also contains duplicate normalized file targets. Revise it into one edit per file before applying.'
                    : message,
              ),
            );
        final summary = message.contains('accepted plan')
            ? 'Prepared changes need revision before they match the accepted plan.'
            : 'Prepared changes need revision before they can be applied.';
        if (acceptedPlan != null) {
          _setAcceptedPlanState(
            requestId,
            turnRef,
            AcceptedPlanState.patchProposed,
          );
        }
        ref
            .read(studioTurnProvider.notifier)
            .complete(requestId, content: '', summary: summary);
        ref.read(studioThreadProvider.notifier).setReviewingPatch(threadId);
        ref
            .read(studioRequestLifecycleProvider.notifier)
            .completeRequest(requestId, message: summary);
        return;
      }
      if (acceptedPlan != null) {
        _setAcceptedPlanState(requestId, turnRef, AcceptedPlanState.failed);
      }
      ref.read(studioThreadProvider.notifier).fail(threadId, message);
      ref
          .read(studioRequestLifecycleProvider.notifier)
          .failRequest(requestId, message);
      if (finishTask && taskId != null) {
        ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
      }
    } finally {
      _runners.remove(requestId);
      _turnApprovalGrantKeys.remove(requestId);
      _rejectPendingApprovalsForRequest(requestId);
      _releaseRuntimeEvents(requestId);
      if (ref.mounted) {
        final active = {...state.activeSessions}..remove(requestId);
        state = state.copyWith(activeSessions: active);
      }
    }
  }

  void _failBeforeStart({
    required String requestId,
    required String threadId,
    required String? taskId,
    required bool finishTask,
    required String message,
  }) {
    final lifecycle = ref.read(studioRequestLifecycleProvider);
    if (lifecycle.active(requestId) != null) {
      ref
          .read(studioRequestLifecycleProvider.notifier)
          .failRequest(requestId, message);
    } else {
      ref.read(studioThreadProvider.notifier).fail(threadId, message);
      ref.read(studioTurnProvider.notifier).fail(requestId, message);
      if (finishTask && taskId != null) {
        ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
      }
    }
  }

  void _setAcceptedPlanState(
    String requestId,
    StudioTurnRef? turnRef,
    AcceptedPlanState acceptedPlanState,
  ) {
    final activeTurnRef =
        ref.read(studioTurnProvider).refForRequest(requestId) ?? turnRef;
    if (activeTurnRef == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .updateTurn(
          activeTurnRef.threadId,
          activeTurnRef.turnId,
          acceptedPlanState: acceptedPlanState,
        );
  }

  void cancel(String requestId) {
    final session = state.sessionFor(requestId);
    _runners[requestId]?.cancel();
    if (session != null) {
      _runtimeEvents[requestId]?.emit(EventType.providerLifecycle, {
        'event': ProviderLifecycleEvent(
          requestId: requestId,
          turnId: ref.read(studioTurnProvider).refForRequest(requestId)?.turnId,
          kind: ProviderLifecycleEventKind.cancelled,
          timestamp: DateTime.now(),
          model: session.model,
          detail: 'Studio request cancelled by user.',
        ),
        'requestId': requestId,
      });
    }
    ref.read(studioRequestLifecycleProvider.notifier).cancelRequest(requestId);
    _rejectPendingApprovalsForRequest(requestId);
    _turnApprovalGrantKeys.remove(requestId);
    _releaseRuntimeEvents(requestId);
    final active = {...state.activeSessions}..remove(requestId);
    state = state.copyWith(activeSessions: active);
  }

  void _releaseRuntimeEvents(String requestId) {
    if (ref.mounted) {
      ref
          .read(studioRequestLifecycleProvider.notifier)
          .detachRuntimeEvents(requestId);
      ref.read(commandRunProvider.notifier).detachRuntimeEvents(requestId);
    }
    _runtimeEvents.remove(requestId);
    _ownedRuntimeEvents.remove(requestId)?.dispose();
  }

  void _rejectPendingApprovalsForRequest(String requestId) {
    final pendingIds = [
      for (final entry in _approvalRequestIds.entries)
        if (entry.value == requestId) entry.key,
    ];
    for (final approvalId in pendingIds) {
      final request = _takePendingApproval(approvalId);
      request?.reject();
    }
  }

  bool _hasDuplicatePatchTargets(List<ProposedFileEdit> edits) {
    final seenPaths = <String>{};
    for (final edit in edits) {
      final normalizedPath = edit.path
          .replaceAll('\\', '/')
          .split('/')
          .where((part) => part.isNotEmpty && part != '.')
          .join('/')
          .toLowerCase();
      if (normalizedPath.isEmpty) continue;
      if (!seenPaths.add(normalizedPath)) return true;
    }
    return false;
  }

  bool _isThinPlanOnlyArtifact(ProposedPatchSet patch) {
    if (!patch.isPlanOnly || patch.effectivePlannedTargets.isNotEmpty) {
      return false;
    }
    final words = [
      patch.title,
      patch.comparisonSummary ?? '',
      patch.planMarkdown ?? '',
    ].join(' ').trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    return words.length < 20;
  }

  StudioTurnEvent? _activePendingApproval() {
    final selected = ref.read(studioThreadProvider).selectedThread;
    if (selected == null) return null;
    StudioTurnEvent? latest;
    for (final turn in selected.turns) {
      for (final event in turn.events) {
        if (event.type != StudioTurnEventType.approvalRequest ||
            event.approvalState != ApprovalRequestState.pending ||
            event.approvalId == null) {
          continue;
        }
        final requestId = _approvalRequestIds[event.approvalId];
        if (requestId == null ||
            requestId != event.requestId ||
            !_pendingApprovals.containsKey(event.approvalId) ||
            !state.activeSessions.containsKey(requestId)) {
          continue;
        }
        if (latest == null || event.timestamp.isAfter(latest.timestamp)) {
          latest = event;
        }
      }
    }
    return latest;
  }

  Duration _timeoutFor(AgentConfigModel? customAgent) {
    final runtimeLimit = ref.read(studioTurnTimeoutProvider);
    final agentLimit = customAgent?.limits.maxWallTime;
    if (agentLimit == null || agentLimit >= runtimeLimit) return runtimeLimit;
    return agentLimit;
  }
}

String _buildMessageWithContext(
  String content,
  List<ContextAttachment> attachments,
) {
  if (attachments.isEmpty) return content;
  final context = attachments.map((attachment) => attachment.toPromptBlock());
  return [
    'Use the following explicit context attachments for this request:',
    ...context,
    'User request:',
    content,
  ].join('\n\n');
}

int _estimateTokens(String text) => (text.length / 4).ceil();

final agentTurnRuntimeProvider =
    NotifierProvider<AgentTurnRuntime, AgentTurnRuntimeState>(
      AgentTurnRuntime.new,
    );
