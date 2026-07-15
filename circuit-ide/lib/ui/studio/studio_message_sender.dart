import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../agent/tools/tool_registry.dart';
import '../../models/agent_config_model.dart';
import '../../models/agent_preflight.dart';
import '../../models/agent_workspace.dart';
import '../../models/accepted_plan_context.dart';
import '../../models/chat_message.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/turn_intent.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/agent_manager_provider.dart';
import '../../state/agent_turn_runtime_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_project_creator.dart';
import '../../state/studio_request_lifecycle_provider.dart';
import '../../state/studio_provider_connection.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/studio_turn_provider.dart';
import '../../state/workspace_session_provider.dart';
import 'studio_plan_prompts.dart';
import 'studio_context_directives.dart';
import 'studio_context_payload.dart';
import 'studio_custom_agent_routing.dart';
import 'studio_patch_revision.dart';
import 'studio_patch_verification_runner.dart';
import 'studio_model_history.dart';
import 'studio_plan_intent.dart';
import 'studio_plan_interactions.dart';
import 'studio_send_result.dart';
import 'studio_turn_contracts.dart';
import 'studio_workspace_opening.dart';

export 'studio_context_directives.dart'
    show debugStudioImageDirectiveAttachments, debugStudioImageDirectiveMessage;
export 'studio_context_payload.dart';
export 'studio_custom_agent_routing.dart';
export 'studio_patch_revision.dart'
    show debugPatchRevisionContextAttachment, debugPatchRevisionOutboundPrompt;
export 'studio_model_history.dart' show studioModelHistoryForThread;
export 'studio_plan_intent.dart'
    show
        actionablePlanForContinuation,
        isConversationalOnlyPrompt,
        isPlanApprovalOnlyText,
        isPlanImplementationContinuationText;
export 'studio_plan_interactions.dart' show handlePlanApprovalOnlyText;
export 'studio_send_result.dart';
export 'studio_turn_contracts.dart'
    show
        buildConversationalContextPayload,
        buildCustomAgentContextPayload,
        studioIntentRequiresWorkspace,
        studioOutboundPromptForIntent,
        studioOutboundPromptWithArtifactContract,
        studioToolModeForIntent;

const _uuid = Uuid();

