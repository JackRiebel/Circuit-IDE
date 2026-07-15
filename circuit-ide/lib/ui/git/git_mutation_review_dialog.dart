import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/git_models.dart';
import '../../state/git_provider.dart';

/// Presents the exact Git mutation preview before the notifier can apply it.
/// This is the common confirmation boundary for stage, discard, commit,
/// branch, and push actions in the product UI.
Future<GitMutationResult?> reviewAndApplyGitMutation(
  BuildContext context,
  WidgetRef ref,
  Future<GitMutationPreview> previewFuture,
) async {
  final preview = await previewFuture;
  if (!context.mounted) return null;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(preview.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(preview.blockedReason ?? preview.summary),
              if (preview.affectedPaths.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Files: ${preview.affectedPaths.join(', ')}'),
              ],
              const SizedBox(height: 12),
              Text(
                'Undo guidance: ${preview.undoGuidance}',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              if (preview.diffPreview.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Preview'),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: Theme.of(
                    dialogContext,
                  ).colorScheme.surfaceContainerHighest,
                  child: SelectableText(
                    preview.diffPreview.length > 12000
                        ? '${preview.diffPreview.substring(0, 12000)}\n… preview truncated'
                        : preview.diffPreview,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(preview.canApply ? 'Cancel' : 'Close'),
        ),
        if (preview.canApply)
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_confirmationLabel(preview.type)),
          ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;
  final result = await ref
      .read(gitProvider.notifier)
      .applyPreview(preview, confirmed: true);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.evidence)));
  }
  return result;
}

String _confirmationLabel(GitMutationType type) => switch (type) {
  GitMutationType.stage => 'Stage file',
  GitMutationType.unstage => 'Unstage file',
  GitMutationType.discardFile => 'Discard changes',
  GitMutationType.discardHunk => 'Discard hunk',
  GitMutationType.commit => 'Create commit',
  GitMutationType.createBranch => 'Create branch',
  GitMutationType.push => 'Push branch',
};
