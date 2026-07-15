import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/accepted_plan_context.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/tool_result_envelope.dart';
import '../../services/verification_recipe_catalog.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import '../chat/chat_message_widget.dart';
import 'studio_message_sender.dart';
import 'studio_plan_prompts.dart' as studio_plan_prompts;
import 'studio_task_patch_controls.dart';

class StudioPatchTransactionEvidence extends ConsumerWidget {
  final ProposedPatchSet patch;

  const StudioPatchTransactionEvidence({super.key, required this.patch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final summary = (patch.diffSummary ?? '').trim();
    final verificationCommands = _runnableVerificationSuggestions(patch);
    final verificationSnapshot = ref.watch(
      studioThreadProvider.select(
        (state) =>
            _PatchVerificationSnapshot.forPatch(state.selectedThread, patch),
      ),
    );
    final verificationStatus = verificationSnapshot.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.isNotEmpty) ...[
          Text(
            'Change summary',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            summary,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              height: 1.35,
            ),
          ),
        ],
        if (verificationCommands.isNotEmpty) ...[
          if (summary.isNotEmpty) const SizedBox(height: Spacing.md),
          Text(
            patch.verificationRequested
                ? 'Verification requested'
                : 'Suggested checks',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (patch.verificationRequested) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              'Run these in a separate Verify turn after reviewing the applied patch.',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: Spacing.xs),
          for (final command in verificationCommands)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    command,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      fontFamily: EditorDefaults.studioMonospaceFontFamily,
                      height: 1.3,
                    ),
                  ),
                  Text(
                    VerificationRecipeCatalog.rationale(command),
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          if (verificationStatus != null) ...[
            const SizedBox(height: Spacing.sm),
            _PatchVerificationStatusView(status: verificationStatus),
          ],
          if (shouldOfferPatchVerification(patch) &&
              !verificationSnapshot.inFlight) ...[
            const SizedBox(height: Spacing.sm),
            FilledButton(
              style: studioPatchPrimaryActionStyle(tokens),
              onPressed: () => _runVerification(ref, patch),
              child: const Text('Run verification'),
            ),
          ],
        ],
      ],
    );
  }

  void _runVerification(WidgetRef ref, ProposedPatchSet patch) {
    final taskId =
        patch.agentTaskId ?? ref.read(studioShellProvider).selectedTaskId;
    unawaited(
      verifyPatchFromStudio(
        ref,
        patch,
        taskId: taskId,
        finishTask: taskId != null,
      ),
    );
  }
}

class StudioPatchPlanMarkdownPreview extends ConsumerWidget {
  final String markdown;
  final bool expanded;

  const StudioPatchPlanMarkdownPreview({
    super.key,
    required this.markdown,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = expanded
        ? (screenHeight * 0.42).clamp(260.0, 420.0).toDouble()
        : 132.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceInset.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.68),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            Spacing.md,
          ),
          child: MarkdownWidget(
            data: markdown,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            config: buildChatMarkdownConfig(tokens),
          ),
        ),
      ),
    );
  }
}

class _PatchVerificationStatusView extends ConsumerWidget {
  final _PatchVerificationStatus status;

