import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/search_result.dart';
import '../../state/theme_provider.dart';

class SearchResultItem extends ConsumerStatefulWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const SearchResultItem({
    super.key,
    required this.result,
    required this.onTap,
  });

  @override
  ConsumerState<SearchResultItem> createState() => _SearchResultItemState();
}

class _SearchResultItemState extends ConsumerState<SearchResultItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AnimationDurations.instant,
          color: _isHovered
              ? tokens.accent.withValues(alpha: 0.05)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: 4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.result.fileName,
                      style: TextStyle(
                        color: tokens.accent,
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.bgDark,
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Text(
                      ':${widget.result.lineNumber}',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xxs,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: widget.result.lineContent
                          .substring(0, widget.result.matchStart)
                          .trimLeft(),
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    TextSpan(
                      text: widget.result.matchText,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.xs,
                        fontFamily: 'JetBrains Mono',
                        fontWeight: FontWeight.w600,
                        backgroundColor: tokens.accent.withValues(alpha: 0.15),
                      ),
                    ),
                    TextSpan(
                      text: widget.result.lineContent.substring(
                        widget.result.matchEnd,
                      ),
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
