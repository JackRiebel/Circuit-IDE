import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../agent/tools/tool_registry.dart';
import '../../enums/message_role.dart';
import '../../models/agent_preflight.dart';
import '../../models/accepted_plan_context.dart';
import '../../models/chat_message.dart';
import '../../models/command_run.dart';
import '../../models/context_attachment.dart';
import '../../models/context_pack.dart';
import '../../models/generated_artifact.dart';
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
import '../../state/command_run_provider.dart';
import '../../state/workspace_session_provider.dart';
import '../../core/config/studio_feature_flags.dart';
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
  String? displayText,
  String? threadTitle,
  String? outboundTextOverride,
  bool userMessageTranscriptVisible = true,
}) async {
  final visibleText = (displayText?.trim().isNotEmpty ?? false)
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
  final classifiedIntent = IntentClassifier.classify(
    text,
    promptMode: studio.promptMode,
    planModeEnabled: studio.planModeEnabled,
  );
  // Accepted-plan implementation is always a Code turn. The structured plan
  // prompt may mention deferred verification, but verification must happen in a
  // separate approved Verify turn after the patch is reviewed and applied.
  final intent = acceptedPlan == null ? classifiedIntent : TurnIntent.code;
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
  final patchRevisionContext = acceptedPlan == null
      ? _activePatchRevisionContext(ref, text)
      : null;
  final extraContextAttachments = [
    if (patchRevisionContext != null) patchRevisionContext.attachment,
  ];
  final extraAllowedFileContextPaths = {
    ..._acceptedPlanFileContextPaths(acceptedPlan),
    if (patchRevisionContext != null) ...patchRevisionContext.filePaths,
  };
  final payload = conversationalOnly
      ? buildConversationalContextPayload(ref)
      : await buildStudioContextPayloadWithFreshIndex(
          ref,
          text,
          allowedFileContextPaths: extraAllowedFileContextPaths,
          extraAttachments: extraContextAttachments,
        );
  final outboundText =
      outboundTextOverride ??
      (patchRevisionContext == null
          ? _studioOutboundPromptWithArtifactContract(
              text: text,
              intent: intent,
              planModeEnabled: planModeEnabled,
            )
          : _patchRevisionOutboundPrompt(text, patchRevisionContext));
  final thread = ref
      .read(studioThreadProvider.notifier)
      .ensureThread(
        taskId: taskId,
        title: threadTitle ?? visibleText,
        model: model,
      );
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
        prompt: visibleText,
        model: model,
        contextSummary: payload.summary,
        intent: intent,
        acceptedPlanState: acceptedPlan == null
            ? AcceptedPlanState.none
            : AcceptedPlanState.accepted,
        acceptedPlanContext: acceptedPlan,
        contextRetrieval: payload.contextRetrieval,
        userMessageTranscriptVisible:
            acceptedPlan == null && userMessageTranscriptVisible,
      );
  ref
      .read(studioRequestLifecycleProvider.notifier)
      .registerRequest(
        requestId: requestId,
        threadId: thread.id,
        taskId: taskId,
        model: model,
        intent: intent,
        contextSummary: payload.summary,
      );
  unawaited(
    runtime.startTurn(
      requestId: requestId,
      threadId: thread.id,
      taskId: taskId,
      outboundText: outboundText,
      attachments: payload.attachments,
      modelHistory: priorThreadMessages,
      toolMode: _toolModeForStudioTurn(
        intent: intent,
        promptMode: promptMode,
        hasWorkspace: rootPath != null && workspace.canCode,
        planModeEnabled: planModeEnabled,
      ),
      intent: intent,
      acceptedPlan: acceptedPlan,
      model: model,
      retryPrompt: visibleText,
      displayTitle: visibleText,
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
    if (prompt.isNotEmpty && _turnHasVisibleUserMessage(turn)) {
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

bool _turnHasVisibleUserMessage(StudioTurn turn) {
  if (turn.acceptedPlanContext != null ||
      turn.acceptedPlanState != AcceptedPlanState.none) {
    return false;
  }
  final userEvents = turn.events
      .where((event) => event.type == StudioTurnEventType.userMessage)
      .toList(growable: false);
  if (userEvents.isEmpty) return true;
  return userEvents.any((event) => event.transcriptVisible);
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
  final shell = ref.read(studioShellProvider);
  final resolvedTaskId = taskId ?? shell.selectedTaskId ?? patch.agentTaskId;
  final rootPath = ref.read(fileTreeProvider).rootPath;
  final commands = patch.verificationSuggestions
      .where(isRunnableVerificationCommand)
      .toSet()
      .take(3)
      .toList(growable: false);
  if (rootPath == null || rootPath.trim().isEmpty) {
    return const StudioSendResult.failed(
      'Open a project folder before running verification.',
    );
  }
  if (commands.isEmpty) {
    return const StudioSendResult.failed(
      'No runnable verification command was available for this patch.',
    );
  }

  final shellNotifier = ref.read(studioShellProvider.notifier);
  shellNotifier.setPlanModeEnabled(false);
  shellNotifier.setPromptMode(StudioPromptMode.ask);
  final threadNotifier = ref.read(studioThreadProvider.notifier);
  final selectedThread = ref.read(studioThreadProvider).selectedThread;
  final model = selectedThread?.model ?? ref.read(settingsProvider).ciscoModel;
  final thread =
      selectedThread ??
      threadNotifier.createBlankThread(title: patch.title, model: model);
  shellNotifier.openThread(thread.id);
  final requestId = _uuid.v4();
  final userMessageId = _uuid.v4();
  final contextSummary = StudioContextSummary(
    rootPath: rootPath,
    projectLabel: p.basename(rootPath),
    includedItemCount: commands.length,
    estimatedTokens: commands.join('\n').length ~/ 4,
    selectedFiles: patch.changedFiles.isNotEmpty
        ? patch.changedFiles
        : patch.edits.map((edit) => edit.path).toList(growable: false),
  );
  final turn = ref
      .read(studioTurnProvider.notifier)
      .registerTurn(
        requestId: requestId,
        threadId: thread.id,
        taskId: resolvedTaskId,
        userMessageId: userMessageId,
        prompt: displayText,
        model: model,
        contextSummary: contextSummary,
        intent: TurnIntent.verify,
        userMessageTranscriptVisible: false,
      );
  ref
      .read(studioRequestLifecycleProvider.notifier)
      .registerRequest(
        requestId: requestId,
        threadId: thread.id,
        taskId: resolvedTaskId,
        model: model,
        intent: TurnIntent.verify,
        contextSummary: contextSummary,
      );
  ref
      .read(patchProposalProvider.notifier)
      .markVerificationStarted(patch.id, requestId);
  ref
      .read(studioTurnProvider.notifier)
      .recordStep(
        requestId,
        step: TurnStep.verification,
        status: TurnStepStatus.running,
        title: 'Verification running',
        detail: 'Running ${commands.length} approved verification check(s).',
      );
  unawaited(
    _runDeterministicPatchVerification(
      ref,
      patch: patch,
      requestId: requestId,
      threadId: thread.id,
      turnId: turn.id,
      taskId: resolvedTaskId,
      rootPath: rootPath,
      commands: commands,
    ),
  );
  return StudioSendResult.sent(
    requestId: requestId,
    threadId: thread.id,
    taskId: resolvedTaskId,
    contextSummary: contextSummary,
    registeredRequest: true,
  );
}

Future<void> _runDeterministicPatchVerification(
  WidgetRef ref, {
  required ProposedPatchSet patch,
  required String requestId,
  required String threadId,
  required String turnId,
  required String? taskId,
  required String rootPath,
  required List<String> commands,
}) async {
  final commandRuns = <CommandRun>[];
  for (var index = 0; index < commands.length; index++) {
    final command = commands[index];
    final runId = 'verify-$requestId-${index + 1}';
    final run = await ref
        .read(commandRunProvider.notifier)
        .runVerificationCommand(
          id: runId,
          command: command,
          workingDir: rootPath,
          requestId: requestId,
          turnId: turnId,
          taskId: taskId,
        );
    commandRuns.add(run);
    if (run.status != CommandRunStatus.succeeded) break;
  }
  final summary = _verificationSummaryForRuns(commandRuns, commands);
  ref
      .read(studioTurnProvider.notifier)
      .complete(requestId, content: '', summary: summary);
}

String _verificationSummaryForRuns(
  List<CommandRun> runs,
  List<String> requestedCommands,
) {
  if (runs.isEmpty) {
    return 'Verification did not run.\n\nNo command was started.';
  }
  final failed = runs
      .where((run) => run.status != CommandRunStatus.succeeded)
      .firstOrNull;
  final lines = <String>[
    failed == null ? 'Verification completed.' : 'Verification failed.',
    '',
    'Commands run:',
    for (final run in runs)
      '- `${run.command}` — ${_verificationRunStatusLabel(run)}',
  ];
  if (failed != null) {
    final outputPreview = _verificationOutputPreviewForRun(failed);
    if (outputPreview.isNotEmpty) {
      lines.addAll(['', 'Failure output:', outputPreview]);
    }
  }
  final remaining = requestedCommands.skip(runs.length).toList();
  if (remaining.isNotEmpty) {
    lines.addAll([
      '',
      'Skipped after first failure:',
      for (final command in remaining) '- `$command`',
    ]);
  }
  if (failed != null) {
    lines.addAll([
      '',
      'Next step: fix the failing command output above, then rerun verification.',
    ]);
  }
  return lines.join('\n');
}

String _verificationOutputPreviewForRun(CommandRun run) {
  final output = run.combinedOutput.trim();
  if (output.isEmpty) return '';
  const maxPreview = 900;
  final preview = output.length <= maxPreview
      ? output
      : 'Output tail (${output.length} chars total):\n${output.substring(output.length - maxPreview)}';
  return preview
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .take(24)
      .join('\n');
}

String _verificationRunStatusLabel(CommandRun run) {
  final exit = run.exitCode == null ? '' : ' (exit ${run.exitCode})';
  return switch (run.status) {
    CommandRunStatus.succeeded => 'passed$exit',
    CommandRunStatus.failed => 'failed$exit',
    CommandRunStatus.cancelled => 'cancelled',
    CommandRunStatus.timedOut => 'timed out',
    CommandRunStatus.blocked => 'blocked',
    CommandRunStatus.queued || CommandRunStatus.running => 'still running',
  };
}

Set<String> _acceptedPlanFileContextPaths(AcceptedPlanContext? acceptedPlan) {
  if (acceptedPlan == null) return const {};
  final targets = acceptedPlan.plannedTargets.isNotEmpty
      ? acceptedPlan.plannedTargets
      : [
          for (final file in acceptedPlan.plannedFiles)
            PlannedFileTarget.fromDisplayString(file),
        ];
  return {
    for (final target in targets)
      if (target.path.trim().isNotEmpty)
        p.normalize(target.path.trim()).replaceAll('\\', '/'),
  };
}

class _PatchRevisionContext {
  final ProposedPatchSet patch;
  final ContextAttachment attachment;
  final Set<String> filePaths;

  const _PatchRevisionContext({
    required this.patch,
    required this.attachment,
    required this.filePaths,
  });
}

ContextAttachment debugPatchRevisionContextAttachment(ProposedPatchSet patch) {
  final content = _patchRevisionPromptBlock(patch);
  return ContextAttachment(
    id: 'patch-revision-context-${patch.id}',
    type: ContextAttachmentType.note,
    label: 'Patch revision context',
    content: content,
    resolutionStatus: ContextAttachmentResolutionStatus.resolved,
    estimatedTokens: (content.length / 4).ceil(),
    createdAt: DateTime.now(),
  );
}

String debugPatchRevisionOutboundPrompt(
  String userPrompt,
  ProposedPatchSet patch,
) {
  return _patchRevisionOutboundPrompt(
    userPrompt,
    _PatchRevisionContext(
      patch: patch,
      attachment: debugPatchRevisionContextAttachment(patch),
      filePaths: _patchRevisionFilePaths(patch),
    ),
  );
}

_PatchRevisionContext? _activePatchRevisionContext(WidgetRef ref, String text) {
  final patch = ref.read(patchProposalProvider).active;
  if (patch == null ||
      patch.approvalStatus != PatchApprovalStatus.revisionRequested) {
    return null;
  }
  final revisionPrompt = patch.revisionPrompt?.trim();
  if (revisionPrompt == null || revisionPrompt.isEmpty) return null;
  if (!_sameRevisionRequest(text, revisionPrompt)) return null;

  final filePaths = _patchRevisionFilePaths(patch);
  return _PatchRevisionContext(
    patch: patch,
    attachment: debugPatchRevisionContextAttachment(patch),
    filePaths: filePaths,
  );
}

bool _sameRevisionRequest(String text, String revisionPrompt) {
  final normalizedText = _normalizeRevisionText(text);
  final normalizedPrompt = _normalizeRevisionText(revisionPrompt);
  if (normalizedText == normalizedPrompt) return true;
  if (normalizedText.contains(normalizedPrompt) ||
      normalizedPrompt.contains(normalizedText)) {
    return normalizedText.length > 24 && normalizedPrompt.length > 24;
  }
  return false;
}

String _normalizeRevisionText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9/._\-\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Set<String> _patchRevisionFilePaths(ProposedPatchSet patch) {
  return {
    for (final edit in patch.edits)
      if (edit.path.trim().isNotEmpty)
        p.normalize(edit.path.trim()).replaceAll('\\', '/'),
    for (final target in patch.effectivePlannedTargets)
      if (target.path.trim().isNotEmpty)
        p.normalize(target.path.trim()).replaceAll('\\', '/'),
  };
}

String _patchRevisionPromptBlock(ProposedPatchSet patch) {
  final edits = patch.edits
      .map(
        (edit) =>
            '- ${edit.path} — ${edit.type.name}${edit.conflictMessage == null ? '' : ' (${edit.conflictMessage})'}',
      )
      .join('\n');
  final targets = patch.effectivePlannedTargets
      .where((target) => target.path.trim().isNotEmpty)
      .map((target) => '- ${target.contractString}')
      .join('\n');
  final suggestions = patch.verificationSuggestions
      .map((suggestion) => '- $suggestion')
      .join('\n');
  return [
    'Patch revision request',
    'Patch id: ${patch.id}',
    'Patch title: ${patch.title}',
    if (patch.comparisonSummary?.trim().isNotEmpty == true)
      'Patch summary: ${patch.comparisonSummary!.trim()}',
    if (patch.conflictMessage?.trim().isNotEmpty == true)
      'Current conflict: ${patch.conflictMessage!.trim()}',
    if (patch.revisionPrompt?.trim().isNotEmpty == true)
      'Revision request: ${patch.revisionPrompt!.trim()}',
    if (edits.trim().isNotEmpty) 'Current proposed files:\n$edits',
    if (targets.trim().isNotEmpty) 'Accepted/planned targets:\n$targets',
    if (suggestions.trim().isNotEmpty)
      'Existing verification suggestions:\n$suggestions',
  ].where((part) => part.trim().isNotEmpty).join('\n\n');
}

String _patchRevisionOutboundPrompt(
  String userPrompt,
  _PatchRevisionContext context,
) {
  final patch = context.patch;
  return '''
The user is asking Circuit to revise a previously proposed patch:
$userPrompt

Use the attached "Patch revision context" as the source of truth.

Revision contract:
- Refresh the proposal against the current workspace files.
- Preserve the accepted plan or original task intent.
- Produce exactly one concrete `propose_patch` result with app-applyable file contents, or ask exactly one specific missing-context question.
- Do not run commands, write files directly, mutate git, apply patches, or ask the user to type approval text.
- Avoid unplanned files unless the revision request explicitly requires them.

Patch to revise: ${patch.title}
''';
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
  if (IntentClassifier.requestsBuildDiscovery(text)) {
    return _buildDiscoveryPrompt(text);
  }
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

String _studioOutboundPromptWithArtifactContract({
  required String text,
  required TurnIntent intent,
  required bool planModeEnabled,
}) {
  final prompt = studioOutboundPromptForIntent(
    text: text,
    intent: intent,
    planModeEnabled: planModeEnabled,
  );
  if (!isGeneratedArtifactRequest(text) ||
      intent == TurnIntent.chat ||
      intent == TurnIntent.review ||
      intent == TurnIntent.verify) {
    return prompt;
  }
  final kind = detectGeneratedArtifactKind(text);
  final artifactLabel = switch (kind) {
    GeneratedArtifactKind.excel => 'Excel workbook',
    GeneratedArtifactKind.csv => 'CSV',
    GeneratedArtifactKind.json => 'JSON',
    GeneratedArtifactKind.markdown => 'Markdown',
    GeneratedArtifactKind.pdf => 'PDF report',
    GeneratedArtifactKind.powerPoint => 'PowerPoint deck',
    GeneratedArtifactKind.docx => 'Word report',
    GeneratedArtifactKind.diagram => 'SVG topology diagram',
    GeneratedArtifactKind.chart => 'SVG chart artifact',
    GeneratedArtifactKind.report => 'report Markdown',
    null => 'file',
  };
  return '''
$prompt

Artifact output contract:
- The user asked for a generated $artifactLabel artifact.
- Produce concise assistant text plus clean machine-readable content when needed.
- For spreadsheet/Excel/CSV outputs, include one complete Markdown table with all required rows and columns; Circuit will save it as a workspace artifact instead of making chat the final output surface. Excel requests become real .xlsx files when table data is available.
- For solution sizing workbook outputs, include requirements, recommendations, validation checks, assumptions, and any source tables; Circuit will organize those into multi-sheet .xlsx workbooks.
- For product comparison matrix outputs, include candidate products/models, capabilities, constraints, lifecycle risk, fit score, recommendation, assumptions, and source tables; Circuit will organize those into multi-sheet .xlsx workbooks.
- For PowerPoint/deck outputs, use clear Markdown headings and concise bullets; Circuit will save that structure as a .pptx deck.
- For Word/DOCX/report outputs, use clear Markdown headings, bullets, assumptions, sources, and any useful tables; Circuit will save that structure as a .docx report.
- For PDF/report outputs, use clear Markdown headings, concise paragraphs, bullets, assumptions, sources, and any useful tables; Circuit will save that structure as a .pdf handoff report.
- For topology/network diagram outputs, include one valid Mermaid diagram fenced as ```mermaid plus a short assumptions section; Circuit will save it as an .svg diagram artifact.
- For chart/graph outputs, include at least one complete Markdown table where the first column is the label and one later column is numeric; Circuit will save it as an .svg chart artifact.
- Do not say you cannot create files unless the requested data is missing. If data is missing, ask one specific missing-data question.
- Keep the human-facing explanation short because Circuit will render a file artifact card after the turn.
''';
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

String _buildDiscoveryPrompt(String userPrompt) {
  return '''
The user described a broad product/build idea:
$userPrompt

Treat this as a product-discovery turn, not an implementation turn.
Do not create files, do not propose patches, do not inspect the workspace unless the user explicitly asks, do not run commands, and do not infer a framework or file structure.
If the user mentioned a technology or framework, treat it as a preference to validate during discovery, not permission to start coding.

Respond like a Codex-style coding partner before implementation:
- Briefly restate the likely goal in plain language.
- Identify the key decisions needed before code exists: users, inputs, outputs, workflow, data model, integrations, validation rules, and success criteria.
- Ask 3-6 concise questions that would materially change the first implementation.
- Suggest a safe next step, such as turning the answers into a plan.

Do not say that anything was built or saved.
''';
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

StudioContextPayload buildStudioContextPayload(
  WidgetRef ref,
  String prompt, {
  Set<String> allowedFileContextPaths = const {},
  List<ContextAttachment> extraAttachments = const [],
}) {
  final rootPath = ref.read(fileTreeProvider).rootPath;
  const registry = SpecialistAgentRegistry();
  final selection = _studioSpecialistSelectionForPrompt(prompt);
  final contextPack = ref
      .read(contextPackProvider.notifier)
      .buildForCodingTask(
        prompt: prompt,
        allowedFileContextPaths: allowedFileContextPaths,
      );
  final attachment = _buildStudioContextAttachment(rootPath, contextPack);
  final attachments = <ContextAttachment>[
    attachment,
    ...extraAttachments,
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
  String prompt, {
  Set<String> allowedFileContextPaths = const {},
  List<ContextAttachment> extraAttachments = const [],
}) async {
  final rootPath = ref.read(fileTreeProvider).rootPath;
  const registry = SpecialistAgentRegistry();
  final selection = _studioSpecialistSelectionForPrompt(prompt);
  final contextPack = await ref
      .read(contextPackProvider.notifier)
      .buildForCodingTaskWithFreshIndex(
        prompt: prompt,
        allowedFileContextPaths: allowedFileContextPaths,
      );
  final attachment = _buildStudioContextAttachment(rootPath, contextPack);
  final attachments = <ContextAttachment>[
    attachment,
    ...extraAttachments,
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

SpecialistAgentSelection _studioSpecialistSelectionForPrompt(String prompt) {
  if (!StudioFeatureFlags.enterpriseSpecialists) {
    return const SpecialistAgentSelection(
      requestedAgentId: SpecialistAgentId.auto,
      resolvedAgentIds: [],
      isAuto: true,
      rationale:
          'Enterprise specialist routing is disabled while Studio uses the request-local turn runtime.',
    );
  }
  return const SpecialistAgentRouter().route(prompt);
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
    omittedCandidateCount:
        contextPack.retrievalResult?.omittedCandidates.length ?? 0,
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
