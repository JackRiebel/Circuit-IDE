import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../agent/tools/tool_registry.dart';
import '../../enums/message_role.dart';
import '../../models/agent_preflight.dart';
import '../../models/accepted_plan_context.dart';
import '../../models/chat_message.dart';
import '../../models/context_attachment.dart';
import '../../models/context_pack.dart';
import '../../models/reviewed_edit.dart';
import '../../models/specialist_agent.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/turn_intent.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/agent_turn_runtime_provider.dart';
import '../../state/context_pack_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_project_creator.dart';
import '../../state/studio_request_lifecycle_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/studio_turn_provider.dart';
import '../../state/workspace_session_provider.dart';
import 'studio_plan_prompts.dart';

const _uuid = Uuid();

enum StudioSendStatus { sent, blocked, failed, completed }

class StudioSendResult {
  final StudioSendStatus status;
  final String? requestId;
  final String? threadId;
  final String? taskId;
  final AgentPreflightResult? preflight;
  final StudioContextSummary? contextSummary;
  final String? error;
  final bool registeredRequest;
  final bool blockedByActiveRequest;

  const StudioSendResult._(
    this.status, {
    this.requestId,
    this.threadId,
    this.taskId,
    this.preflight,
    this.contextSummary,
    this.error,
    this.registeredRequest = false,
    this.blockedByActiveRequest = false,
  });

  const StudioSendResult.sent({
    String? requestId,
    String? threadId,
    String? taskId,
    StudioContextSummary? contextSummary,
    bool registeredRequest = false,
  }) : this._(
         StudioSendStatus.sent,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
         registeredRequest: registeredRequest,
       );

  const StudioSendResult.blocked(
    String message, {
    String? requestId,
    String? threadId,
    String? taskId,
    AgentPreflightResult? preflight,
    StudioContextSummary? contextSummary,
    bool blockedByActiveRequest = false,
  }) : this._(
         StudioSendStatus.blocked,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         preflight: preflight,
         contextSummary: contextSummary,
         error: message,
         blockedByActiveRequest: blockedByActiveRequest,
       );

  const StudioSendResult.failed(
    String message, {
    String? requestId,
    String? threadId,
    String? taskId,
    StudioContextSummary? contextSummary,
  }) : this._(
         StudioSendStatus.failed,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
         error: message,
       );

  const StudioSendResult.completed({
    String? requestId,
    String? threadId,
    String? taskId,
    StudioContextSummary? contextSummary,
    bool registeredRequest = false,
  }) : this._(
         StudioSendStatus.completed,
         requestId: requestId,
         threadId: threadId,
         taskId: taskId,
         contextSummary: contextSummary,
         registeredRequest: registeredRequest,
       );
}

