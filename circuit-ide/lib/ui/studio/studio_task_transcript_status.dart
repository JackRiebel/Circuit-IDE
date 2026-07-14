import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/studio_turn.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'studio_message_sender.dart';

class StudioTaskTranscriptEvent extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;

  const StudioTaskTranscriptEvent({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Semantics(
      container: true,
      label: 'Task event: $title${detail.trim().isEmpty ? '' : '. $detail'}',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  icon,
                  color: tokens.textMuted.withValues(alpha: 0.76),
                  size: 13,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xs,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detail.trim().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted.withValues(alpha: 0.82),
                          fontSize: FontSizes.xs,
                          height: 1.24,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudioTaskRecoveryCard extends ConsumerWidget {
  final StudioTurn turn;
  final String? taskId;

  const StudioTaskRecoveryCard({
    super.key,
    required this.turn,
    required this.taskId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final checkpoint = turn.recoveryCheckpoint!;
    final detail = _detailFor(checkpoint);
    return Semantics(
      container: true,
      label:
          'Interrupted task recovery. Last phase ${checkpoint.phase.name}. ${checkpoint.actionLabel}. $detail',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: StudioLayoutContract.proseWidth,
          ),
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: tokens.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: tokens.warning.withValues(alpha: 0.32)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Task interrupted — ${checkpoint.actionLabel}',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                detail,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextButton.icon(
                style: _recoveryTextActionStyle(tokens),
                onPressed: () => unawaited(_resume(ref, checkpoint)),
                icon: const Icon(StudioIcons.replayOutlined, size: 15),
                label: Text(checkpoint.actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _detailFor(StudioTurnRecoveryCheckpoint checkpoint) {
    final phase = checkpoint.phase.name;
    if (checkpoint.pendingApprovalId != null) {
      return 'CircuitCode closed during $phase while awaiting approval for ${checkpoint.pendingToolName ?? 'a tool'}. The old approval expired; retry will request a new approval.';
    }
    if (checkpoint.commandRunId != null) {
      return 'CircuitCode closed during $phase after recording a command run. Retry will create a new verification request and require approval again.';
    }
    if (checkpoint.patchSetId != null) {
      return 'CircuitCode closed during $phase with reviewable patch ${checkpoint.patchSetId}. Review the saved patch before any further work.';
    }
    final streamed = checkpoint.streamedCharacters;
    return streamed == 0
        ? 'CircuitCode closed during $phase before the task completed. Retry starts a new safe request using the saved prompt.'
        : 'CircuitCode closed during $phase after $streamed streamed characters. Retry starts a new safe request using the saved prompt.';
  }

  Future<void> _resume(
    WidgetRef ref,
    StudioTurnRecoveryCheckpoint checkpoint,
  ) async {
    switch (checkpoint.action) {
      case StudioTurnRecoveryAction.reviewPatch:
        final patchSetId = checkpoint.patchSetId;
        if (patchSetId != null && patchSetId.trim().isNotEmpty) {
          ref
              .read(studioRightDrawerProvider.notifier)
              .openPatchReview(patchSetId);
          return;
        }
        break;
      case StudioTurnRecoveryAction.continuePlan:
        final acceptedPlan = turn.acceptedPlanContext;
        if (acceptedPlan != null) {
          await implementAcceptedPlanFromStudio(
            ref,
            acceptedPlan,
            taskId: taskId,
            finishTask: taskId != null,
            displayText: 'Continuing recovered plan',
          );
          return;
        }
        break;
      case StudioTurnRecoveryAction.retryTurn:
      case StudioTurnRecoveryAction.rerunVerification:
        break;
    }
    final prompt = turn.displayPrompt.trim();
    if (prompt.isEmpty) return;
    await sendStudioMessage(
      ref,
      prompt,
      taskId: taskId,
      finishTask: taskId != null,
    );
  }
}

ButtonStyle _recoveryTextActionStyle(ThemeTokens tokens) {
  return TextButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    visualDensity: VisualDensity.compact,
    foregroundColor: tokens.textSecondary,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}
