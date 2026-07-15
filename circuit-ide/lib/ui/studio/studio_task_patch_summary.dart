import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_shell.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'checkpoint_restore_dialog.dart';
import 'studio_message_sender.dart';
import 'studio_plan_continuation.dart';
import 'studio_task_patch_controls.dart';
import 'studio_task_patch_evidence.dart';
import 'studio_task_patch_files.dart';
import 'studio_task_patch_status.dart';
import 'studio_task_plan_continuation_card.dart';

class StudioPatchSummaryCard extends ConsumerStatefulWidget {
  final ProposedPatchSet patch;

  const StudioPatchSummaryCard({super.key, required this.patch});

  @override
  ConsumerState<StudioPatchSummaryCard> createState() =>
      _StudioPatchSummaryCardState();
}

class _StudioPatchSummaryCardState
    extends ConsumerState<StudioPatchSummaryCard> {
  bool _expanded = false;
  late final FocusNode _rejectFocusNode;
  late final FocusNode _revisionFocusNode;
  late final FocusNode _applyFocusNode;

  @override
  void initState() {
    super.initState();
    _rejectFocusNode = FocusNode(debugLabel: 'studio-patch-reject');
    _revisionFocusNode = FocusNode(debugLabel: 'studio-patch-revision');
    _applyFocusNode = FocusNode(debugLabel: 'studio-patch-apply');
  }

  @override
  void dispose() {
    _rejectFocusNode.dispose();
    _revisionFocusNode.dispose();
    _applyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final patch = widget.patch;
    final isPlan = patch.isPlanOnly;
    final isAcceptedPlan =
        isPlan && patch.approvalStatus == PatchApprovalStatus.approved;
    final canApply =
        !isPlan &&
        patch.edits.isNotEmpty &&
        patch.approvalStatus != PatchApprovalStatus.revisionRequested &&
        patch.applyStatus != PatchApplyStatus.conflict &&
        patch.applyStatus != PatchApplyStatus.applied &&
        patch.applyStatus != PatchApplyStatus.rejected &&
        patch.applyStatus != PatchApplyStatus.revisionRequested;
    final canRestore =
        !isPlan &&
        patch.checkpointId != null &&
        patch.applyStatus == PatchApplyStatus.applied;
    final continuation = studioPlanContinuationForPatch(
      patch: patch,
      threads: ref.read(studioThreadProvider).threads,
    );
    final delta = studioPatchDelta(patch);
    final title = isPlan
        ? isAcceptedPlan
              ? 'Plan accepted'
              : 'Plan ready'
        : patch.applyStatus == PatchApplyStatus.applied
        ? 'Edited ${studioFormatFileCount(patch.fileCount)}'
        : patch.applyStatus == PatchApplyStatus.restored
        ? 'Restored ${studioFormatFileCount(patch.changedFiles.length)}'
        : patch.applyStatus == PatchApplyStatus.conflict
        ? 'Patch conflict'
        : patch.applyStatus == PatchApplyStatus.revisionRequested
        ? 'Revision requested'
        : 'Prepared ${studioFormatFileCount(patch.fileCount)}';
    final statusNote = studioPatchHeaderStatusNote(patch);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: StudioLayoutContract.reviewWidth,
        ),
        margin: const EdgeInsets.only(bottom: 22),
        decoration: BoxDecoration(
          color: tokens.studioCard.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.surfaceInset.withValues(alpha: 0.66),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          isPlan
                              ? StudioIcons.altRouteOutlined
                              : StudioIcons.differenceOutlined,
                          color: tokens.textMuted,
                          size: 13,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: FontSizes.sm,
                                height: 1.18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (delta.additions > 0 || delta.deletions > 0) ...[
                              const SizedBox(height: 2),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '+${delta.additions}',
                                      style: TextStyle(color: tokens.success),
                                    ),
                                    const TextSpan(text: ' '),
                                    TextSpan(
                                      text: '-${delta.deletions}',
                                      style: TextStyle(color: tokens.error),
                                    ),
                                  ],
                                ),
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: FontSizes.xs,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (statusNote != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                statusNote,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      patch.applyStatus ==
                                          PatchApplyStatus.conflict
                                      ? tokens.warning
                                      : tokens.textMuted,
                                  fontSize: FontSizes.xs,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: Spacing.sm,
                    runSpacing: 6,
                    children: [
                      if (canApply) ...[
                        TextButton(
                          style: studioPatchTextActionStyle(tokens),
                          focusNode: _rejectFocusNode,
                          onPressed: () => _rejectPatch(ref),
                          child: const Text('Reject'),
                        ),
                        OutlinedButton(
                          style: studioPatchSecondaryActionStyle(tokens),
                          focusNode: _revisionFocusNode,
                          onPressed: () =>
                              patch.applyStatus == PatchApplyStatus.conflict
                              ? _rebasePatch(ref)
                              : _revisePatch(ref),
                          child: Text(
                            patch.applyStatus == PatchApplyStatus.conflict
                                ? 'Ask Circuit to rebase'
                                : 'Ask for revision',
                          ),
                        ),
                        FilledButton(
                          style: studioPatchPrimaryActionStyle(tokens),
                          focusNode: _applyFocusNode,
                          onPressed: () => _applyPatch(ref),
                          child: const Text('Apply changes'),
                        ),
                      ] else ...[
                        if (!isPlan &&
                            patch.applyStatus == PatchApplyStatus.conflict) ...[
                          OutlinedButton(
                            style: studioPatchSecondaryActionStyle(tokens),
                            onPressed: () => _viewConflictFile(ref),
                            child: const Text('View current file'),
                          ),
                          OutlinedButton(
                            style: studioPatchSecondaryActionStyle(tokens),
                            onPressed: () => _refreshPatch(ref),
                            child: const Text('Refresh patch'),
                          ),
                          OutlinedButton(
                            style: studioPatchSecondaryActionStyle(tokens),
                            onPressed: () => _rebasePatch(ref),
                            child: const Text('Ask Circuit to rebase'),
                          ),
                          TextButton(
                            style: studioPatchTextActionStyle(tokens),
                            onPressed: () => _dismissConflict(ref),
                            child: const Text('Dismiss conflict'),
                          ),
                        ],
                        if (canRestore)
                          OutlinedButton(
                            style: studioPatchSecondaryActionStyle(tokens),
                            onPressed: () => _restoreCheckpoint(ref),
                            child: const Text('Restore checkpoint'),
                          ),
                        StudioPatchActionButton(
                          onPressed: isPlan
                              ? () => setState(() => _expanded = true)
                              : () => _openPatchReview(ref),
                          label: isPlan ? 'View plan' : 'Review',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Divider(
              color: tokens.studioDivider.withValues(alpha: 0.34),
              height: 1,
            ),
            for (final file in studioPatchFiles(patch))
              StudioPatchFileRow(patch: patch, file: file),
            if (!isPlan && studioPatchStatusDetail(patch) != null) ...[
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.34),
                height: 1,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Text(
                  studioPatchStatusDetail(patch)!,
                  style: TextStyle(
                    color: patch.applyStatus == PatchApplyStatus.conflict
                        ? tokens.warning
                        : tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (!isPlan && studioHasPatchTransactionEvidence(patch)) ...[
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.34),
                height: 1,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: StudioPatchTransactionEvidence(patch: patch),
              ),
            ],
            if (continuation != null) ...[
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.34),
                height: 1,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: StudioPlanContinuationCard(
                  continuation: continuation,
                  onContinue: () => _continueNextPlanBatch(ref, continuation),
                ),
              ),
            ],
            if (isPlan) ...[
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.34),
                height: 1,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((patch.comparisonSummary ?? '').trim().isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(Spacing.md),
                        decoration: BoxDecoration(
                          color: tokens.surfacePanel.withValues(alpha: 0.34),
                          borderRadius: BorderRadius.circular(Radii.lg),
                          border: Border.all(
                            color: tokens.studioDivider.withValues(alpha: 0.62),
                          ),
                        ),
                        child: Text(
                          patch.comparisonSummary!.trim(),
                          maxLines: _expanded ? null : 3,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: FontSizes.sm,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: Spacing.md),
                    ],
                    if ((patch.planMarkdown ?? '').trim().isNotEmpty) ...[
                      Row(
                        children: [
                          Text(
                            'Plan preview',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FontSizes.xs,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: tokens.studioDivider.withValues(
                                alpha: 0.58,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      StudioPatchPlanMarkdownPreview(
                        markdown: patch.planMarkdown!,
                        expanded: _expanded,
                      ),
                    ],
                    if ((patch.planMarkdown ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: Spacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: studioPatchTextActionStyle(tokens),
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          icon: Icon(
                            _expanded
                                ? StudioIcons.unfoldLess
                                : StudioIcons.unfoldMore,
                            size: 15,
                          ),
                          label: Text(
                            _expanded ? 'Collapse plan' : 'Expand plan',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: tokens.surfacePanel.withValues(alpha: 0.22),
                  border: Border(
                    top: BorderSide(
                      color: tokens.studioDivider.withValues(alpha: 0.68),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  7,
                  Spacing.lg,
                  7,
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    TextButton(
                      style: studioPatchTextActionStyle(tokens),
                      onPressed: () => ref
                          .read(patchProposalProvider.notifier)
                          .reject(widget.patch.id),
                      child: const Text('Dismiss'),
                    ),
                    OutlinedButton(
                      style: studioPatchSecondaryActionStyle(tokens),
                      onPressed: () => _revisePlan(ref),
                      child: const Text('Tell Circuit what to change'),
                    ),
                    if (!isAcceptedPlan)
                      FilledButton(
                        style: studioPatchPrimaryActionStyle(tokens),
                        onPressed: () => _implementPlan(ref),
                        child: const Text('Implement this plan'),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _implementPlan(WidgetRef ref) {
    unawaited(
      implementPlanFromStudio(
        ref,
        widget.patch,
        taskId: widget.patch.agentTaskId,
        finishTask: widget.patch.agentTaskId != null,
      ),
    );
  }

  void _revisePlan(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(
            patchSetId: widget.patch.id,
            prompt: 'Revise this plan. Change: ',
          ),
        );
    shellNotifier.setPlanModeEnabled(true);
    shellNotifier.setComposerText('Revise this plan. Change: ');
  }

  void _openPatchReview(WidgetRef ref) {
    final firstEdit = widget.patch.edits.firstOrNull;
    if (firstEdit != null) {
      ref
          .read(studioRightDrawerProvider.notifier)
          .openPatchFile(widget.patch.id, firstEdit.path);
      return;
    }
    ref
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.diff);
  }

  void _continueNextPlanBatch(
    WidgetRef ref,
    StudioPlanContinuationSummary continuation,
  ) {
    unawaited(
      implementPlanFromStudio(
        ref,
        widget.patch,
        taskId: widget.patch.agentTaskId,
        finishTask: widget.patch.agentTaskId != null,
        acceptedPlanOverride: continuation.acceptedPlan,
        displayText: 'Continuing approved plan',
      ),
    );
  }

  Future<void> _applyPatch(WidgetRef ref) async {
    final result = await ref
        .read(patchProposalProvider.notifier)
        .apply(widget.patch.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          result.applied
              ? result.message ?? 'Applied ${result.changedFiles.length} files.'
              : result.conflictMessage ??
                    result.message ??
                    'Patch not applied.',
        ),
      ),
    );
  }

  Future<void> _restoreCheckpoint(WidgetRef ref) async {
    final checkpointId = widget.patch.checkpointId;
    if (checkpointId == null) return;
    await previewAndRestoreCheckpoint(context, ref, checkpointId);
  }

  void _rejectPatch(WidgetRef ref) {
    ref.read(patchProposalProvider.notifier).reject(widget.patch.id);
  }

  void _revisePatch(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(
            patchSetId: widget.patch.id,
            prompt: 'Revise these proposed changes. Change: ',
          ),
        );
    shellNotifier.setPromptMode(StudioPromptMode.code);
    shellNotifier.setComposerText('Revise these proposed changes. Change: ');
  }

  void _rebasePatch(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
    final conflict = widget.patch.conflictMessage?.trim();
    final prompt =
        'Refresh these proposed changes against the current files and preserve the accepted plan intent.'
        '${conflict == null || conflict.isEmpty ? '' : ' Resolve: $conflict'}';
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(
            patchSetId: widget.patch.id,
            prompt: prompt,
          ),
        );
    shellNotifier.setPromptMode(StudioPromptMode.code);
    shellNotifier.setComposerText(prompt);
  }

  void _refreshPatch(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
    final conflict = widget.patch.conflictMessage?.trim();
    final prompt =
        'Refresh this patch against the current file contents without expanding scope.'
        '${conflict == null || conflict.isEmpty ? '' : ' Resolve the current conflict: $conflict'}';
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(
            patchSetId: widget.patch.id,
            prompt: prompt,
          ),
        );
    shellNotifier.setPromptMode(StudioPromptMode.code);
    shellNotifier.setComposerText(prompt);
  }

  void _viewConflictFile(WidgetRef ref) {
    final path = studioPatchPrimaryConflictPath(widget.patch);
    if (path == null) return;
    ref.read(studioRightDrawerProvider.notifier).openFile(path);
  }

  void _dismissConflict(WidgetRef ref) {
    ref.read(patchProposalProvider.notifier).dismissConflict(widget.patch.id);
  }
}
