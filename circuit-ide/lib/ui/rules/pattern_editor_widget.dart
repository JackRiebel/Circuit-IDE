import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

class PatternEditorWidget extends ConsumerStatefulWidget {
  final List<String> patterns;
  final ValueChanged<List<String>> onChanged;

  const PatternEditorWidget({
    super.key,
    required this.patterns,
    required this.onChanged,
  });

  @override
  ConsumerState<PatternEditorWidget> createState() =>
      _PatternEditorWidgetState();
}

class _PatternEditorWidgetState extends ConsumerState<PatternEditorWidget> {
  final _controller = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addPattern() {
    final pattern = _controller.text.trim();
    if (pattern.isEmpty) return;
    if (widget.patterns.contains(pattern)) return;

    widget.onChanged([...widget.patterns, pattern]);
    _controller.clear();
    setState(() => _isAdding = false);
  }

  void _removePattern(int index) {
    final newPatterns = List<String>.from(widget.patterns)..removeAt(index);
    widget.onChanged(newPatterns);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'File Patterns',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Tooltip(
              message:
                  'Glob patterns that activate this rule.\n'
                  'Examples: lib/ui/**/*.dart, *_test.dart\n'
                  'Leave empty to always activate.',
              child: Icon(
                Icons.info_outline,
                size: 13,
                color: tokens.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),

        // Pattern chips
        if (widget.patterns.isNotEmpty)
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (var i = 0; i < widget.patterns.length; i++)
                _PatternChip(
                  pattern: widget.patterns[i],
                  onDelete: () => _removePattern(i),
                  tokens: tokens,
                ),
            ],
          ),

        const SizedBox(height: Spacing.md),

        // Add pattern
        if (_isAdding)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.xs,
                      fontFamily: 'JetBrains Mono',
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: tokens.bgDark,
                      hintText: 'e.g., lib/ui/**/*.dart',
                      hintStyle: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xs,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.sm,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        borderSide: BorderSide(color: tokens.accent),
                      ),
                    ),
                    onSubmitted: (_) => _addPattern(),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              GestureDetector(
                onTap: _addPattern,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.check, size: 16, color: tokens.success),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              GestureDetector(
                onTap: () => setState(() => _isAdding = false),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.close, size: 16, color: tokens.textMuted),
                ),
              ),
            ],
          )
        else
          GestureDetector(
            onTap: () => setState(() => _isAdding = true),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: tokens.accent),
                  const SizedBox(width: 4),
                  Text(
                    'Add Pattern',
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PatternChip extends StatelessWidget {
  final String pattern;
  final VoidCallback onDelete;
  final dynamic tokens;

  const _PatternChip({
    required this.pattern,
    required this.onDelete,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        color: tokens.accent.withValues(alpha: 0.1),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pattern,
            style: TextStyle(
              color: tokens.accent,
              fontSize: FontSizes.xxs,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDelete,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(Icons.close, size: 12, color: tokens.accent),
            ),
          ),
        ],
      ),
    );
  }
}
