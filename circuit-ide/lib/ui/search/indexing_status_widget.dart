import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/semantic_search_provider.dart';
import '../../state/theme_provider.dart';

/// Compact indexing progress indicator shown at the top of the search panel
/// while the semantic index is being built.
class IndexingStatusWidget extends ConsumerWidget {
  const IndexingStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final searchState = ref.watch(semanticSearchProvider);

    if (!searchState.isIndexing) return const SizedBox.shrink();

    final progress = searchState.totalFileCount > 0
        ? searchState.indexedFileCount / searchState.totalFileCount
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.accent.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(
            color: tokens.border.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Text(
                searchState.totalFileCount > 0
                    ? 'Indexing... ${searchState.indexedFileCount}/${searchState.totalFileCount} files'
                    : 'Indexing...',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xs),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: tokens.border.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
            ),
          ),
        ],
      ),
    );
  }
}
