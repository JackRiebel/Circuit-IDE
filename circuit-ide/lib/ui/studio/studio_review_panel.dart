import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/reviewed_edit.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_message_sender.dart';

class StudioReviewPanel extends ConsumerWidget {
  const StudioReviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final patchState = ref.watch(patchProposalProvider);
    final patch = patchState.active ?? _latestReviewablePatch(patchState);

    if (patch == null) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.difference_outlined,
              color: tokens.textMuted.withValues(alpha: 0.72),
              size: 14,
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              'No changes to review.',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 736),
        child: Container(
          margin: const EdgeInsets.all(Spacing.xl),
          decoration: BoxDecoration(
            color: tokens.studioActivityRow.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: tokens.studioDivider.withValues(alpha: 0.62),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.md,
                ),
                child: _ReviewHeader(patch: patch),
              ),
              Divider(
                height: 1,
                color: tokens.studioDivider.withValues(alpha: 0.78),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.md,
                ),
                child: Text(
                  _reviewSummary(patch),
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.32,
                  ),
                ),
              ),
              if (patch.isPlanOnly)
                for (final file in patch.plannedFiles) _PlanFileRow(path: file)
              else
                for (final edit in patch.edits)
                  _ReviewFileRow(patchId: patch.id, edit: edit),
              const SizedBox(height: Spacing.md),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                margin: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                decoration: BoxDecoration(
                  color: tokens.surfaceInset.withValues(alpha: 0.58),
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
                  child: SelectableText(
                    patch.isPlanOnly
                        ? patch.planMarkdown ?? patch.comparisonSummary ?? ''
                        : _diffPreview(patch),
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      height: 1.35,
                      fontFamily: EditorDefaults.fallbackFontFamily,
                    ),
                  ),
                ),
              ),
              if (patch.conflictMessage != null) ...[
                const SizedBox(height: Spacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: Text(
                    patch.conflictMessage!,
                    style: TextStyle(
                      color: tokens.error,
                      fontSize: FontSizes.sm,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Spacing.md),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: tokens.surfacePanel.withValues(alpha: 0.2),
                  border: Border(
                    top: BorderSide(
                      color: tokens.studioDivider.withValues(alpha: 0.66),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.sm,
                  Spacing.lg,
                  Spacing.sm,
                ),
                child: _ReviewActions(
                  patch: patch,
                  isApplying: patchState.isApplying,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _diffPreview(ProposedPatchSet patch) {
    return patch.edits
        .map((edit) {
          final before = edit.before ?? '';
          final after = edit.after ?? '';
          return [
            '--- ${edit.path}',
            '+++ ${edit.path}',
            if (edit.unifiedDiff?.isNotEmpty == true)
              edit.unifiedDiff!
            else ...[
              if (before.isNotEmpty) '- ${before.trim()}',
              if (after.isNotEmpty) '+ ${after.trim()}',
            ],
          ].join('\n');
        })
        .join('\n\n');
  }
}

ProposedPatchSet? _latestReviewablePatch(PatchProposalState state) {
  for (final patch in state.history) {
    if (patch.checkpointId != null ||
        patch.applyStatus == PatchApplyStatus.applied ||
        patch.applyStatus == PatchApplyStatus.restored ||
        patch.applyStatus == PatchApplyStatus.conflict ||
        patch.applyStatus == PatchApplyStatus.failed) {
      return patch;
    }
  }
  return null;
}

String _reviewTitle(ProposedPatchSet patch) {
  if (patch.isPlanOnly) return 'Circuit created a plan';
  return switch (patch.applyStatus) {
    PatchApplyStatus.applied => 'Applied ${patch.fileCount} files',
    PatchApplyStatus.restored => 'Checkpoint restored',
    PatchApplyStatus.conflict => 'Patch needs attention',
    PatchApplyStatus.failed => 'Patch failed',
    PatchApplyStatus.rejected => 'Patch rejected',
    null => 'Circuit wants to change ${patch.fileCount} files',
  };
}

String _reviewSummary(ProposedPatchSet patch) {
  return patch.comparisonSummary ??
      patch.planMarkdown
          ?.split('\n')
          .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '') ??
      'Review the summary, inspect the files, then apply or ask for a revision.';
}

class _ReviewHeader extends ConsumerWidget {
  final ProposedPatchSet patch;

  const _ReviewHeader({required this.patch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final status = patch.isPlanOnly
        ? 'Plan'
        : patch.applyStatus == PatchApplyStatus.applied
        ? 'Applied'
        : patch.applyStatus == PatchApplyStatus.conflict
        ? 'Needs review'
        : 'Review';
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: tokens.bgDark.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Icon(
            patch.isPlanOnly ? Icons.format_list_bulleted : Icons.difference,
            color: tokens.textMuted,
            size: 16,
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _reviewTitle(patch),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${patch.fileCount} file${patch.fileCount == 1 ? '' : 's'} · $status',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewFileRow extends ConsumerWidget {
  final String patchId;
  final ProposedFileEdit edit;

  const _ReviewFileRow({required this.patchId, required this.edit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref
            .read(studioRightDrawerProvider.notifier)
            .openPatchFile(patchId, edit.path),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: tokens.studioDivider.withValues(alpha: 0.8),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                color: tokens.textMuted,
                size: 13,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  edit.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                edit.type.name,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Icon(Icons.chevron_right, color: tokens.textMuted, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewActions extends ConsumerWidget {
  final ProposedPatchSet patch;
  final bool isApplying;

  const _ReviewActions({required this.patch, required this.isApplying});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canApply =
        patch.isPlanOnly ||
        patch.applyStatus == null ||
        patch.applyStatus == PatchApplyStatus.conflict ||
        patch.applyStatus == PatchApplyStatus.failed ||
        patch.applyStatus == PatchApplyStatus.restored;
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        if (canApply)
          FilledButton.icon(
            onPressed: isApplying
                ? null
                : patch.isPlanOnly
                ? () => unawaited(implementPlanFromStudio(ref, patch))
                : () => unawaited(
                    ref.read(patchProposalProvider.notifier).apply(patch.id),
                  ),
            icon: const Icon(Icons.check, size: 16),
            label: Text(
              isApplying
                  ? 'Applying'
                  : patch.isPlanOnly
                  ? 'Implement this plan'
                  : 'Apply changes',
            ),
          ),
        OutlinedButton.icon(
          onPressed: isApplying
              ? null
              : () => ref
                    .read(patchProposalProvider.notifier)
                    .requestRevision(
                      PatchProposalRevisionRequest(
                        patchSetId: patch.id,
                        prompt: 'Revise this patch based on user feedback.',
                      ),
                    ),
          icon: const Icon(Icons.edit_note, size: 16),
          label: const Text('Ask for revision'),
        ),
        OutlinedButton.icon(
          onPressed: isApplying
              ? null
              : () => ref.read(patchProposalProvider.notifier).rejectActive(),
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Reject'),
        ),
        if (patch.checkpointId != null)
          OutlinedButton.icon(
            onPressed: () => unawaited(
              ref
                  .read(patchProposalProvider.notifier)
                  .restoreCheckpoint(patch.checkpointId!),
            ),
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('Restore checkpoint'),
          ),
      ],
    );
  }
}

class _PlanFileRow extends ConsumerWidget {
  final String path;

  const _PlanFileRow({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            ref.read(studioRightDrawerProvider.notifier).openFile(path),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: tokens.studioDivider.withValues(alpha: 0.8),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                color: tokens.textMuted,
                size: 13,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                'planned',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Icon(Icons.chevron_right, color: tokens.textMuted, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}