Future<StudioSendResult> sendStudioMessage(
  WidgetRef ref,
  String text, {
  String? taskId,
  bool finishTask = false,
  AcceptedPlanContext? acceptedPlan,
  String? displayText,
  String? threadTitle,
  String? outboundTextOverride,
  bool userMessageTranscriptVisible = true,
  bool deferTaskWhenStudioBusy = false,
  IntentRoutingDecision? intentRoutingOverride,
  StudioPromptMode? promptModeOverride,
}) async {
  var visibleText = (displayText?.trim().isNotEmpty ?? false)
      ? displayText!.trim()
      : text;
  final runtime = ref.read(agentTurnRuntimeProvider.notifier);
  final beforeSend = ref.read(agentTurnRuntimeProvider);
  if (runtime.handlePendingApprovalText(text)) {
    final thread = ref.read(studioThreadProvider).selectedThread;
    if (thread != null) {
      ref
          .read(studioThreadProvider.notifier)
          .markPhase(
            thread.id,
            status: StudioThreadStatus.runningCommand,
            phase: StudioSendPhase.runningCommand,
            requestId: thread.requestId,
            model: thread.model,
            contextSummary: thread.contextSummary,
          );
    }
    return StudioSendResult.sent(
      requestId: thread?.requestId,
      threadId: thread?.id,
      taskId: taskId,
      contextSummary: thread?.contextSummary,
      registeredRequest: true,
    );
  }
  final planApprovalOnly = handlePlanApprovalOnlyText(
    ref,
    text,
    hasActiveStudioRequest: beforeSend.hasActiveStudioRequest,
    taskId: taskId,
  );
  if (planApprovalOnly != null) return planApprovalOnly;
  final planContinuation = await _handleActivePlanContinuation(
    ref,
    text,
    beforeSend,
    taskId: taskId,
    finishTask: finishTask,
  );
  if (planContinuation != null) return planContinuation;
  ref.read(workspaceSessionProvider.notifier).syncFromCurrentWorkspace();
  final studio = ref.read(studioShellProvider);
  final requestedPromptMode = promptModeOverride ?? studio.promptMode;
  var rootPath = ref.read(fileTreeProvider).rootPath;
  final directives = await extractStudioContextDirectives(
    text,
    rootPath: rootPath,
  );
  final requestText = directives.message.trim().isEmpty
      ? 'Review the attached screenshot/image context and summarize relevant findings.'
      : directives.message;
  if (!(displayText?.trim().isNotEmpty ?? false)) {
    visibleText = requestText;
  }
  final classifiedIntentDecision =
      intentRoutingOverride ??
      await runtime.resolveIntentRouting(
        prompt: requestText,
        promptMode: requestedPromptMode,
        planModeEnabled: studio.planModeEnabled,
      );
  // Accepted-plan implementation is always a Code turn. The structured plan
  // prompt may mention deferred verification, but verification must happen in a
  // separate approved Verify turn after the patch is reviewed and applied.
  final intentRouting = acceptedPlan == null
      ? classifiedIntentDecision
      : const IntentRoutingDecision(
          intent: TurnIntent.code,
          confidence: 1,
          reason: 'User accepted a reviewed implementation plan.',
          source: IntentRoutingSource.deterministic,
        );
  final intent = intentRouting.intent;
  final customAgentSelection = resolveCustomAgentSelection(
    ref.read(agentManagerProvider).configs,
    requestText: requestText,
    intent: intent,
    explicitAgentId: studio.customAgentId,
    auto: studio.autoCustomAgent,
  );
  final customAgent = customAgentSelection.agent;
  final customAgentError = customAgentValidationError(
    selectedAgentId: customAgentSelection.isAuto
        ? customAgent?.id
        : studio.customAgentId,
    customAgent: customAgent,
    intent: intent,
  );
  if (customAgentError != null) {
    return StudioSendResult.blocked(customAgentError);
  }
  final intentContract = IntentContract.forIntent(intent);
  final conversationalOnly = intent == TurnIntent.chat;
  final requiresWorkspace = studioIntentRequiresWorkspace(intent);
  final promptMode = intent == TurnIntent.chat
      ? StudioPromptMode.ask
      : requestedPromptMode;
  final planModeEnabled = intent == TurnIntent.plan;
  final model = customAgent?.model ?? ref.read(settingsProvider).ciscoModel;
  var resolvedTaskId = taskId;
  var shouldFinishTask = finishTask;
  var workspace = ref.read(workspaceSessionProvider);
  if ((rootPath == null || !workspace.canCode) &&
      promptMode.agentProfile != null &&
      intentContract.mayCreateWorkspace) {
    final path = await StudioProjectCreator.createProject(
      name: StudioProjectCreator.projectNameFromPrompt(requestText),
    );
    final openResult = await ref
        .read(workspaceSessionProvider.notifier)
        .openWorkspaceAndBindAgent(path);
    if (openResult.success) {
      rootPath = recordBoundStudioWorkspace(
        ref,
        requestedPath: path,
        binding: openResult,
      );
      workspace = ref.read(workspaceSessionProvider);
    }
  }
  if (resolvedTaskId == null &&
      studio.executionMode == StudioExecutionMode.worktree &&
      requiresWorkspace &&
      rootPath != null &&
      workspace.canCode) {
    final task = await ref
        .read(agentWorkspaceProvider.notifier)
        .startIsolatedTask(
          goal: requestText,
          profile: promptMode.agentProfile ?? AgentTaskProfile.patch,
        );
    if (task == null) {
      return StudioSendResult.blocked(
        ref.read(agentWorkspaceProvider).error ??
            'Could not create an isolated task worktree.',
      );
    }
    resolvedTaskId = task.id;
    shouldFinishTask = true;
  }
  final taskWorkspace = resolvedTaskId == null
      ? null
      : ref
            .read(agentWorkspaceProvider)
            .tasks
            .where((task) => task.id == resolvedTaskId)
            .firstOrNull;
  if (taskWorkspace?.workspaceMode == AgentTaskWorkspaceMode.isolatedWorktree &&
      !taskWorkspace!.hasUsableIsolatedWorktree) {
    return const StudioSendResult.blocked(
      'This task no longer has a usable isolated worktree. Choose the current workspace or create a new worktree before continuing.',
    );
  }
  final taskRoot = taskWorkspace?.effectiveWorkspaceRoot;
  final hasTaskWorkspace = taskRoot != null && taskRoot.trim().isNotEmpty;
  if (taskRoot != null && taskRoot.trim().isNotEmpty) {
    rootPath = taskRoot;
  }
  final patchRevisionContext = acceptedPlan == null
      ? activePatchRevisionContext(ref, requestText)
      : null;
  await ref
      .read(studioThreadProvider.notifier)
      .hydrateThreadForTask(resolvedTaskId);
  final contextThread = resolvedTaskId == null
      ? ref.read(studioThreadProvider).selectedThread
      : ref.read(studioThreadProvider).threadForTask(resolvedTaskId);
  final extraContextAttachments = [
    ...directives.attachments,
    ...browserSelectionContextAttachments(contextThread),
    if (patchRevisionContext != null) patchRevisionContext.attachment,
  ];
  final extraAllowedFileContextPaths = {
    ...acceptedPlanFileContextPaths(acceptedPlan),
    if (patchRevisionContext != null) ...patchRevisionContext.filePaths,
  };
  final payload =
      customAgent != null &&
          customAgent.contextPolicy != AgentContextPolicy.projectOnly
      ? buildCustomAgentContextPayload(
          rootPath: rootPath,
          attachments: extraContextAttachments,
          contextPolicy: customAgent.contextPolicy,
        )
      : conversationalOnly
      ? buildConversationalContextPayload(
          ref,
          extraAttachments: extraContextAttachments,
        )
      : await buildStudioContextPayloadWithFreshIndex(
          ref,
          requestText,
          workspaceRoot: rootPath,
          allowedFileContextPaths: extraAllowedFileContextPaths,
          extraAttachments: extraContextAttachments,
        );
  final outboundText =
      outboundTextOverride ??
      (patchRevisionContext == null
          ? studioOutboundPromptWithArtifactContract(
              text: requestText,
              intent: intent,
              planModeEnabled: planModeEnabled,
              promptMode: promptMode,
            )
          : patchRevisionOutboundPrompt(requestText, patchRevisionContext));
  final thread = ref
      .read(studioThreadProvider.notifier)
      .ensureThread(
        taskId: resolvedTaskId,
        title: threadTitle ?? visibleText,
        model: model,
      );
  // Custom agents are request-local. Unlike the general Studio assistant,
  // they never inherit a pre-existing Studio thread transcript.
  final priorThreadMessages = customAgent == null
      ? studioModelHistoryForThread(thread)
      : const <ChatMessage>[];
  final userMessageId = _uuid.v4();
  final requestId = _uuid.v4();
  var turnRegistered = false;

  void registerTurnIfNeeded() {
    if (turnRegistered) return;
    ref
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: resolvedTaskId,
          userMessageId: userMessageId,
          prompt: visibleText,
          modelPrompt: outboundText,
          taskTitle: threadTitle ?? visibleText,
          model: model,
          contextSummary: payload.summary,
          intent: intent,
          acceptedPlanState: acceptedPlan == null
              ? AcceptedPlanState.none
              : AcceptedPlanState.accepted,
          acceptedPlanContext: acceptedPlan,
          contextRetrieval: payload.contextRetrieval,
          intentRouting: intentRouting,
          userMessageTranscriptVisible:
              acceptedPlan == null && userMessageTranscriptVisible,
          isResearch: promptMode == StudioPromptMode.research,
        );
    turnRegistered = true;
  }

  void registerBlockedTurn(String message) {
    registerTurnIfNeeded();
    ref
        .read(studioTurnProvider.notifier)
        .fail(requestId, message, finalOutcome: StudioTurnOutcome.blocked);
  }

  if (beforeSend.hasActiveStudioRequest) {
    const message =
        'A request is already running. Wait for it to finish or cancel it before sending another.';
    registerBlockedTurn(message);
    if (shouldFinishTask &&
        resolvedTaskId != null &&
        !deferTaskWhenStudioBusy) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .failTask(resolvedTaskId, message);
    }
    return StudioSendResult.blocked(
      message,
      requestId: requestId,
      threadId: thread.id,
      taskId: resolvedTaskId,
      contextSummary: payload.summary,
      blockedByActiveRequest: true,
    );
  }

  final toolMode = studioToolModeForIntent(
    intent: intent,
    promptMode: promptMode,
    hasWorkspace: rootPath != null && (workspace.canCode || hasTaskWorkspace),
    planModeEnabled: planModeEnabled,
  );
  final preflight = await runtime.preflightMessage(
    outboundText,
    payload.attachments,
    requiresTools:
        toolMode != AgentToolMode.chat &&
        (customAgent == null || customAgent.allowedTools.isNotEmpty),
  );
  if (!preflight.canSend) {
    final message =
        preflight.primaryIssue?.message ?? 'Circuit AI is not ready.';
    final blockedByActiveRequest =
        ref.read(agentTurnRuntimeProvider).hasActiveStudioRequest ||
        preflight.issues.any(
          (issue) =>
              issue.recoveryAction ==
              AgentPreflightRecoveryAction.waitForRequest,
        );
    registerBlockedTurn(message);
    if (shouldFinishTask &&
        resolvedTaskId != null &&
        !(deferTaskWhenStudioBusy && blockedByActiveRequest)) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .failTask(resolvedTaskId, message);
    }
    return StudioSendResult.blocked(
      message,
      requestId: requestId,
      threadId: thread.id,
      taskId: resolvedTaskId,
      preflight: preflight,
      contextSummary: payload.summary,
      blockedByActiveRequest: blockedByActiveRequest,
    );
  }

  if ((rootPath == null || (!workspace.canCode && !hasTaskWorkspace)) &&
      requiresWorkspace) {
    const message =
        'Choose a bound project folder before using Code, Fix, or Review mode.';
    registerBlockedTurn(message);
    if (shouldFinishTask && resolvedTaskId != null) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .failTask(resolvedTaskId, message);
    }
    return StudioSendResult.blocked(
      message,
      requestId: requestId,
      threadId: thread.id,
      taskId: resolvedTaskId,
      contextSummary: payload.summary,
    );
  }

  ref
      .read(studioThreadProvider.notifier)
      .markPhase(
        thread.id,
        status: StudioThreadStatus.buildingContext,
        phase: StudioSendPhase.buildingContext,
        model: model,
        contextSummary: payload.summary,
      );
  ref
      .read(studioThreadProvider.notifier)
      .markPhase(
        thread.id,
        status: StudioThreadStatus.preflighting,
        phase: StudioSendPhase.preflighting,
        model: model,
        contextSummary: payload.summary,
      );
  registerTurnIfNeeded();
  ref
      .read(studioRequestLifecycleProvider.notifier)
      .registerRequest(
        requestId: requestId,
        threadId: thread.id,
        taskId: resolvedTaskId,
        model: model,
        intent: intent,
        contextSummary: payload.summary,
      );
  unawaited(
    runtime.startTurn(
      requestId: requestId,
      threadId: thread.id,
      taskId: resolvedTaskId,
      outboundText: outboundText,
      attachments: payload.attachments,
      modelHistory: priorThreadMessages,
      toolMode: toolMode,
      intent: intent,
      acceptedPlan: acceptedPlan,
      model: model,
      retryPrompt: visibleText,
      displayTitle: visibleText,
      finishTask: shouldFinishTask,
      customAgent: customAgent,
      workspaceRoot: rootPath,
    ),
  );
  return StudioSendResult.sent(
    requestId: requestId,
    threadId: thread.id,
    taskId: resolvedTaskId,
    contextSummary: payload.summary,
    registeredRequest: true,
  );
}