  const _PatchVerificationStatusView({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = switch (status.kind) {
      _PatchVerificationStatusKind.running => tokens.textSecondary,
      _PatchVerificationStatusKind.waitingApproval => tokens.warning,
      _PatchVerificationStatusKind.passed => tokens.success,
      _PatchVerificationStatusKind.failed => tokens.error,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status.title,
            style: TextStyle(
              color: color,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (status.detail.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              status.detail,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _PatchVerificationStatusKind { running, waitingApproval, passed, failed }

class _PatchVerificationStatus {
  final _PatchVerificationStatusKind kind;
  final String title;
  final String detail;

  const _PatchVerificationStatus({
    required this.kind,
    required this.title,
    required this.detail,
  });
}

bool shouldOfferPatchVerification(ProposedPatchSet patch) {
  return patch.verificationRequested &&
      patch.applyStatus == PatchApplyStatus.applied &&
      (patch.verificationRequestId == null ||
          patch.verificationRequestId!.trim().isEmpty) &&
      _runnableVerificationSuggestions(patch).isNotEmpty;
}

List<String> _runnableVerificationSuggestions(ProposedPatchSet patch) {
  return patch.verificationSuggestions
      .where(studio_plan_prompts.isRunnableVerificationCommand)
      .toSet()
      .take(5)
      .toList(growable: false);
}

bool studioHasPatchTransactionEvidence(ProposedPatchSet patch) {
  return (patch.diffSummary ?? '').trim().isNotEmpty ||
      _runnableVerificationSuggestions(patch).isNotEmpty;
}

String buildPlanImplementationPrompt(AcceptedPlanContext plan) {
  return studio_plan_prompts.buildPlanImplementationPrompt(plan);
}

String buildPatchVerificationPrompt(ProposedPatchSet patch) {
  return studio_plan_prompts.buildPatchVerificationPrompt(patch);
}

StudioTurn? _verificationTurnForPatch(
  StudioThread? thread,
  ProposedPatchSet patch,
) {
  final requestId = patch.verificationRequestId;
  if (requestId == null || requestId.trim().isEmpty || thread == null) {
    return null;
  }
  return thread.turns.where((turn) => turn.requestId == requestId).firstOrNull;
}

bool _verificationIsInFlight(StudioTurn? turn) {
  if (turn == null) return false;
  return switch (turn.status) {
    StudioTurnStatus.queued ||
    StudioTurnStatus.buildingContext ||
    StudioTurnStatus.sent ||
    StudioTurnStatus.waitingForModel ||
    StudioTurnStatus.streaming ||
    StudioTurnStatus.toolRunning ||
    StudioTurnStatus.waitingForApproval ||
    StudioTurnStatus.verifying => true,
    StudioTurnStatus.reviewingPatch => false,
    StudioTurnStatus.completed ||
    StudioTurnStatus.failed ||
    StudioTurnStatus.cancelled ||
    StudioTurnStatus.interrupted => false,
  };
}

_PatchVerificationStatus? _verificationStatusForPatch(
  ProposedPatchSet patch,
  StudioTurn? turn,
) {
  final requestId = patch.verificationRequestId;
  if (requestId == null || requestId.trim().isEmpty) return null;
  if (turn == null) {
    return const _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.running,
      title: 'Verification started',
      detail: 'Circuit started a Verify turn for this patch.',
    );
  }
  final commandResults = turn.toolResults
      .where((result) => result.toolName == 'run_command')
      .toList(growable: false);
  final failedCommand = commandResults.where((result) {
    return result.status == ToolResultStatus.error ||
        result.status == ToolResultStatus.cancelled ||
        result.status == ToolResultStatus.denied ||
        result.status == ToolResultStatus.waitingForApproval;
  }).firstOrNull;
  final verificationStep = turn.steps
      .where((step) => step.step == TurnStep.verification)
      .lastOrNull;
  final successfulCommands = commandResults
      .where((result) => result.status == ToolResultStatus.success)
      .toList(growable: false);
  switch (turn.finalOutcome) {
    case StudioTurnOutcome.verified:
      final detail = successfulCommands.isEmpty
          ? _latestCompletionDetail(turn) ?? 'The Verify turn completed.'
          : successfulCommands.length == 1
          ? successfulCommands.single.summary
          : '${successfulCommands.length} verification commands completed.';
      return _PatchVerificationStatus(
        kind: _PatchVerificationStatusKind.passed,
        title: 'Verification completed',
        detail: detail,
      );
    case StudioTurnOutcome.blocked || StudioTurnOutcome.failed:
      return _PatchVerificationStatus(
        kind: _PatchVerificationStatusKind.failed,
        title: 'Verification failed',
        detail:
            failedCommand?.summary ??
            verificationStep?.detail ??
            turn.lastError ??
            'Verification failed.',
      );
    case StudioTurnOutcome.cancelled:
      return const _PatchVerificationStatus(
        kind: _PatchVerificationStatusKind.failed,
        title: 'Verification cancelled',
        detail: 'The Verify turn was cancelled before completion.',
      );
    case null ||
        StudioTurnOutcome.answered ||
        StudioTurnOutcome.createdArtifact ||
        StudioTurnOutcome.preparedChanges ||
        StudioTurnOutcome.appliedChanges:
      break;
  }
  final pendingApproval = turn.events.any(
    (event) =>
        event.type == StudioTurnEventType.approvalRequest &&
        event.approvalState == ApprovalRequestState.pending,
  );
  if (pendingApproval || turn.status == StudioTurnStatus.waitingForApproval) {
    return const _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.waitingApproval,
      title: 'Verification waiting for approval',
      detail: 'Review and approve the command before Circuit runs it.',
    );
  }
  if (_verificationIsInFlight(turn)) {
    return const _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.running,
      title: 'Verification running',
      detail: 'Circuit is running the approved verification turn.',
    );
  }
  if (turn.status == StudioTurnStatus.failed ||
      turn.status == StudioTurnStatus.interrupted ||
      failedCommand != null) {
    final detail = failedCommand?.summary.trim().isNotEmpty == true
        ? failedCommand!.summary
        : turn.lastError ?? _latestErrorDetail(turn) ?? 'Verification failed.';
    return _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.failed,
      title: 'Verification failed',
      detail: detail,
    );
  }
  if (turn.status == StudioTurnStatus.cancelled) {
    return const _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.failed,
      title: 'Verification cancelled',
      detail: 'The Verify turn was cancelled before completion.',
    );
  }
  if (verificationStep?.status == TurnStepStatus.failed) {
    return _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.failed,
      title: 'Verification failed',
      detail: verificationStep?.detail ?? 'Verification failed.',
    );
  }
  if (turn.status == StudioTurnStatus.completed &&
      successfulCommands.isNotEmpty) {
    final detail = successfulCommands.length == 1
        ? successfulCommands.single.summary
        : '${successfulCommands.length} verification commands completed.';
    return _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.passed,
      title: 'Verification completed',
      detail: detail,
    );
  }
  if (turn.status == StudioTurnStatus.completed) {
    return _PatchVerificationStatus(
      kind: _PatchVerificationStatusKind.passed,
      title: 'Verification completed',
      detail:
          _latestCompletionDetail(turn) ??
          'The Verify turn completed without command output.',
    );
  }
  return null;
}

