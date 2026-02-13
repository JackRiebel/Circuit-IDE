import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/git_models.dart';
import '../../state/git_provider.dart';
import '../../state/theme_provider.dart';

class CommitHistory extends ConsumerWidget {
  const CommitHistory({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final git = ref.watch(gitProvider);

    if (git.recentCommits.isEmpty) {
      return Center(
        child: Text(
          'No commits yet',
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }

    return ListView.builder(
      itemCount: git.recentCommits.length,
      itemBuilder: (context, index) {
        final commit = git.recentCommits[index];
        return _CommitItem(commit: commit);
      },
    );
  }
}

class _CommitItem extends ConsumerWidget {
  final GitCommit commit;

  const _CommitItem({required this.commit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            commit.shortHash,
            style: TextStyle(
              color: tokens.accent,
              fontSize: FontSizes.xs,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  commit.message,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${commit.author} - ${_formatDate(commit.date)}',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }
}