Future<StudioSendResult> sendStudioMessage(
  WidgetRef ref,
  String text, {
  String? taskId,
  bool finishTask = false,
  AcceptedPlanContext? acceptedPlan,
}) async {
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
  final planApprovalOnly = _handlePlanApprovalOnlyText(
    ref,
    text,
    beforeSend,
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
  final intent = IntentClassifier.classify(
    text,
    promptMode: studio.promptMode,
    planModeEnabled: studio.planModeEnabled,
  );
  final intentContract = IntentContract.forIntent(intent);
  final conversationalOnly = intent == TurnIntent.chat;
  final requiresWorkspace = _intentRequiresWorkspace(intent);
  final promptMode = intent == TurnIntent.chat
      ? StudioPromptMode.ask
      : studio.promptMode;
  final planModeEnabled = intent == TurnIntent.plan;
  final model = ref.read(settingsProvider).ciscoModel;
  var rootPath = ref.read(fileTreeProvider).rootPath;
  var workspace = ref.read(workspaceSessionProvider);
  if ((rootPath == null || !workspace.canCode) &&
      promptMode.agentProfile != null &&
      intentContract.mayCreateWorkspace) {
    final path = await StudioProjectCreator.createProject(
      name: StudioProjectCreator.projectNameFromPrompt(text),
    );
    final openResult = await ref
        .read(workspaceSessionProvider.notifier)
        .openWorkspaceAndBindAgent(path);
    if (openResult.success) {
      ref.read(settingsProvider.notifier).addRecentProject(path);
      ref.read(studioShellProvider.notifier).openProject(path);
      rootPath = path;
      workspace = ref.read(workspaceSessionProvider);
    }
  }
  final payload = conversationalOnly
      ? buildConversationalContextPayload(ref)
      : await buildStudioContextPayloadWithFreshIndex(ref, text);
  final outboundText = studioOutboundPromptForIntent(
    text: text,
    intent: intent,
    planModeEnabled: planModeEnabled,
  );
  final thread = ref
      .read(studioThreadProvider.notifier)
      .ensureThread(taskId: taskId, title: text, model: model);
  final priorThreadMessages = studioModelHistoryForThread(thread);

  if (beforeSend.hasActiveStudioRequest) {
    const message =
        'A request is already running. Wait for it to finish or cancel it before sending another.';
    ref.read(studioThreadProvider.notifier).block(thread.id, message);
    if (finishTask && taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
    }
    return StudioSendResult.blocked(
      message,
      threadId: thread.id,
      taskId: taskId,
      contextSummary: payload.summary,
      blockedByActiveRequest: true,
    );
  }

  final preflight = await runtime.preflightMessage(
    outboundText,
    payload.attachments,
  );
  if (!preflight.canSend) {
    final message =
        preflight.primaryIssue?.message ?? 'Circuit AI is not ready.';
    ref
        .read(studioThreadProvider.notifier)
        .block(thread.id, message, preflight: preflight);
    if (finishTask && taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
    }
    return StudioSendResult.blocked(
      message,
      threadId: thread.id,
      taskId: taskId,
      preflight: preflight,
      contextSummary: payload.summary,
    );
  }

  if ((rootPath == null || !workspace.canCode) && requiresWorkspace) {
    const message =
        'Choose a bound project folder before using Code, Fix, or Review mode.';
    ref.read(studioThreadProvider.notifier).block(thread.id, message);
    if (finishTask && taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(taskId, message);
    }
    return StudioSendResult.blocked(
      message,
      threadId: thread.id,
      taskId: taskId,
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
  final userMessageId = _uuid.v4();

  ref
      .read(studioThreadProvider.notifier)
      .markPhase(
        thread.id,
        status: StudioThreadStatus.preflighting,
        phase: StudioSendPhase.preflighting,
        model: model,
        contextSummary: payload.summary,
      );
  final requestId = _uuid.v4();
  ref
      .read(studioTurnProvider.notifier)
      .registerTurn(
        requestId: requestId,
        threadId: thread.id,
        taskId: taskId,
        userMessageId: userMessageId,
        prompt: text,
        model: model,
        contextSummary: payload.summary,
        intent: intent,
        acceptedPlanState: acceptedPlan == null
            ? AcceptedPlanState.none
            : AcceptedPlanState.accepted,
        acceptedPlanContext: acceptedPlan,
        contextRetrieval: payload.contextRetrieval,
      );
  ref
      .read(studioRequestLifecycleProvider.notifier)
      .registerRequest(
        requestId: requestId,
        threadId: thread.id,
        taskId: taskId,
        model: model,
        contextSummary: payload.summary,
      );
  unawaited(
    runtime.startTurn(
      requestId: requestId,
      threadId: thread.id,
      taskId: taskId,
      outboundText: outboundText,
      attachments: payload.attachments,
      historyOverride: priorThreadMessages,
      toolMode: _toolModeForStudioTurn(
        intent: intent,
        promptMode: promptMode,
        hasWorkspace: rootPath != null && workspace.canCode,
        planModeEnabled: planModeEnabled,
      ),
      intent: intent,
      acceptedPlan: acceptedPlan,
      model: model,
      retryPrompt: text,
      finishTask: finishTask,
    ),
  );
  return StudioSendResult.sent(
    requestId: requestId,
    threadId: thread.id,
    taskId: taskId,
    contextSummary: payload.summary,
    registeredRequest: true,
  );
}

List<ChatMessage> studioModelHistoryForThread(StudioThread thread) {
  return _modelHistoryFromTurns(thread.turns);
}

List<ChatMessage> _modelHistoryFromTurns(List<StudioTurn> turns) {
  final sortedTurns = turns.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final history = <ChatMessage>[];
  for (final turn in sortedTurns) {
    final prompt = turn.prompt.trim();
    if (prompt.isNotEmpty) {
      history.add(
        ChatMessage(
          id: turn.userMessageId,
          role: MessageRole.user,
          content: prompt,
          timestamp: turn.createdAt,
        ),
      );
    }

    final assistantEvent = _assistantHistoryEvent(turn);
    final assistantContent = assistantEvent?.content?.trim().isNotEmpty == true
        ? assistantEvent!.content!.trim()
        : assistantEvent?.detail.trim() ?? _turnFailureHistoryDetail(turn);
    if (assistantContent.isNotEmpty) {
      history.add(
        ChatMessage(
          id: assistantEvent?.id ?? 'failure-${turn.id}',
          role: MessageRole.assistant,
          content: assistantContent,
          timestamp:
              assistantEvent?.timestamp ?? turn.completedAt ?? turn.updatedAt,
        ),
      );
    }
  }
  return history;
}

String _turnFailureHistoryDetail(StudioTurn turn) {
  if (turn.status != StudioTurnStatus.failed &&
      turn.status != StudioTurnStatus.cancelled) {
    return '';
  }
  return turn.lastError?.trim() ?? '';
}

StudioTurnEvent? _assistantHistoryEvent(StudioTurn turn) {
  final assistantEvents =
      turn.events
          .where((event) => event.type == StudioTurnEventType.assistantMessage)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (assistantEvents.isNotEmpty) return assistantEvents.last;
  if (turn.status == StudioTurnStatus.completed) {
    final summaries =
        turn.events
            .where(
              (event) => event.type == StudioTurnEventType.completionSummary,
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (summaries.isNotEmpty) return summaries.last;
  }
  if (turn.status == StudioTurnStatus.failed ||
      turn.status == StudioTurnStatus.cancelled) {
    final errors =
        turn.events
            .where((event) => event.type == StudioTurnEventType.error)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (errors.isNotEmpty) return errors.last;
  }
  return null;
}

Future<StudioSendResult> implementPlanFromStudio(
  WidgetRef ref,
  ProposedPatchSet plan, {
  String? taskId,
  bool finishTask = false,
}) async {
  final shell = ref.read(studioShellProvider);
  final resolvedTaskId = taskId ?? shell.selectedTaskId;
  final shellNotifier = ref.read(studioShellProvider.notifier);
  final previousPlanMode = shell.planModeEnabled;
  final previousPromptMode = shell.promptMode;
  shellNotifier.setPlanModeEnabled(false);
  shellNotifier.setPromptMode(StudioPromptMode.code);
  final acceptedPlan = AcceptedPlanContext.fromPatch(plan);
  final prompt = buildPlanImplementationPrompt(acceptedPlan);
  final result = await sendStudioMessage(
    ref,
    prompt,
    taskId: resolvedTaskId,
    finishTask: finishTask || resolvedTaskId != null,
    acceptedPlan: acceptedPlan,
  );
  if (result.registeredRequest &&
      (result.status == StudioSendStatus.sent ||
          result.status == StudioSendStatus.completed)) {
    ref.read(patchProposalProvider.notifier).markPlanAccepted(plan.id);
  } else {
    ref.read(patchProposalProvider.notifier).preserveProposal(plan);
    shellNotifier.setPlanModeEnabled(previousPlanMode);
    shellNotifier.setPromptMode(previousPromptMode);
  }
  return result;
}

bool isConversationalOnlyPrompt(String text) {
  return IntentClassifier.isConversational(text);
}

bool isPlanImplementationContinuationText(String text) {
  final normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const exactPhrases = {
    'do it',
    'implement',
    'implement it',
    'implement this',
    'implement this plan',
    'start implementation',
    'build it',
    'make it',
    'apply it',
    'apply this',
    'apply the plan',
    'apply this plan',
    'yes implement this plan',
    'yes apply this plan',
    'yes apply the plan',
    'can you do that',
    'could you do that',
    'would you do that',
    'please do that',
    'make that happen',
    'can you make that happen',
    'could you make that happen',
    'yes please do that',
    'sounds good do that',
    'that works do that',
    "let's do it",
    'lets do it',
  };
  if (exactPhrases.contains(normalized)) return true;
  if (RegExp(
    r'^(yes|yeah|yep|yup|sure|ok|okay|sounds\s+good|that\s+works|looks\s+good)(\s+please)?\s+(do|apply|implement|continue|proceed|start|begin|ship|make)\s+(it|this|that|the\s+plan|this\s+plan|the\s+changes|those\s+changes|these\s+changes|same\s+thing)(\s+happen)?$',
  ).hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    r'^(can|could|would|will)\s+you\s+(please\s+)?(do|apply|implement|continue|proceed|start|begin|ship|make)\s+(it|this|that|the\s+plan|this\s+plan|the\s+changes|those\s+changes|these\s+changes|what\s+you\s+suggested|what\s+you\s+recommended)(\s+happen)?(\s+please)?$',
  ).hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    r'^(please\s+)?(do|make|apply|implement)\s+(it|this|that|the\s+same\s+thing|same\s+thing)(\s+happen)?$',
  ).hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    r"^(let's|lets)\s+(do|ship|apply|implement)\s+(it|this|that|the\s+plan)?$",
  ).hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    r'^(please\s+)?(start|begin|do|apply|implement|make)\s+((with|on|from)\s+)?(the\s+changes|those\s+changes|these\s+changes|the\s+edits|those\s+edits|the\s+patch|that\s+patch|the\s+plan|that\s+plan|what\s+you\s+suggested|what\s+you\s+recommended|your\s+suggestion|your\s+recommendation|the\s+same\s+thing|same\s+as\s+above)(\s+(you\s+suggested|you\s+recommended|from\s+above|please|now))?$',
  ).hasMatch(normalized)) {
    return true;
  }
  return RegExp(
    r'^(please\s+)?(do|make|apply|implement)\s+(what\s+you\s+said|what\s+you\s+planned|what\s+you\s+proposed|those\s+suggestions|these\s+suggestions|the\s+suggested\s+changes|your\s+recommended\s+changes)(\s+(please|now))?$',
  ).hasMatch(normalized);
}

