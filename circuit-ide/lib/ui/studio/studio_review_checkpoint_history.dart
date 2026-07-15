import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/checkpoint.dart';
import '../../models/reviewed_edit.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/theme_provider.dart';
import 'checkpoint_restore_dialog.dart';

/// Checkpoint history and restore controls for the compact patch-review card.
///
/// Keeping this feature separate from the active-review presentation prevents
/// restoration lifecycle behavior from coupling to diff and action rendering.
class StudioCheckpointHistory extends ConsumerWidget {
  final PatchProposalState state;

  const StudioCheckpointHistory({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final checkpoints = state.checkpoints.values.toList()
      ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceInset.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.44)),
      ),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        childrenPadding: const EdgeInsets.only(bottom: Spacing.xs),
        title: Text(
          'Checkpoint history · ${checkpoints.length}',
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          'Review and restore any saved state.',
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xxs),
        ),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 176),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: checkpoints.length,
              itemBuilder: (context, index) {
                final checkpoint = checkpoints[index];
                final patch = _checkpointPatch(state, checkpoint);
                return _CheckpointHistoryRow(
                  checkpoint: checkpoint,
                  patch: patch,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

ProposedPatchSet? _checkpointPatch(
  PatchProposalState state,
  Checkpoint checkpoint,
) {
  final id = checkpoint.patchSetId;
  final candidates = [
    if (state.active != null) state.active!,
    ...state.history,
  ];
  if (id != null) {
    return candidates.where((patch) => patch.id == id).firstOrNull;
  }
  return candidates
      .where((patch) => patch.checkpointId == checkpoint.id)
      .firstOrNull;
}

class _CheckpointHistoryRow extends ConsumerWidget {
  final Checkpoint checkpoint;
  final ProposedPatchSet? patch;

  const _CheckpointHistoryRow({required this.checkpoint, required this.patch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final task = patch?.workItemId ?? checkpoint.workItemId ?? 'Current task';
    final verification = patch?.verificationRequested == true
        ? (patch?.verificationRequestId?.trim().isEmpty ?? true)
              ? 'Verification requested'
              : 'Verification recorded'
        : 'No verification requested';
    return Container(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 3, Spacing.xs, 3),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.32)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            StudioIcons.restorePageOutlined,
            color: tokens.textMuted,
            size: 13,
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checkpoint.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_checkpointTime(checkpoint.timestamp)} · ${checkpoint.fileCount} files · $verification',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                  ),
                ),
                Text(
                  'Patch: ${patch?.title ?? 'Historical state'} · Task: $task',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => unawaited(
              previewAndRestoreCheckpoint(context, ref, checkpoint.id),
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}

String _checkpointTime(DateTime value) {
  String part(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${part(value.month)}-${part(value.day)} ${part(value.hour)}:${part(value.minute)}';
}