Future<StudioSendResult> implementPlanFromStudio(
  WidgetRef ref,
  ProposedPatchSet plan, {
  String? taskId,
  bool finishTask = false,
  AcceptedPlanContext? acceptedPlanOverride,
  String displayText = 'Implementing approved plan',
}) async {
  final shell = ref.read(studioShellProvider);
  final resolvedTaskId = taskId ?? shell.selectedTaskId;
  final acceptedPlan =
      acceptedPlanOverride ?? AcceptedPlanContext.fromPatch(plan);
  final result = await implementAcceptedPlanFromStudio(
    ref,
    acceptedPlan,
    taskId: resolvedTaskId,
    finishTask: finishTask || resolvedTaskId != null,
    displayText: displayText,
    fallbackTitle: plan.title,
  );
  if (result.registeredRequest &&
      (result.status == StudioSendStatus.sent ||
          result.status == StudioSendStatus.completed)) {
    ref.read(patchProposalProvider.notifier).markPlanAccepted(plan.id);
  } else {
    ref.read(patchProposalProvider.notifier).preserveProposal(plan);
  }
  return result;
}

Future<StudioSendResult> implementAcceptedPlanFromStudio(
  WidgetRef ref,
  AcceptedPlanContext acceptedPlan, {
  String? taskId,
  bool finishTask = false,
  String displayText = 'Implementing approved plan',
  String? fallbackTitle,
}) async {
  final shell = ref.read(studioShellProvider);
  final resolvedTaskId = taskId ?? shell.selectedTaskId;
  final shellNotifier = ref.read(studioShellProvider.notifier);
  final previousPlanMode = shell.planModeEnabled;
  final previousPromptMode = shell.promptMode;
  final selectedThread = ref.read(studioThreadProvider).selectedThread;
  shellNotifier.setPlanModeEnabled(false);
  shellNotifier.setPromptMode(StudioPromptMode.code);
  final prompt = buildPlanImplementationPrompt(acceptedPlan);
  final result = await sendStudioMessage(
    ref,
    prompt,
    taskId: resolvedTaskId,
    finishTask: finishTask || resolvedTaskId != null,
    acceptedPlan: acceptedPlan,
    displayText: displayText,
    threadTitle: selectedThread?.title ?? fallbackTitle ?? acceptedPlan.title,
    outboundTextOverride: prompt,
    userMessageTranscriptVisible: false,
  );
  if (!result.registeredRequest ||
      (result.status != StudioSendStatus.sent &&
          result.status != StudioSendStatus.completed)) {
    shellNotifier.setPlanModeEnabled(previousPlanMode);
    shellNotifier.setPromptMode(previousPromptMode);
  }
  return result;
}