bool isPlanApprovalOnlyText(String text) {
  final normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const exactPhrases = {
    'approve',
    'approved',
    'approve it',
    'please approve',
    'please approve it',
    'approve this',
    'approve that',
    'approve the plan',
    'approve this plan',
    'approve as described',
    'please approve as described',
    'accept',
    'accepted',
    'accept it',
    'please accept',
    'please accept it',
    'accept this',
    'accept that',
    'accept the plan',
    'accept this plan',
    'accept as described',
    'please accept as described',
    'yes',
    'y',
    'yeah',
    'yep',
    'yup',
    'sure',
    'ok',
    'okay',
    'sounds good',
    'that works',
    'looks good',
    'looks good to me',
    'go ahead',
    'please proceed',
    'proceed',
    'continue',
    'continue please',
    'next',
    'next step',
    'ship it',
    'yes please',
  };
  return exactPhrases.contains(normalized);
}

ProposedPatchSet? actionablePlanForContinuation(
  PatchProposalState state, {
  StudioThread? thread,
  String? taskId,
}) {
  bool isActionablePlan(ProposedPatchSet patch) {
    final hasPlanBody =
        (patch.planMarkdown ?? '').trim().isNotEmpty ||
        patch.plannedFiles.isNotEmpty;
    if (!(patch.edits.isEmpty &&
        hasPlanBody &&
        patch.approvalStatus == PatchApprovalStatus.proposed &&
        patch.applyStatus == null)) {
      return false;
    }
    if (thread == null && taskId == null) return true;
    if (patch.agentTaskId != null) {
      return patch.agentTaskId == taskId || patch.agentTaskId == thread?.taskId;
    }
    if (patch.runId != null && thread != null) {
      return thread.turns.any((turn) => turn.requestId == patch.runId);
    }
    return false;
  }

  final active = state.active;
  if (active != null && isActionablePlan(active)) return active;
  final matches = state.history.where(isActionablePlan).toList(growable: false)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return matches.firstOrNull;
}

