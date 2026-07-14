import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../models/reviewed_edit.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/turn_intent.dart';
import '../../state/file_tree_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/studio_turn_provider.dart';
import 'studio_plan_intent.dart';
import 'studio_send_result.dart';

const _uuid = Uuid();

StudioSendResult? handlePlanApprovalOnlyText(
  WidgetRef ref,
  String text, {
  required bool hasActiveStudioRequest,
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

  final message = hasActiveStudioRequest
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
    blockedByActiveRequest: hasActiveStudioRequest,
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

void recordBlockedSendTurn(
  WidgetRef ref, {
  required StudioThread thread,
  required String? taskId,
  required String prompt,
  required String message,
  required TurnIntent intent,
}) {
  final rootPath = ref.read(fileTreeProvider).rootPath;
  final requestId = _uuid.v4();
  final userMessageId = _uuid.v4();
  ref
      .read(studioTurnProvider.notifier)
      .registerTurn(
        requestId: requestId,
        threadId: thread.id,
        taskId: taskId,
        userMessageId: userMessageId,
        prompt: prompt,
        model: thread.model ?? ref.read(settingsProvider).ciscoModel,
        contextSummary:
            thread.contextSummary ?? _fallbackContextSummary(rootPath),
        intent: intent,
      );
  ref
      .read(studioTurnProvider.notifier)
      .fail(requestId, message, finalOutcome: StudioTurnOutcome.blocked);
}

StudioContextSummary _fallbackContextSummary(String? rootPath) {
  final estimatedTokens = rootPath == null ? 0 : (rootPath.length / 4).ceil();
  return StudioContextSummary(
    projectLabel: rootPath == null
        ? 'No project selected'
        : p.basename(rootPath),
    rootPath: rootPath,
    includedItemCount: rootPath == null ? 0 : 1,
    estimatedTokens: estimatedTokens,
  );
}