class _PatchVerificationSnapshot {
  final bool inFlight;
  final _PatchVerificationStatus? status;
  final int _fingerprint;

  const _PatchVerificationSnapshot({
    required this.inFlight,
    required this.status,
    required int fingerprint,
  }) : _fingerprint = fingerprint;

  factory _PatchVerificationSnapshot.forPatch(
    StudioThread? thread,
    ProposedPatchSet patch,
  ) {
    final turn = _verificationTurnForPatch(thread, patch);
    final status = _verificationStatusForPatch(patch, turn);
    return _PatchVerificationSnapshot(
      inFlight: _verificationIsInFlight(turn),
      status: status,
      fingerprint: Object.hash(
        patch.verificationRequestId,
        turn?.id,
        turn?.status,
        turn?.lastError,
        turn?.events.length,
        turn?.toolResults.length,
        status?.kind,
        status?.title,
        status?.detail,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _PatchVerificationSnapshot &&
        _fingerprint == other._fingerprint;
  }

  @override
  int get hashCode => _fingerprint;
}

String? _latestErrorDetail(StudioTurn turn) {
  return turn.events
      .where((event) => event.type == StudioTurnEventType.error)
      .lastOrNull
      ?.detail;
}

String? _latestCompletionDetail(StudioTurn turn) {
  return turn.events
      .where((event) => event.type == StudioTurnEventType.completionSummary)
      .lastOrNull
      ?.detail;
}