StudioSendResult? _handlePlanApprovalOnlyText(
  WidgetRef ref,
  String text,
  AgentTurnRuntimeState beforeSend, {
  String? taskId,
}) {
  if (!isPlanApprovalOnlyText(text)) return null;
  final thread = ref.read(studioThreadProvider).selectedThread;
  final shell = ref.read(studioShellProvider);
  final resolvedTaskId = taskId ?? shell.selectedTaskId;
  final plan = actionablePlanForContinuation(
    ref.read(patchProposalProvider),
    thread: thread,
    taskId: resolvedTaskId,
  );
  if (plan == null) return null;

  final message = beforeSend.hasActiveStudioRequest
      ? 'A request is already running. Wait for it to finish or cancel it before reviewing this plan.'
      : 'Use the plan card\'s Implement this plan button, or tell Circuit what to change in the plan.';
  if (thread != null) {
    _recordPlanGuidanceEvent(ref, thread, plan, message);
  }
  return StudioSendResult.blocked(
    message,
    threadId: thread?.id,
    taskId: taskId,
    contextSummary: thread?.contextSummary,
    blockedByActiveRequest: beforeSend.hasActiveStudioRequest,
  );
}

void _recordPlanGuidanceEvent(
  WidgetRef ref,
  StudioThread thread,
  ProposedPatchSet plan,
  String message,
) {
  final matchingTurn = plan.runId == null
      ? null
      : thread.turns.where((turn) => turn.requestId == plan.runId).firstOrNull;
  final latestTurn = thread.turns.isEmpty
      ? null
      : thread.turns.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
  final turn = matchingTurn ?? latestTurn;
  if (turn == null) return;
  ref
      .read(studioThreadProvider.notifier)
      .upsertTurnEvent(
        thread.id,
        turn.id,
        StudioTurnEvent.completionSummary(
          id: 'plan-guidance-${turn.id}',
          turnId: turn.id,
          requestId: turn.requestId,
          threadId: thread.id,
          title: 'Use the plan card',
          detail: message,
        ),
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
      ref.read(studioThreadProvider.notifier).block(thread.id, message);
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

bool studioIntentRequiresWorkspace(TurnIntent intent) =>
    _intentRequiresWorkspace(intent);

String studioOutboundPromptForIntent({
  required String text,
  required TurnIntent intent,
  required bool planModeEnabled,
}) {
  if (intent == TurnIntent.chat) return _conversationalPrompt(text);
  if (intent == TurnIntent.ask &&
      IntentClassifier.requestsStructuredAdvisoryOutput(text)) {
    return _structuredAdvisoryPrompt(text);
  }
  if (planModeEnabled || intent == TurnIntent.plan) {
    return _planModePrompt(text);
  }
  if (intent == TurnIntent.code &&
      IntentClassifier.requestsVerification(text)) {
    return _codeWithDeferredVerificationPrompt(text);
  }
  return text;
}

AgentToolMode studioToolModeForIntent({
  required TurnIntent intent,
  required StudioPromptMode promptMode,
  required bool hasWorkspace,
  required bool planModeEnabled,
}) {
  return _toolModeForStudioTurn(
    intent: intent,
    promptMode: promptMode,
    hasWorkspace: hasWorkspace,
    planModeEnabled: planModeEnabled,
  );
}

String _conversationalPrompt(String userPrompt) {
  return '''
The user sent a greeting or small-talk message:
$userPrompt

Respond briefly and conversationally. Do not inspect the project, do not mention current files or previous implementation details, do not run tools, do not propose changes, and do not infer that the user wants code written.
''';
}

String _structuredAdvisoryPrompt(String userPrompt) {
  return '''
The user asked for an advisory or visual output:
$userPrompt

Produce the answer directly in chat. Do not create files, do not propose patches, do not ask the user to type "approve", do not run shell commands, and do not claim that anything was saved.

Output contract:
- Start with the direct answer, not a plan to answer later.
- For topology, architecture, or network diagram requests, include a valid Mermaid diagram fenced as ```mermaid and label assumptions.
- For sizing, lifecycle, replacement, or architecture validation requests, include a compact comparison/requirements table and explicit assumptions.
- For business-case or company-use-case requests, include a concise use-case table, chart-ready metrics or categories when useful, and cite only sources actually available in the provided context. If live research is needed but not available in this turn, say what needs to be researched instead of inventing citations.
- End with missing inputs or follow-up questions only when they would materially change the answer.
''';
}

String _planModePrompt(String userPrompt) {
  return '''
Plan Mode is enabled for this turn.

User request:
$userPrompt

Create a reviewable implementation plan before making changes. Inspect the project as needed, then call the `propose_patch` tool with:
- `title`
- `summary`
- `plan_markdown`
- `assumptions`
- `verification_steps`
- `files` containing planned workspace-relative paths, intents, and `operation` (`create`, `modify`, or `delete`)

Do not ask the user to type "approve". Do not call write, edit, command, or git mutation tools in this planning turn. CircuitCode will render the plan with Implement / Revise / Dismiss controls.
''';
}

String _codeWithDeferredVerificationPrompt(String userPrompt) {
  return '''
The user requested an implementation and verification:
$userPrompt

This is a Code turn. Code turns may inspect files and produce a concrete `propose_patch` result only.
- Do not run shell commands, tests, builds, git mutation, write/edit tools, or `apply_patch_set` from this turn.
- First produce app-applyable file edits with `propose_patch`, or ask exactly one specific missing-context question.
- Preserve the user's verification request in the patch summary / verification suggestions.
- After the patch is reviewed and applied, CircuitCode will handle verification in a separate Verify turn with command approval.
''';
}

StudioContextPayload buildConversationalContextPayload(WidgetRef ref) {
  final rootPath = ref.read(fileTreeProvider).rootPath;
  const selection = SpecialistAgentSelection(
    requestedAgentId: SpecialistAgentId.auto,
    resolvedAgentIds: [],
    isAuto: true,
    rationale: 'Specialist routing is disabled for conversational turns.',
  );
  final summary = StudioContextSummary(
    rootPath: rootPath,
    projectLabel: rootPath == null
        ? 'No project selected'
        : p.basename(rootPath),
    includedItemCount: 0,
    estimatedTokens: 0,
    selectedFiles: const [],
    includesGit: false,
    includesTerminal: false,
    warnings: const ['conversational turn: no project context attached'],
  );
  return StudioContextPayload(
    attachments: const [],
    summary: summary,
    specialistSelection: selection,
  );
}

AgentToolMode _toolModeForPrompt(StudioPromptMode mode) {
  return switch (mode) {
    StudioPromptMode.ask => AgentToolMode.ask,
    StudioPromptMode.code => AgentToolMode.code,
    StudioPromptMode.fix => AgentToolMode.fix,
    StudioPromptMode.review => AgentToolMode.review,
  };
}

bool _intentRequiresWorkspace(TurnIntent intent) {
  return switch (intent) {
    TurnIntent.chat => false,
    TurnIntent.ask => false,
    TurnIntent.plan => true,
    TurnIntent.code => true,
    TurnIntent.review => true,
    TurnIntent.verify => true,
  };
}

AgentToolMode _toolModeForStudioTurn({
  required TurnIntent intent,
  required StudioPromptMode promptMode,
  required bool hasWorkspace,
  required bool planModeEnabled,
}) {
  if (intent == TurnIntent.chat) return AgentToolMode.chat;
  if (planModeEnabled) return AgentToolMode.plan;
  if (!hasWorkspace && !studioIntentRequiresWorkspace(intent)) {
    return AgentToolMode.chat;
  }
  if (intent == TurnIntent.ask) return AgentToolMode.ask;
  if (intent == TurnIntent.plan) return AgentToolMode.plan;
  if (intent == TurnIntent.review) return AgentToolMode.review;
  if (intent == TurnIntent.verify) return AgentToolMode.verify;
  return _toolModeForPrompt(promptMode);
}

class StudioContextPayload {
  final List<ContextAttachment> attachments;
  final StudioContextSummary summary;
  final SpecialistAgentSelection specialistSelection;
  final ContextRetrievalResult? contextRetrieval;

  const StudioContextPayload({
    required this.attachments,
    required this.summary,
    required this.specialistSelection,
    this.contextRetrieval,
  });
}

StudioContextPayload buildStudioContextPayload(WidgetRef ref, String prompt) {
  final rootPath = ref.read(fileTreeProvider).rootPath;
  const registry = SpecialistAgentRegistry();
  const selection = SpecialistAgentSelection(
    requestedAgentId: SpecialistAgentId.auto,
    resolvedAgentIds: [],
    isAuto: true,
    rationale: 'Specialist routing is disabled for the core runtime.',
  );
  final contextPack = ref
      .read(contextPackProvider.notifier)
      .buildForCodingTask(prompt: prompt);
  final attachment = _buildStudioContextAttachment(rootPath, contextPack);
  final attachments = <ContextAttachment>[
    attachment,
    if (selection.hasEnterpriseRouting)
      _buildSpecialistContextAttachment(selection, registry),
  ];
  return StudioContextPayload(
    attachments: attachments,
    summary: _buildContextSummary(
      rootPath,
      contextPack,
      attachments,
      selection,
      registry,
    ),
    specialistSelection: selection,
    contextRetrieval: contextPack.retrievalResult,
  );
}

Future<StudioContextPayload> buildStudioContextPayloadWithFreshIndex(
  WidgetRef ref,
  String prompt,
) async {
  final rootPath = ref.read(fileTreeProvider).rootPath;
  const registry = SpecialistAgentRegistry();
  const selection = SpecialistAgentSelection(
    requestedAgentId: SpecialistAgentId.auto,
    resolvedAgentIds: [],
    isAuto: true,
    rationale: 'Specialist routing is disabled for the core runtime.',
  );
  final contextPack = await ref
      .read(contextPackProvider.notifier)
      .buildForCodingTaskWithFreshIndex(prompt: prompt);
  final attachment = _buildStudioContextAttachment(rootPath, contextPack);
  final attachments = <ContextAttachment>[
    attachment,
    if (selection.hasEnterpriseRouting)
      _buildSpecialistContextAttachment(selection, registry),
  ];
  return StudioContextPayload(
    attachments: attachments,
    summary: _buildContextSummary(
      rootPath,
      contextPack,
      attachments,
      selection,
      registry,
    ),
    specialistSelection: selection,
    contextRetrieval: contextPack.retrievalResult,
  );
}

List<ContextAttachment> buildStudioContextAttachments(
  WidgetRef ref,
  String prompt,
) {
  return buildStudioContextPayload(ref, prompt).attachments;
}

ContextAttachment _buildStudioContextAttachment(
  String? rootPath,
  ContextPack contextPack,
) {
  final projectLabel = rootPath == null
      ? 'No project selected'
      : p.basename(rootPath);
  final content = [
    if (rootPath == null)
      'No project directory is selected. Ask the user to choose a project before reviewing or editing files.'
    else ...[
      'Open project directory: $rootPath',
      'Project name: $projectLabel',
      'Use this directory as the working root for all file reads, searches, commands, and edits.',
      'Do not assume a different repository unless the user explicitly asks.',
    ],
    contextPack.serializePrompt(),
  ].where((part) => part.trim().isNotEmpty).join('\n\n');

  return ContextAttachment(
    id: 'studio-project-context-${contextPack.id}',
    type: ContextAttachmentType.note,
    label: 'Project directory context',
    path: rootPath,
    content: content,
    resolutionStatus: ContextAttachmentResolutionStatus.resolved,
    estimatedTokens: (content.length / 4).ceil(),
    createdAt: DateTime.now(),
  );
}

ContextAttachment _buildSpecialistContextAttachment(
  SpecialistAgentSelection selection,
  SpecialistAgentRegistry registry,
) {
  final content = selection.toPromptBlock(registry);
  return ContextAttachment(
    id: 'enterprise-specialists-${selection.resolvedAgentIds.map((id) => id.name).join('-')}',
    type: ContextAttachmentType.note,
    label: 'Enterprise specialist routing',
    content: content,
    resolutionStatus: ContextAttachmentResolutionStatus.resolved,
    estimatedTokens: (content.length / 4).ceil(),
    createdAt: DateTime.now(),
  );
}

StudioContextSummary _buildContextSummary(
  String? rootPath,
  ContextPack contextPack,
  List<ContextAttachment> attachments,
  SpecialistAgentSelection specialistSelection,
  SpecialistAgentRegistry registry,
) {
  final files = contextPack.visibleItems
      .where(
        (item) =>
            item.type == ContextPackItemType.activeFile ||
            item.type == ContextPackItemType.selection ||
            item.type == ContextPackItemType.mentionedFile,
      )
      .map((item) => item.source ?? item.title)
      .where((value) => value.trim().isNotEmpty)
      .toSet()
      .toList();
  return StudioContextSummary(
    rootPath: rootPath,
    projectLabel: rootPath == null
        ? 'No project selected'
        : p.basename(rootPath),
    includedItemCount: contextPack.visibleItems.length,
    estimatedTokens: attachments.fold<int>(
      0,
      (sum, attachment) => sum + attachment.estimatedTokens,
    ),
    selectedFiles: files,
    includesGit: contextPack.visibleItems.any(
      (item) => item.type == ContextPackItemType.gitDiff,
    ),
    includesTerminal: contextPack.visibleItems.any(
      (item) => item.type == ContextPackItemType.terminal,
    ),
    warnings: rootPath == null
        ? const ['chat only until a project is selected']
        : const [],
    specialistLabels: specialistSelection.hasEnterpriseRouting
        ? specialistSelection
              .descriptors(registry)
              .map((descriptor) => descriptor.label)
              .toList(growable: false)
        : const [],
    specialistRouting: specialistSelection.hasEnterpriseRouting
        ? specialistSelection.rationale
        : null,
  );
}
