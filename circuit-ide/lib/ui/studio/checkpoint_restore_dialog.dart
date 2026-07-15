import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/reviewed_edit.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/theme_provider.dart';

/// Shows the complete restore scope before a checkpoint can mutate a project.
/// The controller repeats this comparison immediately before mutation, so this
/// dialog is an informed confirmation rather than a stale authorization.
Future<void> previewAndRestoreCheckpoint(
  BuildContext context,
  WidgetRef ref,
  String checkpointId,
) async {
  final controller = ref.read(patchProposalProvider.notifier);
  final preview = await controller.previewCheckpointRestore(checkpointId);
  if (!context.mounted) return;
  if (preview == null) {
    _showCheckpointResult(context, 'Checkpoint preview is not available.');
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _CheckpointRestoreDialog(preview: preview),
  );
  if (confirmed != true || !context.mounted) return;

  final result = await controller.restoreCheckpoint(
    checkpointId,
    allowOverwrite: preview.hasLaterUserChanges,
  );
  if (!context.mounted) return;
  _showCheckpointResult(
    context,
    result.status == PatchApplyStatus.restored
        ? result.message ?? 'Checkpoint restored.'
        : result.conflictMessage ??
              result.message ??
              'Checkpoint was not restored.',
  );
}

void _showCheckpointResult(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

class _CheckpointRestoreDialog extends ConsumerWidget {
  final CheckpointRestorePreview preview;

  const _CheckpointRestoreDialog({required this.preview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final patch = preview.patchSet;
    final timestamp = _checkpointTimestamp(preview.checkpoint.timestamp);
    final changedFiles = preview.files
        .where((file) => file.requiresOverwrite)
        .length;
    return AlertDialog(
      backgroundColor: tokens.surfacePanel,
      title: Text(
        'Restore checkpoint?',
        style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.md),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: StudioLayoutContract.checkpointDialogWidth,
          maxHeight: StudioLayoutContract.checkpointDialogWidth,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.checkpoint.description,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.sm,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: Spacing.md),
              _CheckpointDetail(
                label: 'Patch',
                value: patch?.title ?? 'Historical checkpoint',
              ),
              _CheckpointDetail(
                label: 'Task',
                value:
                    patch?.workItemId ??
                    preview.checkpoint.workItemId ??
                    'Current task',
              ),
              _CheckpointDetail(label: 'Saved', value: timestamp),
              _CheckpointDetail(
                label: 'Verification',
                value: preview.verificationStatus,
              ),
              const SizedBox(height: Spacing.md),
              Text(
                '${preview.fileCount} file${preview.fileCount == 1 ? '' : 's'} to restore',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              for (final file in preview.files)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        file.requiresOverwrite
                            ? StudioIcons.warningAmberRounded
                            : StudioIcons.checkCircleOutline,
                        color: file.requiresOverwrite
                            ? tokens.warning
                            : tokens.textMuted,
                        size: 14,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text(
                          file.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontFamily:
                                EditorDefaults.studioMonospaceFontFamily,
                            fontSize: FontSizes.xs,
                          ),
                        ),
                      ),
                      Text(
                        _restoreFileLabel(file),
                        style: TextStyle(
                          color: file.requiresOverwrite
                              ? tokens.warning
                              : tokens.textMuted,
                          fontSize: FontSizes.xxs,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (changedFiles > 0) ...[
                const SizedBox(height: Spacing.md),
                Text(
                  '$changedFiles file${changedFiles == 1 ? '' : 's'} changed after this patch. Restoring will overwrite those later changes only if you confirm below.',
                  style: TextStyle(
                    color: tokens.warning,
                    fontSize: FontSizes.xs,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.md),
              Text(
                'Circuit saves a reversible checkpoint of the current files before restoring.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            preview.hasLaterUserChanges
                ? 'Overwrite and restore'
                : 'Restore checkpoint',
          ),
        ),
      ],
    );
  }
}

class _CheckpointDetail extends ConsumerWidget {
  final String label;
  final String value;

  const _CheckpointDetail({required this.label, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: tokens.textSecondary, fontSize: FontSizes.xs),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: tokens.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

String _restoreFileLabel(CheckpointRestoreFilePreview file) {
  return switch (file.state) {
    CheckpointRestoreFileState.ready => 'Ready',
    CheckpointRestoreFileState.alreadyRestored => 'Already restored',
    CheckpointRestoreFileState.laterUserChange => 'Later change',
  };
}

String _checkpointTimestamp(DateTime value) {
  String part(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${part(value.month)}-${part(value.day)} ${part(value.hour)}:${part(value.minute)}';
}
