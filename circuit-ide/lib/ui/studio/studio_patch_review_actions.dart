import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_shell.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'checkpoint_restore_dialog.dart';

/// Approve, revise, recover, and restore the selected patch.
class StudioPatchReviewActionBar extends ConsumerWidget {
  final ProposedPatchSet patch;

  const StudioPatchReviewActionBar({super.key, required this.patch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    if (patch.isPlanOnly) {
      return _PatchReviewActionStrip(
        children: [
          Text(
            'Plan review',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    final canApply =
        patch.edits.isNotEmpty &&
        patch.approvalStatus != PatchApprovalStatus.revisionRequested &&
        patch.applyStatus != PatchApplyStatus.conflict &&
        patch.applyStatus != PatchApplyStatus.applied &&
        patch.applyStatus != PatchApplyStatus.rejected &&
        patch.applyStatus != PatchApplyStatus.revisionRequested;
    final canRestore =
        patch.checkpointId != null &&
        patch.applyStatus == PatchApplyStatus.applied;
    if (canApply) {
      return _PatchReviewActionStrip(
        children: [
          TextButton(
            style: _drawerTextActionStyle(tokens),
            onPressed: () =>
                ref.read(patchProposalProvider.notifier).reject(patch.id),
            child: const Text('Reject'),
          ),
          OutlinedButton(
            style: studioPatchSecondaryActionStyle(tokens),
            onPressed: () => _requestRevision(ref),
            child: const Text('Ask for revision'),
          ),
          FilledButton(
            style: _drawerPrimaryActionStyle(tokens),
            onPressed: () => _applyPatch(context, ref),
            child: const Text('Apply changes'),
          ),
        ],
      );
    }
    if (patch.applyStatus == PatchApplyStatus.conflict) {
      return _PatchReviewActionStrip(
        children: [
          OutlinedButton(
            style: studioPatchSecondaryActionStyle(tokens),
            onPressed: () => _openConflictFile(ref),
            child: const Text('View current file'),
          ),
          OutlinedButton(
            style: studioPatchSecondaryActionStyle(tokens),
            onPressed: () => _requestRefresh(ref),
            child: const Text('Refresh patch'),
          ),
          OutlinedButton(
            style: studioPatchSecondaryActionStyle(tokens),
            onPressed: () => _requestRebase(ref),
            child: const Text('Ask Circuit to rebase'),
          ),
          TextButton(
            style: _drawerTextActionStyle(tokens),
            onPressed: () => ref
                .read(patchProposalProvider.notifier)
                .dismissConflict(patch.id),
            child: const Text('Dismiss conflict'),
          ),
        ],
      );
    }
    if (canRestore) {
      return _PatchReviewActionStrip(
        children: [
          Text(
            'Applied',
            style: TextStyle(
              color: tokens.success,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w700,
            ),
          ),
          OutlinedButton(
            style: studioPatchSecondaryActionStyle(tokens),
            onPressed: () => _restoreCheckpoint(context, ref),
            child: const Text('Restore checkpoint'),
          ),
        ],
      );
    }
    final label = switch (patch.applyStatus) {
      PatchApplyStatus.restored => 'Checkpoint restored',
      PatchApplyStatus.rejected => 'Rejected',
      PatchApplyStatus.revisionRequested => 'Revision requested',
      PatchApplyStatus.failed => 'Apply failed',
      PatchApplyStatus.applied => 'Applied',
      PatchApplyStatus.conflict => 'Conflict',
      null => 'Review',
    };
    return _PatchReviewActionStrip(
      children: [
        Text(
          label,
          style: TextStyle(
            color: patch.applyStatus == PatchApplyStatus.failed
                ? tokens.error
                : tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _applyPatch(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(patchProposalProvider.notifier)
        .apply(patch.id);
    if (!context.mounted) return;
    _showPatchSnack(
      context,
      result.applied
          ? result.message ?? 'Applied ${result.changedFiles.length} files.'
          : result.conflictMessage ?? result.message ?? 'Patch not applied.',
    );
  }

  Future<void> _restoreCheckpoint(BuildContext context, WidgetRef ref) async {
    final checkpointId = patch.checkpointId;
    if (checkpointId == null) return;
    await previewAndRestoreCheckpoint(context, ref, checkpointId);
  }

  void _requestRevision(WidgetRef ref) {
    const prompt = 'Revise these proposed changes. Change: ';
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(patchSetId: patch.id, prompt: prompt),
        );
    ref.read(studioShellProvider.notifier)
      ..setPromptMode(StudioPromptMode.code)
      ..setComposerText(prompt);
  }

  void _requestRebase(WidgetRef ref) {
    final conflict = patch.conflictMessage?.trim();
    final prompt =
        'Refresh these proposed changes against the current files and preserve the accepted plan intent.'
        '${conflict == null || conflict.isEmpty ? '' : ' Resolve: $conflict'}';
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(patchSetId: patch.id, prompt: prompt),
        );
    ref.read(studioShellProvider.notifier)
      ..setPromptMode(StudioPromptMode.code)
      ..setComposerText(prompt);
  }

  void _requestRefresh(WidgetRef ref) {
    final conflict = patch.conflictMessage?.trim();
    final prompt =
        'Refresh this patch against the current file contents without expanding scope.'
        '${conflict == null || conflict.isEmpty ? '' : ' Resolve the current conflict: $conflict'}';
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(patchSetId: patch.id, prompt: prompt),
        );
    ref.read(studioShellProvider.notifier)
      ..setPromptMode(StudioPromptMode.code)
      ..setComposerText(prompt);
  }

  void _openConflictFile(WidgetRef ref) {
    final path = _primaryConflictPath(patch);
    if (path == null) return;
    ref.read(studioRightDrawerProvider.notifier).openFile(path);
  }
}

class _PatchReviewActionStrip extends ConsumerWidget {
  final List<Widget> children;

  const _PatchReviewActionStrip({required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      color: tokens.surfacePanel.withValues(alpha: 0.24),
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 7, Spacing.sm, 7),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

String? _primaryConflictPath(ProposedPatchSet patch) {
  final message = patch.conflictMessage?.trim();
  if (message != null && message.isNotEmpty) {
    final match = RegExp(r':\s*([^\n]+)').firstMatch(message);
    final parsed = match?.group(1)?.trim();
    if (parsed != null && parsed.isNotEmpty) return parsed;
  }
  return patch.edits.firstOrNull?.path;
}

void _showPatchSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

ButtonStyle _drawerPrimaryActionStyle(ThemeTokens tokens) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

/// Compact secondary action styling shared by patch-review states.
ButtonStyle studioPatchSecondaryActionStyle(ThemeTokens tokens) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    visualDensity: VisualDensity.compact,
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

ButtonStyle _drawerTextActionStyle(ThemeTokens tokens) {
  return TextButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 0),
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
