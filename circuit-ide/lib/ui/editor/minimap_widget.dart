import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/syntax_theme.dart';

class MinimapWidget extends StatelessWidget {
  final String content;
  final int totalLines;
  final int visibleStartLine;
  final int visibleEndLine;
  final double width;
  final ValueChanged<int>? onLineSelected;
  final SyntaxTheme? syntaxTheme;
  final Color? bgColor;
  final Color? viewportColor;

  const MinimapWidget({
    super.key,
    required this.content,
    required this.totalLines,
    required this.visibleStartLine,
    required this.visibleEndLine,
    this.width = 60,
    this.onLineSelected,
    this.syntaxTheme,
    this.bgColor,
    this.viewportColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vpColor = viewportColor ?? theme.colorScheme.onSurface;

    return SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight;
          final lineHeight = min(maxHeight / max(totalLines, 1), 3.0);
          final viewportTop = visibleStartLine * lineHeight;
          final viewportHeight =
              (visibleEndLine - visibleStartLine) * lineHeight;

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTapDown: (details) {
                final line = (details.localPosition.dy / lineHeight).floor();
                onLineSelected?.call(line.clamp(0, totalLines - 1));
              },
              onVerticalDragUpdate: (details) {
                final line = (details.localPosition.dy / lineHeight).floor();
                onLineSelected?.call(line.clamp(0, totalLines - 1));
              },
              child: Container(
                color: bgColor ?? theme.scaffoldBackgroundColor,
                child: Stack(
                  children: [
                    // Minimap lines with syntax coloring
                    CustomPaint(
                      size: Size(width, maxHeight),
                      painter: _MinimapPainter(
                        content: content,
                        totalLines: totalLines,
                        lineHeight: lineHeight,
                        syntaxTheme: syntaxTheme,
                        defaultColor:
                            vpColor.withValues(alpha: 0.35),
                      ),
                    ),
                    // Viewport indicator
                    Positioned(
                      top: viewportTop.clamp(0.0, maxHeight - 20),
                      left: 0,
                      right: 0,
                      height: max(viewportHeight, 20.0)
                          .clamp(20.0, maxHeight).toDouble(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: vpColor.withValues(alpha: 0.08),
                          border: Border(
                            top: BorderSide(
                              color: vpColor.withValues(alpha: 0.2),
                              width: 1,
                            ),
                            bottom: BorderSide(
                              color: vpColor.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Determines a color for a line based on simple syntax heuristics.
Color _getLineColor(String line, SyntaxTheme? syntax, Color defaultColor) {
  if (syntax == null) return defaultColor;

  final trimmed = line.trimLeft();
  if (trimmed.isEmpty) return defaultColor;

  // Comments
  if (trimmed.startsWith('//') ||
      trimmed.startsWith('#') ||
      trimmed.startsWith('/*') ||
      trimmed.startsWith('*') ||
      trimmed.startsWith('///')) {
    return syntax.comment.withValues(alpha: 0.5);
  }

  // Strings (lines dominated by string content)
  if (trimmed.startsWith("'") ||
      trimmed.startsWith('"') ||
      trimmed.startsWith('`')) {
    return syntax.string.withValues(alpha: 0.5);
  }

  // Keywords
  final keywordPatterns = [
    'import ',
    'export ',
    'class ',
    'abstract ',
    'interface ',
    'enum ',
    'extends ',
    'implements ',
    'return ',
    'if ',
    'else ',
    'for ',
    'while ',
    'switch ',
    'case ',
    'break',
    'continue',
    'try ',
    'catch ',
    'finally ',
    'throw ',
    'async ',
    'await ',
    'const ',
    'final ',
    'var ',
    'let ',
    'def ',
    'fn ',
    'func ',
    'function ',
    'pub ',
    'static ',
    'void ',
    'int ',
    'double ',
    'bool ',
    'String ',
    '@override',
    '@required',
  ];
  for (final kw in keywordPatterns) {
    if (trimmed.startsWith(kw)) {
      return syntax.keyword.withValues(alpha: 0.5);
    }
  }

  // Function definitions (heuristic: contains parentheses)
  if (trimmed.contains('(') && trimmed.contains(')') && !trimmed.startsWith('//')) {
    return syntax.function.withValues(alpha: 0.4);
  }

  return defaultColor;
}

class _MinimapPainter extends CustomPainter {
  final String content;
  final int totalLines;
  final double lineHeight;
  final SyntaxTheme? syntaxTheme;
  final Color defaultColor;

  _MinimapPainter({
    required this.content,
    required this.totalLines,
    required this.lineHeight,
    this.syntaxTheme,
    required this.defaultColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lines = content.split('\n');
    final charWidth = size.width / 80;

    for (var i = 0; i < lines.length && i < totalLines; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;

      final y = i * lineHeight;
      if (y > size.height) break;

      // Find leading whitespace
      final stripped = line.trimLeft();
      final indent = line.length - stripped.length;

      // Get syntax-based color for this line
      final color = _getLineColor(line, syntaxTheme, defaultColor);
      final paint = Paint()..color = color;

      // Draw line as a thin rectangle
      final lineWidth =
          min(stripped.length.toDouble(), 80.0 - indent) * charWidth;
      if (lineWidth > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            indent * charWidth,
            y,
            lineWidth,
            max(lineHeight * 0.6, 1),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.content != content ||
        oldDelegate.totalLines != totalLines ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.syntaxTheme != syntaxTheme;
  }
}
