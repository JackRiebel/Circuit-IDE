import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_shell.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'checkpoint_restore_dialog.dart';
import 'studio_chrome.dart';
import 'studio_message_sender.dart';
import 'studio_review_checkpoint_history.dart';

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
              StudioIcons.differenceOutlined,
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
        constraints: const BoxConstraints(
          maxWidth: StudioLayoutContract.reviewWidth,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          decoration: BoxDecoration(
            color: tokens.studioActivityRow.withValues(alpha: 0.44),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: tokens.studioDivider.withValues(alpha: 0.38),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 10, 10),
                child: _ReviewHeader(patch: patch),
              ),
              Divider(
                height: 1,
                color: tokens.studioDivider.withValues(alpha: 0.52),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 8, 13, 8),
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
              const SizedBox(height: Spacing.sm),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 176),
                margin: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: tokens.surfaceInset.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(
                    color: tokens.studioDivider.withValues(alpha: 0.46),
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
                      height: 1.32,
                      fontFamily: EditorDefaults.studioMonospaceFontFamily,
                    ),
                  ),
                ),
              ),
              if (patch.conflictMessage != null) ...[
                const SizedBox(height: Spacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: Text(
                    patch.conflictMessage!,
                    style: TextStyle(
                      color: tokens.error,
                      fontSize: FontSizes.sm,
                    ),
                  ),
                ),
              ],
              if (patchState.checkpoints.isNotEmpty) ...[
                const SizedBox(height: Spacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: StudioCheckpointHistory(state: patchState),
                ),
              ],
              const SizedBox(height: Spacing.md),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: tokens.surfacePanel.withValues(alpha: 0.13),
                  border: Border(
                    top: BorderSide(
                      color: tokens.studioDivider.withValues(alpha: 0.42),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(13, 6, 10, 6),
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
        patch.applyStatus == PatchApplyStatus.revisionRequested ||
        patch.applyStatus == PatchApplyStatus.conflict ||
        patch.applyStatus == PatchApplyStatus.failed) {
      return patch;
    }
  }
  return null;
}

String _reviewTitle(ProposedPatchSet patch) {
  if (patch.isPlanOnly) return 'Plan ready';
  return switch (patch.applyStatus) {
    PatchApplyStatus.applied => 'Edited ${_fileCountLabel(patch.fileCount)}',
    PatchApplyStatus.restored => 'Checkpoint restored',
    PatchApplyStatus.revisionRequested => 'Patch revision requested',
    PatchApplyStatus.conflict => 'Patch conflict',
    PatchApplyStatus.failed => 'Patch failed',
    PatchApplyStatus.rejected => 'Patch rejected',
    null => 'Prepared ${_fileCountLabel(patch.fileCount)}',
  };
}

String _fileCountLabel(int count) => '$count file${count == 1 ? '' : 's'}';

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
        ? 'Needs rebase before apply'
        : patch.applyStatus == PatchApplyStatus.revisionRequested
        ? 'Revision requested'
        : 'Review';
    return Row(
      children: [
        Container(
          width: 25,
          height: 25,
          decoration: BoxDecoration(
            color: tokens.bgDark.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            patch.isPlanOnly
                ? StudioIcons.formatListBulleted
                : StudioIcons.difference,
            color: tokens.textMuted,
            size: 14,
          ),
        ),
        const SizedBox(width: 10),
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
                '${_fileCountLabel(patch.fileCount)} · $status',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.15,
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
    return StudioFocusableActionSurface(
      key: ValueKey('studio-review-file-$patchId-${edit.path}'),
      semanticLabel: 'Open ${edit.type.name} patch review for ${edit.path}',
      onTap: () => ref
          .read(studioRightDrawerProvider.notifier)
          .openPatchFile(patchId, edit.path),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: tokens.studioDivider.withValues(alpha: 0.48),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              StudioIcons.descriptionOutlined,
              color: tokens.textMuted,
              size: 11,
            ),
            const SizedBox(width: Spacing.sm),
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
                fontSize: FontSizes.xxs,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Icon(StudioIcons.chevronRight, color: tokens.textMuted, size: 13),
          ],
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
    final tokens = ref.watch(themeProvider);
    final canApply =
        patch.isPlanOnly ||
        (patch.approvalStatus != PatchApprovalStatus.revisionRequested &&
            (patch.applyStatus == null ||
                patch.applyStatus == PatchApplyStatus.failed ||
                patch.applyStatus == PatchApplyStatus.restored));
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (canApply)
          FilledButton.icon(
            style: _primaryActionStyle(tokens),
            onPressed: isApplying
                ? null
                : patch.isPlanOnly
                ? () => unawaited(implementPlanFromStudio(ref, patch))
                : () => unawaited(
                    ref.read(patchProposalProvider.notifier).apply(patch.id),
                  ),
            icon: const Icon(StudioIcons.check, size: 13),
            label: Text(
              isApplying
                  ? 'Applying'
                  : patch.isPlanOnly
                  ? 'Implement this plan'
                  : 'Apply changes',
            ),
          ),
        OutlinedButton.icon(
          style: _secondaryActionStyle(tokens),
          onPressed: isApplying ? null : () => _requestPatchUpdate(ref, patch),
          icon: const Icon(StudioIcons.editNote, size: 13),
          label: Text(
            patch.applyStatus == PatchApplyStatus.conflict
                ? 'Ask Circuit to rebase'
                : 'Ask for revision',
          ),
        ),
        if (patch.applyStatus == PatchApplyStatus.conflict)
          OutlinedButton.icon(
            style: _secondaryActionStyle(tokens),
            onPressed: isApplying
                ? null
                : () => _requestPatchRefresh(ref, patch),
            icon: const Icon(StudioIcons.refresh, size: 13),
            label: const Text('Refresh patch'),
          ),
        if (patch.applyStatus == PatchApplyStatus.conflict &&
            _conflictedPatchPath(patch) != null)
          OutlinedButton.icon(
            style: _secondaryActionStyle(tokens),
            onPressed: isApplying
                ? null
                : () => ref
                      .read(patchProposalProvider.notifier)
                      .skipConflictedFile(
                        patch.id,
                        _conflictedPatchPath(patch)!,
                      ),
            icon: const Icon(StudioIcons.skipNext, size: 13),
            label: const Text('Skip conflicted file'),
          ),
        OutlinedButton.icon(
          style: _subtleActionStyle(tokens),
          onPressed: isApplying
              ? null
              : () => ref.read(patchProposalProvider.notifier).reject(patch.id),
          icon: const Icon(StudioIcons.close, size: 13),
          label: const Text('Reject'),
        ),
        if (patch.checkpointId != null)
          OutlinedButton.icon(
            style: _secondaryActionStyle(tokens),
            onPressed: isApplying
                ? null
                : () => unawaited(
                    previewAndRestoreCheckpoint(
                      context,
                      ref,
                      patch.checkpointId!,
                    ),
                  ),
            icon: const Icon(StudioIcons.restore, size: 13),
            label: const Text('Restore checkpoint'),
          ),
      ],
    );
  }
}

