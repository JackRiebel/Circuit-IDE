import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';

/// A horizontally scrollable, line-virtualized read-only document projection.
///
/// Shared by code, patch, and artifact previews so large text never creates a
/// widget subtree per line outside the visible viewport.
class StudioVirtualizedTextDocumentBody extends ConsumerStatefulWidget {
  final String text;
  final EdgeInsets padding;

  const StudioVirtualizedTextDocumentBody({
    super.key,
    required this.text,
    required this.padding,
  });

  @override
  ConsumerState<StudioVirtualizedTextDocumentBody> createState() =>
      _StudioVirtualizedTextDocumentBodyState();
}

class _StudioVirtualizedTextDocumentBodyState
    extends ConsumerState<StudioVirtualizedTextDocumentBody> {
  late List<String> _lines;
  late int _maxLineLength;

  @override
  void initState() {
    super.initState();
    _prepareLines();
  }

  @override
  void didUpdateWidget(covariant StudioVirtualizedTextDocumentBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _prepareLines();
    }
  }

  void _prepareLines() {
    final text = widget.text.isEmpty ? '(empty)' : widget.text;
    _lines = text.split('\n');
    _maxLineLength = 0;
    for (final line in _lines) {
      if (line.length > _maxLineLength) _maxLineLength = line.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final lineNumberWidth = (_lines.length + 1).toString().length * 7.0 + 28;
    return LayoutBuilder(
      builder: (context, constraints) {
        final estimatedTextWidth =
            (_maxLineLength * 7.1) + lineNumberWidth + 48;
        final contentWidth = estimatedTextWidth
            .clamp(constraints.maxWidth, 2200.0)
            .toDouble();
        return Scrollbar(
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              child: ListView.builder(
                key: const ValueKey('studio-virtualized-text-lines'),
                padding: widget.padding,
                itemCount: _lines.length,
                itemBuilder: (context, index) {
                  final line = _lines[index];
                  return _StudioVirtualizedTextLine(
                    lineNumber: index + 1,
                    lineNumberWidth: lineNumberWidth,
                    line: line,
                    tokens: tokens,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StudioVirtualizedTextLine extends StatelessWidget {
  final int lineNumber;
  final double lineNumberWidth;
  final String line;
  final ThemeTokens tokens;

  const _StudioVirtualizedTextLine({
    required this.lineNumber,
    required this.lineNumberWidth,
    required this.line,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final color = _lineColor(line, tokens);
    return SizedBox(
      height: 19,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: lineNumberWidth,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: tokens.textMuted.withValues(alpha: 0.56),
                fontSize: FontSizes.xs,
                height: 1.42,
                fontFamily: EditorDefaults.studioMonospaceFontFamily,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              line.isEmpty ? ' ' : line,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: color,
                fontSize: FontSizes.xs,
                height: 1.42,
                fontFamily: EditorDefaults.studioMonospaceFontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _lineColor(String line, ThemeTokens tokens) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return tokens.success.withValues(alpha: 0.92);
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return tokens.error.withValues(alpha: 0.92);
    }
    if (line.startsWith('@@')) {
      return tokens.accent.withValues(alpha: 0.9);
    }
    if (line.startsWith('diff ') ||
        line.startsWith('index ') ||
        line.startsWith('+++') ||
        line.startsWith('---')) {
      return tokens.textMuted;
    }
    return tokens.textSecondary;
  }
}
