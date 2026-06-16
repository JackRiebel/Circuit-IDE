import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/studio_turn_runner.dart';
import '../agent/config/config.dart';
import '../agent/config/models_config.dart';
import '../agent/tools/tool_executor.dart';
import '../agent/tools/tool_registry.dart';
import '../enums/ai_provider.dart';
import '../enums/connection_status.dart';
import '../enums/event_type.dart';
import '../models/agent_preflight.dart';
import '../models/agent_request.dart';
import '../models/agent_run.dart';
import '../models/chat_message.dart';
import '../models/confirmation_request.dart';
import '../models/context_attachment.dart';
import '../models/studio_turn.dart';
import '../models/workspace_context.dart';
import 'agent_request_provider.dart';
import 'agent_run_provider.dart';
import 'agent_workspace_provider.dart';
import 'connection_provider.dart';
import 'settings_provider.dart';
import 'studio_request_lifecycle_provider.dart';
import 'studio_thread_provider.dart';
import 'studio_turn_provider.dart';
import 'workspace_context_provider.dart';

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

class AgentTurnSession {
  final String requestId;
  final String threadId;
  final String? taskId;
  final String model;
  final AgentTurnPhase phase;
  final DateTime startedAt;
  final String? lastError;

  const AgentTurnSession({
    required this.requestId,
    required this.threadId,
    this.taskId,
    required this.model,
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
      phase: phase ?? this.phase,
      startedAt: startedAt,
      lastError: lastError ?? this.lastError,
    );
  }
}

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

class AgentTurnRuntime extends Notifier<AgentTurnRuntimeState> {
  final _runners = <String, StudioTurnRunner>{};
  final _pendingApprovals = <String, ConfirmationRequest>{};
  final _approvalRequestIds = <String, String>{};
  final _turnAutoApprove = <String, bool>{};

  @override
  AgentTurnRuntimeState build() => const AgentTurnRuntimeState();

