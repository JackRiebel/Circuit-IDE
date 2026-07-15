import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/git_provider.dart';
import '../../state/theme_provider.dart';
import 'git_mutation_review_dialog.dart';

class BranchPicker extends ConsumerWidget {
  const BranchPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final git = ref.watch(gitProvider);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Row(
        children: [
          Icon(Icons.account_tree, size: 14, color: tokens.accent),
          const SizedBox(width: 6),
          Text(
            git.status.branch.isEmpty ? 'No branch' : git.status.branch,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.sm,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Create branch',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, size: 15, color: tokens.textMuted),
            onPressed: () => unawaited(_createBranch(context, ref)),
          ),
          IconButton(
            tooltip: 'Review push',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.upload_outlined,
              size: 15,
              color: tokens.textMuted,
            ),
            onPressed: () => unawaited(
              reviewAndApplyGitMutation(
                context,
                ref,
                ref.read(gitProvider.notifier).previewPush(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh repository status',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.refresh, size: 15, color: tokens.textMuted),
            onPressed: () => ref.read(gitProvider.notifier).refresh(),
          ),
        ],
      ),
    );
  }

  Future<void> _createBranch(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final branch = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create branch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'feature/descriptive-name',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Review branch'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (branch == null || branch.trim().isEmpty || !context.mounted) return;
    await reviewAndApplyGitMutation(
      context,
      ref,
      ref.read(gitProvider.notifier).previewCreateBranch(branch),
    );
  }
}
