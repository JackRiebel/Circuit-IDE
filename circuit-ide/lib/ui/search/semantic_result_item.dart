import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/semantic_search_models.dart';
import '../../state/editor_provider.dart';
import '../../state/theme_provider.dart';

/// A single semantic search result card showing chunk info, relevance
/// score, AI explanation, and a code preview.
class SemanticResultItem extends ConsumerStatefulWidget {
  final SemanticSearchResult result;

  const SemanticResultItem({
    super.key,
    required this.result,
  });

  @override
  ConsumerState<SemanticResultItem> createState() => _SemanticResultItemState();
}

class _SemanticResultItemState extends ConsumerState<SemanticResultItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final chunk = widget.result.chunk;
    final score = widget.result.score;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          ref.read(editorProvider.notifier).openFile(chunk.filePath);
        },
        child: AnimatedContainer(
          duration: AnimationDurations.instant,
          color: _isHovered
              ? tokens.accent.withValues(alpha: 0.05)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: type badge + file path + line range
              Row(
                children: [
                  _TypeBadge(type: chunk.type, tokens: tokens),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      chunk.name,
                      style: TextStyle(
                        color: tokens.accent,
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w600,
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
                      '${chunk.startLine}-${chunk.endLine}',
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

              // File path
              Text(
                p.basename(chunk.filePath),
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                ),
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: Spacing.sm),

              // Relevance score bar
              _ScoreBar(score: score, tokens: tokens),

              // AI explanation (if available)
              if (widget.result.explanation != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  widget.result.explanation!,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xxs,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: Spacing.sm),

              // Code preview (first 3-5 lines)
              _CodePreview(
                content: chunk.content,
                tokens: tokens,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Badge showing the chunk type with an appropriate icon.
class _TypeBadge extends StatelessWidget {
  final ChunkType type;
  final dynamic tokens;

  const _TypeBadge({required this.type, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (type) {
      ChunkType.function => (Icons.functions, 'fn'),
      ChunkType.classDecl => (Icons.class_, 'class'),
      ChunkType.method => (Icons.code, 'method'),
      ChunkType.block => (Icons.segment, 'block'),
      ChunkType.imports => (Icons.input, 'imports'),
      ChunkType.topLevel => (Icons.layers, 'top'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(
          color: tokens.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: tokens.accent),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              color: tokens.accent,
              fontSize: FontSizes.xxs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin colored relevance score bar.
class _ScoreBar extends StatelessWidget {
  final double score;
  final dynamic tokens;

  const _ScoreBar({required this.score, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final color = score >= 0.7
        ? tokens.success as Color
        : score >= 0.4
            ? tokens.warning as Color
            : tokens.error as Color;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.xs),
            child: LinearProgressIndicator(
              value: score,
              minHeight: 2,
              backgroundColor: tokens.border.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Text(
          '${(score * 100).toInt()}%',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xxs,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ],
    );
  }
}

/// Shows the first 3-5 lines of code in monospace with muted color.
class _CodePreview extends StatelessWidget {
  final String content;
  final dynamic tokens;

  const _CodePreview({required this.content, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final previewLines = lines.take(4).join('\n');
    final hasMore = lines.length > 4;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: tokens.editorBg,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(
          color: tokens.border.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        hasMore ? '$previewLines\n...' : previewLines,
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: FontSizes.xxs,
          fontFamily: 'JetBrains Mono',
          height: 1.4,
        ),
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
