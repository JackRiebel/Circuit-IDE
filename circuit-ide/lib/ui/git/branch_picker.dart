import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/git_provider.dart';
import '../../state/theme_provider.dart';

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
          InkWell(
            onTap: () => ref.read(gitProvider.notifier).refresh(),
            child: Icon(Icons.refresh, size: 14, color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}
