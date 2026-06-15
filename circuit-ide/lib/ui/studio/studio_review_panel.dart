import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/reviewed_edit.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/theme_provider.dart';

class StudioReviewPanel extends ConsumerWidget {
  const StudioReviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final patchState = ref.watch(patchProposalProvider);
    final patch = patchState.active;

    if (patch == null) {
      return Center(
        child: Text(
          'No changes are waiting for review.',
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.base),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Container(
          margin: const EdgeInsets.all(Spacing.xxxl),
          padding: const EdgeInsets.all(Spacing.xxl),
          decoration: BoxDecoration(
            color: tokens.studioPanel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tokens.studioDivider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                patch.isPlanOnly
                    ? 'Circuit created a plan'
                    : 'Circuit wants to change ${patch.fileCount} files',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.xxl,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Text(
                patch.planMarkdown ??
                    patch.comparisonSummary ??
                    'Review the summary, inspect the files, then apply or ask for a revision.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.base,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: Spacing.xl),
              if (patch.isPlanOnly)
                for (final file in patch.plannedFiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: _PlanFileRow(path: file),
                  )
              else
                for (final edit in patch.edits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: _ReviewFileRow(edit: edit),
                  ),
              const SizedBox(height: Spacing.lg),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 280),
                padding: const EdgeInsets.all(Spacing.lg),
                decoration: BoxDecoration(
                  color: tokens.surfaceInset,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: tokens.studioDivider),
                ),
                child: SingleChildScrollView(
                  child: Text(
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
                const SizedBox(height: Spacing.lg),
                Text(
                  patch.conflictMessage!,
                  style: TextStyle(color: tokens.error, fontSize: FontSizes.sm),
                ),
              ],
              const SizedBox(height: Spacing.xl),
              Wrap(
                spacing: Spacing.md,
                runSpacing: Spacing.sm,
                children: [
                  FilledButton.icon(
                    onPressed: patchState.isApplying
                        ? null
                        : patch.isPlanOnly
                        ? () => ref
                              .read(patchProposalProvider.notifier)
                              .approvePlanActive()
                        : () => unawaited(
                            ref
                                .read(patchProposalProvider.notifier)
                                .applyActive(),
                          ),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(
                      patchState.isApplying
                          ? 'Applying'
                          : patch.isPlanOnly
                          ? 'Approve plan'
                          : 'Apply changes',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: patchState.isApplying
                        ? null
                        : () => ref
                              .read(patchProposalProvider.notifier)
                              .requestRevision(
                                PatchProposalRevisionRequest(
                                  patchSetId: patch.id,
                                  prompt:
                                      'Revise this patch based on user feedback.',
                                ),
                              ),
                    icon: const Icon(Icons.edit_note, size: 16),
                    label: const Text('Ask for revision'),
                  ),
                  OutlinedButton.icon(
                    onPressed: patchState.isApplying
                        ? null
                        : () => ref
                              .read(patchProposalProvider.notifier)
                              .rejectActive(),
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

class _ReviewFileRow extends ConsumerWidget {
  final ProposedFileEdit edit;

  const _ReviewFileRow({required this.edit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: tokens.textMuted, size: 16),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              edit.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            edit.type.name,
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
          ),
        ],
      ),
    );
  }
}

class _PlanFileRow extends ConsumerWidget {
  final String path;

  const _PlanFileRow({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: tokens.textMuted, size: 16),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'planned',
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
          ),
        ],
      ),
    );
  }
}