Future<StudioSendResult> verifyPatchFromStudio(
  WidgetRef ref,
  ProposedPatchSet patch, {
  String? taskId,
  bool finishTask = false,
  String displayText = 'Running verification',
}) async {
  final resolvedTaskId =
      taskId ??
      ref.read(studioShellProvider).selectedTaskId ??
      patch.agentTaskId;
  return startStudioPatchVerification(
    ref,
    patch,
    taskId: resolvedTaskId,
    displayText: displayText,
    dispatchRepair: (repairPrompt) async {
      ref
          .read(studioShellProvider.notifier)
          .setPromptMode(StudioPromptMode.code);
      final repairProvider =
          ref.read(studioAgentEnvironmentOverrideProvider)?.provider ??
          ref.read(studioAgentConnectionProvider).provider;
      if (repairProvider == null) return;
      await sendStudioMessage(
        ref,
        repairPrompt,
        taskId: resolvedTaskId,
        finishTask: finishTask || resolvedTaskId != null,
        displayText: 'Repairing failed verification',
        threadTitle: patch.title,
        outboundTextOverride: repairPrompt,
        userMessageTranscriptVisible: false,
        intentRoutingOverride: const IntentRoutingDecision(
          intent: TurnIntent.code,
          confidence: 1,
          reason: 'Repairing one failed approved verification command.',
          source: IntentRoutingSource.deterministic,
        ),
      );
    },
  );
}