void _requestPatchRefresh(WidgetRef ref, ProposedPatchSet patch) {
  final prompt = _refreshPrompt(patch);
  ref
      .read(patchProposalProvider.notifier)
      .requestRevision(
        PatchProposalRevisionRequest(patchSetId: patch.id, prompt: prompt),
      );
  ref.read(studioShellProvider.notifier)
    ..setPromptMode(StudioPromptMode.code)
    ..setComposerText(prompt);
}

void _requestPatchUpdate(WidgetRef ref, ProposedPatchSet patch) {
  final prompt = patch.applyStatus == PatchApplyStatus.conflict
      ? _rebasePrompt(patch)
      : 'Revise this patch based on user feedback.';
  ref
      .read(patchProposalProvider.notifier)
      .requestRevision(
        PatchProposalRevisionRequest(patchSetId: patch.id, prompt: prompt),
      );
  ref.read(studioShellProvider.notifier)
    ..setPromptMode(StudioPromptMode.code)
    ..setComposerText(prompt);
}

String _rebasePrompt(ProposedPatchSet patch) {
  final conflict = patch.conflictMessage?.trim();
  final suffix = conflict == null || conflict.isEmpty
      ? ''
      : ' Resolve: $conflict';
  return 'Refresh these proposed changes against the current files and preserve the accepted plan intent.$suffix';
}

String _refreshPrompt(ProposedPatchSet patch) {
  final conflict = patch.conflictMessage?.trim();
  final suffix = conflict == null || conflict.isEmpty
      ? ''
      : ' Resolve the current conflict: $conflict';
  return 'Refresh this patch against the current file contents without expanding scope.$suffix';
}

String? _conflictedPatchPath(ProposedPatchSet patch) {
  final message = patch.conflictMessage ?? '';
  final match = RegExp(
    r'(?:proposal|file)[^\n:]*:\s*([^\n]+)',
    caseSensitive: false,
  ).firstMatch(message);
  final path = match?.group(1)?.trim();
  if (path == null || path.isEmpty) return null;
  return patch.edits.any((edit) => edit.path == path) ? path : null;
}

ButtonStyle _primaryActionStyle(ThemeTokens tokens) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

ButtonStyle _secondaryActionStyle(ThemeTokens tokens) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    foregroundColor: tokens.textSecondary,
    side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.58)),
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

ButtonStyle _subtleActionStyle(ThemeTokens tokens) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    foregroundColor: tokens.textMuted,
    side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.34)),
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

class _PlanFileRow extends ConsumerWidget {
  final String path;

  const _PlanFileRow({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final filePath = _plannedFilePath(path);
    return StudioFocusableActionSurface(
      key: ValueKey('studio-plan-file-$filePath'),
      semanticLabel: 'Open planned file $filePath',
      onTap: () =>
          ref.read(studioRightDrawerProvider.notifier).openFile(filePath),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: tokens.studioDivider.withValues(alpha: 0.48),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              StudioIcons.descriptionOutlined,
              color: tokens.textMuted,
              size: 11,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                filePath,
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
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Icon(StudioIcons.chevronRight, color: tokens.textMuted, size: 13),
          ],
        ),
      ),
    );
  }
}

String _plannedFilePath(String plannedFile) {
  return plannedFile.split(' — ').first.split(' - ').first.trim();
}