  Future<AgentPreflightResult> preflightMessage(
    String content,
    List<ContextAttachment> attachments,
  ) async {
    final issues = <AgentPreflightIssue>[];
    final settings = ref.read(settingsProvider);
    final service = ref.read(agentServiceProvider);
    final connectionStatus = ref.read(connectionStatusProvider);
    final workspace = ref.read(workspaceContextProvider);
    final selectedModel = service.activeProviderType == AIProviderType.cisco
        ? service.state.model
        : settings.ciscoModel;
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

    if (connectionStatus != ConnectionStatus.connected) {
      final config = await AgentConfig.load();
      final hasCredentials = config.hasCiscoCredentials;
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message: hasCredentials
              ? 'AI is not connected. Reconnect before sending.'
              : 'Circuit credentials are missing. Add them in Settings.',
          recoveryAction: hasCredentials
              ? AgentPreflightRecoveryAction.reconnect
              : AgentPreflightRecoveryAction.openSettings,
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
    } else if (modelInfo?.supportsTools == false) {
      issues.add(
        const AgentPreflightIssue(
          severity: AgentPreflightSeverity.warning,
          message:
              'Selected model may not support tools. Coding actions may be limited.',
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
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final compact = normalized.replaceAll(RegExp(r'[^a-z ]+'), ' ');
    if (RegExp(r'\b(reject|deny|cancel|stop)\b').hasMatch(compact)) {
      rejectApproval(pending.approvalId!);
      return true;
    }
    if (RegExp(
          r'\b(always|auto|all|this task|this turn)\b',
        ).hasMatch(compact) &&
        RegExp(r'\b(approve|yes|ok|proceed|continue)\b').hasMatch(compact)) {
      approveForTurn(pending.approvalId!);
      return true;
    }
    if (RegExp(
      r'^(approve|approved|yes|y|ok|okay|proceed|continue|do it|go ahead)( please)?$',
    ).hasMatch(compact.trim())) {
      approveOnce(pending.approvalId!);
      return true;
    }
    return false;
  }

  Future<void> startTurn({
    required String requestId,
    required String threadId,
    required String? taskId,
    required String outboundText,
    required List<ContextAttachment> attachments,
    required List<ChatMessage> historyOverride,
    required AgentToolMode toolMode,
    required String model,
    required String retryPrompt,
    required bool finishTask,
  }) async {
    final service = ref.read(agentServiceProvider);
    final provider = service.provider;
    final workingDir = service.state.workingDir;
    final finalContent = _buildMessageWithContext(outboundText, attachments);
    if (provider == null || workingDir.trim().isEmpty) {
      final message = provider == null
          ? 'Circuit AI is not connected.'
          : 'No workspace is bound to this Studio turn.';
      ref.read(studioThreadProvider.notifier).fail(threadId, message);
      ref
          .read(studioRequestLifecycleProvider.notifier)
          .failRequest(requestId, message);
      return;
    }
    state = state.copyWith(
      activeSessions: {
        ...state.activeSessions,
        requestId: AgentTurnSession(
          requestId: requestId,
          threadId: threadId,
          taskId: taskId,
          model: model,
          phase: AgentTurnPhase.providerRequest,
          startedAt: DateTime.now(),
        ),
      },
    );
    ref
        .read(agentRunProvider.notifier)
        .startRun(
          id: requestId,
          kind: AgentRunKind.chat,
          model: model,
          message: 'Studio turn sent',
          title: _preview(retryPrompt),
          inputPreview: _preview(retryPrompt),
          retryPrompt: retryPrompt,
          retryAttachments: attachments,
          contextAttachmentCount: attachments.length,
        );
    ref
        .read(agentRequestProvider.notifier)
        .start(lane: AgentRequestLane.chat, requestId: requestId, model: model);
    final turnRef = ref.read(studioTurnProvider).refForRequest(requestId);
    final executor = ToolExecutor(
      workingDir: workingDir,
      autoApprove: false,
      onConfirmationNeeded: (request) =>
          _handleConfirmationNeeded(requestId, request),
      onToolCallUpdate: (toolCall) {
        final type = switch (toolCall.status.name) {
          'success' => EventType.toolCallCompleted,
          'error' => EventType.toolCallError,
          'cancelled' => EventType.toolCallError,
          _ => EventType.toolCallStarted,
        };
        service.events.emit(type, {
          'toolCall': toolCall,
          'requestId': requestId,
        });
      },
    );
    final config = await AgentConfig.load();
    if (config.githubPat != null) {
      executor.configureGithub(config.githubPat!);
    }
    final runner = StudioTurnRunner(
      provider: provider,
      workingDir: workingDir,
      events: service.events,
      model: model,
      toolExecutor: executor,
    );
    _runners[requestId] = runner;

    try {
      final result = await runner
          .run(
            requestId: requestId,
            turnId: turnRef?.turnId,
            userMessage: finalContent,
            history: historyOverride,
            toolMode: toolMode,
          )
          .timeout(const Duration(minutes: 4));
      ref
          .read(studioThreadProvider.notifier)
          .updateTokenUsage(threadId, result.usage);
      ref
          .read(agentRunProvider.notifier)
          .finishRun(
            AgentRunKind.chat,
            outputPreview: _preview(result.content),
          );
      ref.read(agentRequestProvider.notifier).finish(AgentRequestLane.chat);
    } on TimeoutException {
      const message =
          'Request timed out after 4 minutes. Try again or check the Circuit AI connection.';
      runner.cancel();
      ref.read(studioThreadProvider.notifier).fail(threadId, message);
      ref
          .read(studioRequestLifecycleProvider.notifier)
          .failRequest(requestId, message);
      if (finishTask && taskId != null) {
        ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
      }
      ref
          .read(agentRunProvider.notifier)
          .finishRun(AgentRunKind.chat, error: message);
      ref
          .read(agentRequestProvider.notifier)
          .finish(AgentRequestLane.chat, error: message);
    } on StudioTurnCancelledException {
      ref
          .read(studioRequestLifecycleProvider.notifier)
          .cancelRequest(requestId);
      ref
          .read(agentRequestProvider.notifier)
          .finish(AgentRequestLane.chat, cancelled: true);
      ref
          .read(agentRunProvider.notifier)
          .finishRun(AgentRunKind.chat, cancelled: true);
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      ref.read(studioThreadProvider.notifier).fail(threadId, message);
      ref
          .read(studioRequestLifecycleProvider.notifier)
          .failRequest(requestId, message);
      if (finishTask && taskId != null) {
        ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
      }
      ref
          .read(agentRunProvider.notifier)
          .finishRun(AgentRunKind.chat, error: message);
      ref
          .read(agentRequestProvider.notifier)
          .finish(AgentRequestLane.chat, error: message);
    } finally {
      _runners.remove(requestId);
      _turnAutoApprove.remove(requestId);
      _pendingApprovals.removeWhere(
        (id, _) => _approvalRequestIds[id] == requestId,
      );
      _approvalRequestIds.removeWhere((_, value) => value == requestId);
      final active = {...state.activeSessions}..remove(requestId);
      state = state.copyWith(activeSessions: active);
    }
  }

  Future<bool> _handleConfirmationNeeded(
    String requestId,
    ConfirmationRequest request,
  ) async {
    final service = ref.read(agentServiceProvider);
    if (_turnAutoApprove[requestId] == true) {
      service.events.emit(EventType.confirmationNeeded, {
        'request': request,
        'requestId': requestId,
      });
      service.events.emit(EventType.confirmationReceived, {
        'id': request.id,
        'approved': true,
        'requestId': requestId,
      });
      return true;
    }
    _pendingApprovals[request.id] = request;
    _approvalRequestIds[request.id] = requestId;
    service.events.emit(EventType.confirmationNeeded, {
      'request': request,
      'requestId': requestId,
    });
    final approved = await request.response;
    service.events.emit(EventType.confirmationReceived, {
      'id': request.id,
      'approved': approved,
      'requestId': requestId,
    });
    return approved;
  }

  void approveOnce(String approvalId) {
    final request = _pendingApprovals.remove(approvalId);
    _approvalRequestIds.remove(approvalId);
    if (request != null) {
      request.approve();
      return;
    }
    ref.read(agentServiceProvider).approveConfirmation(approvalId);
  }

  void approveForTurn(String approvalId) {
    final requestId = _approvalRequestIds[approvalId];
    if (requestId != null) {
      _turnAutoApprove[requestId] = true;
    }
    approveOnce(approvalId);
  }

  void rejectApproval(String approvalId) {
    final request = _pendingApprovals.remove(approvalId);
    _approvalRequestIds.remove(approvalId);
    if (request != null) {
      request.reject();
      return;
    }
    ref.read(agentServiceProvider).rejectConfirmation(approvalId);
  }

  void cancel(String requestId) {
    _runners[requestId]?.cancel();
    ref.read(studioRequestLifecycleProvider.notifier).cancelRequest(requestId);
    ref
        .read(agentRequestProvider.notifier)
        .finish(AgentRequestLane.chat, cancelled: true);
    ref
        .read(agentRunProvider.notifier)
        .finishRun(AgentRunKind.chat, cancelled: true);
    _pendingApprovals.removeWhere(
      (id, _) => _approvalRequestIds[id] == requestId,
    );
    _approvalRequestIds.removeWhere((_, value) => value == requestId);
    _turnAutoApprove.remove(requestId);
    final active = {...state.activeSessions}..remove(requestId);
    state = state.copyWith(activeSessions: active);
  }

  StudioTurnEvent? _activePendingApproval() {
    final selected = ref.read(studioThreadProvider).selectedThread;
    if (selected == null) return null;
    for (final turn in selected.turns.reversed) {
      for (final event in turn.events.reversed) {
        if (event.type == StudioTurnEventType.approvalRequest &&
            event.approvalState == ApprovalRequestState.pending &&
            event.approvalId != null) {
          return event;
        }
      }
    }
    return null;
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

String _preview(String text) {
  final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.length <= 120) return clean;
  return '${clean.substring(0, 117)}...';
}

final agentTurnRuntimeProvider =
    NotifierProvider<AgentTurnRuntime, AgentTurnRuntimeState>(
      AgentTurnRuntime.new,
    );
