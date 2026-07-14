import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../models/command_run.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_shell.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/turn_intent.dart';
import '../../state/command_run_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_request_lifecycle_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/studio_turn_provider.dart';
import 'studio_plan_prompts.dart';
import 'studio_patch_verification.dart';
import 'studio_send_result.dart';

const _verificationUuid = Uuid();

/// Sends a focused repair turn after a scoped verification command fails.
///
/// The runner deliberately owns no provider connection. The message-sending
/// feature supplies the repair dispatch so verification remains usable with a
/// deterministic test provider and cannot select a second provider path.
typedef StudioVerificationRepairDispatcher =
    Future<void> Function(String repairPrompt);

/// Starts a persisted Verify turn and runs its already-approved commands.
///
/// This is separate from the general message sender because verification has
/// no model prompt: it creates one durable turn around an explicitly selected,
/// bounded command set. A failed command can request one Code-mode repair via
/// [dispatchRepair], while all normal command/turn ownership stays here.
Future<StudioSendResult> startStudioPatchVerification(
  WidgetRef ref,
  ProposedPatchSet patch, {
  String? taskId,
  String displayText = 'Running verification',
  required StudioVerificationRepairDispatcher dispatchRepair,
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
  final requestId = _verificationUuid.v4();
  final userMessageId = _verificationUuid.v4();
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
        modelPrompt: '',
        taskTitle: patch.title,
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
      .markProgress(
        requestId,
        title: 'Verification running',
        detail: 'Running ${commands.length} approved verification check(s).',
        status: StudioTurnStatus.verifying,
      );
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
      dispatchRepair: dispatchRepair,
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
  required StudioVerificationRepairDispatcher dispatchRepair,
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
          userApproved: true,
        );
    commandRuns.add(run);
    if (run.status != CommandRunStatus.succeeded) break;
  }
  final summary = verificationSummaryForRuns(commandRuns, commands);
  final failed = commandRuns
      .where((run) => run.status != CommandRunStatus.succeeded)
      .firstOrNull;
  ref
      .read(studioTurnProvider.notifier)
      .complete(requestId, content: '', summary: summary);
  ref
      .read(studioRequestLifecycleProvider.notifier)
      .completeRequest(requestId, message: summary);
  if (failed != null && !hasVerificationRepairRequest(patch)) {
    final repairPrompt = verificationRepairPrompt(patch, failed);
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(
            patchSetId: patch.id,
            prompt: repairPrompt,
          ),
        );
    await dispatchRepair(repairPrompt);
  }
}
