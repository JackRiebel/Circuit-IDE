import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/semantic_search_provider.dart';
import '../../state/theme_provider.dart';
import 'indexing_status_widget.dart';
import 'semantic_result_item.dart';

/// Replaces the normal search results area when semantic mode is active.
/// Shows indexing status, semantic search results, or an empty state.
class SemanticSearchPanel extends ConsumerWidget {
  const SemanticSearchPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final searchState = ref.watch(semanticSearchProvider);

    return Column(
      children: [
        // Indexing status at top
        const IndexingStatusWidget(),

        // Error message
        if (searchState.error != null)
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 14, color: tokens.warning),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    searchState.error!,
                    style: TextStyle(
                      color: tokens.warning,
                      fontSize: FontSizes.xxs,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Results or empty state
        Expanded(
          child: searchState.results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        searchState.query.isEmpty
                            ? Icons.psychology_outlined
                            : searchState.isSearching
                            ? Icons.hourglass_top
                            : Icons.search_off_outlined,
                        size: 32,
                        color: tokens.textMuted.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: Spacing.md),
                      Text(
                        searchState.query.isEmpty
                            ? 'Type a natural language query\nto search semantically'
                            : searchState.isSearching
                            ? 'Searching...'
                            : 'No results found',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.sm,
                        ),
                      ),
                      if (searchState.query.isEmpty) ...[
                        const SizedBox(height: Spacing.md),
                        Text(
                          'e.g. "function that handles user auth"',
                          style: TextStyle(
                            color: tokens.textMuted.withValues(alpha: 0.5),
                            fontSize: FontSizes.xxs,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: searchState.results.length,
                  separatorBuilder: (_, _) => Container(
                    height: 1,
                    color: tokens.border.withValues(alpha: 0.15),
                  ),
                  itemBuilder: (context, index) {
                    return SemanticResultItem(
                      result: searchState.results[index],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
