import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/utils/debouncer.dart';
import '../../state/search_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/semantic_search_provider.dart';
import '../../state/theme_provider.dart';
import 'indexing_status_widget.dart';
import 'search_result_item.dart';
import 'semantic_search_panel.dart';

class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({super.key});

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  final _controller = TextEditingController();
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 300));
  final _semanticDebouncer = Debouncer(
    delay: const Duration(milliseconds: 600),
  );

  @override
  void dispose() {
    _controller.dispose();
    _debouncer.dispose();
    _semanticDebouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final searchState = ref.watch(searchProvider);
    final semanticState = ref.watch(semanticSearchProvider);
    final isSemanticMode = semanticState.isSemanticMode;
    final isSearching = isSemanticMode
        ? semanticState.isSearching
        : searchState.isSearching;

    return Column(
      children: [
        // Search input
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                ),
                decoration: InputDecoration(
                  hintText: isSemanticMode
                      ? 'Search with AI...'
                      : 'Search files...',
                  prefixIcon: Icon(
                    isSemanticMode ? Icons.psychology : Icons.search,
                    size: 15,
                    color: isSemanticMode ? tokens.accent : tokens.textMuted,
                  ),
                  suffixIcon: isSearching
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: tokens.accent,
                            ),
                          ),
                        )
                      : null,
                ),
                onChanged: (value) {
                  if (isSemanticMode) {
                    _semanticDebouncer.call(() {
                      ref.read(semanticSearchProvider.notifier).search(value);
                    });
                  } else {
                    _debouncer.call(() {
                      ref.read(searchProvider.notifier).search(value);
                    });
                  }
                },
              ),
              const SizedBox(height: Spacing.sm),
              // Search options
              Row(
                children: [
                  _OptionChip(
                    label: 'Aa',
                    tooltip: 'Match Case',
                    isActive: searchState.caseSensitive,
                    onTap: () => ref
                        .read(searchProvider.notifier)
                        .setCaseSensitive(!searchState.caseSensitive),
                  ),
                  const SizedBox(width: 4),
                  _OptionChip(
                    label: '.*',
                    tooltip: 'Use Regex',
                    isActive: searchState.isRegex,
                    onTap: () => ref
                        .read(searchProvider.notifier)
                        .setRegex(!searchState.isRegex),
                  ),
                  const SizedBox(width: 4),
                  _OptionChip(
                    label: 'AI',
                    tooltip: 'Semantic Search',
                    isActive: isSemanticMode,
                    onTap: () => ref
                        .read(semanticSearchProvider.notifier)
                        .toggleSemanticMode(),
                  ),
                  const Spacer(),
                  if (!isSemanticMode && searchState.totalMatches > 0)
                    Text(
                      '${searchState.totalMatches} results in ${searchState.filesSearched} files',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xxs,
                        letterSpacing: 0.1,
                      ),
                    ),
                  if (isSemanticMode && semanticState.results.isNotEmpty)
                    Text(
                      '${semanticState.results.length} results',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xxs,
                        letterSpacing: 0.1,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Container(height: 1, color: tokens.border.withValues(alpha: 0.3)),

        // Indexing status (shown above results when indexing)
        if (isSemanticMode && semanticState.isIndexing)
          const IndexingStatusWidget(),

        // Results
        if (isSemanticMode)
          const Expanded(child: SemanticSearchPanel())
        else
          Expanded(
            child: searchState.results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          searchState.query.isEmpty
                              ? Icons.search_outlined
                              : Icons.search_off_outlined,
                          size: 32,
                          color: tokens.textMuted.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: Spacing.md),
                        Text(
                          searchState.query.isEmpty
                              ? 'Type to search'
                              : 'No results found',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: FontSizes.sm,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: searchState.results.length,
                    itemBuilder: (context, index) {
                      return SearchResultItem(
                        result: searchState.results[index],
                        onTap: () {
                          ref
                              .read(editorProvider.notifier)
                              .openFile(searchState.results[index].filePath);
                        },
                      );
                    },
                  ),
          ),
      ],
    );
  }
}

class _OptionChip extends ConsumerStatefulWidget {
  final String label;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  ConsumerState<_OptionChip> createState() => _OptionChipState();
}

class _OptionChipState extends ConsumerState<_OptionChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AnimationDurations.fast,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? tokens.accent.withValues(alpha: 0.15)
                  : _isHovered
                  ? tokens.accent.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(
                color: widget.isActive
                    ? tokens.accent.withValues(alpha: 0.5)
                    : tokens.border.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.isActive ? tokens.accent : tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