Future<StudioSendResult?> _handleActivePlanContinuation(
  WidgetRef ref,
  String text,
  AgentTurnRuntimeState beforeSend, {
  String? taskId,
  required bool finishTask,
}) async {
  if (!isPlanImplementationContinuationText(text)) return null;
  final thread = ref.read(studioThreadProvider).selectedThread;
  final shell = ref.read(studioShellProvider);
  final resolvedTaskId = taskId ?? shell.selectedTaskId;
  final plan = actionablePlanForContinuation(
    ref.read(patchProposalProvider),
    thread: thread,
    taskId: resolvedTaskId,
  );
  if (plan == null) return null;

  if (beforeSend.hasActiveStudioRequest) {
    const message =
        'A request is already running. Wait for it to finish or cancel it before implementing this plan.';
    if (thread != null) {
      recordBlockedSendTurn(
        ref,
        thread: thread,
        taskId: resolvedTaskId,
        prompt: text,
        message: message,
        intent: TurnIntent.code,
      );
    }
    return StudioSendResult.blocked(
      message,
      threadId: thread?.id,
      taskId: taskId,
      contextSummary: thread?.contextSummary,
      blockedByActiveRequest: true,
    );
  }

  return implementPlanFromStudio(
    ref,
    plan,
    taskId: resolvedTaskId,
    finishTask: finishTask || resolvedTaskId != null,
  );
}
