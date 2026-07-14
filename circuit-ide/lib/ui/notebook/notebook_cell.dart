import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/notebook.dart';
import '../../state/notebook_provider.dart';
import '../../state/theme_provider.dart';
import 'cell_output_widget.dart';
import 'cell_toolbar.dart';

/// Language-to-accent color mapping for cell border indicators.
Color _languageColor(String language) {
  switch (language) {
    case 'python':
      return const Color(0xFF3572A5);
    case 'dart':
      return const Color(0xFF00B4AB);
    case 'javascript':
      return const Color(0xFFF7DF1E);
    case 'typescript':
      return const Color(0xFF3178C6);
    case 'bash':
    case 'shell':
      return const Color(0xFF89E051);
    case 'ruby':
      return const Color(0xFFCC342D);
    case 'go':
      return const Color(0xFF00ADD8);
    case 'rust':
      return const Color(0xFFDEA584);
    default:
      return const Color(0xFF808080);
  }
}

/// Widget representing a single notebook cell (code or markdown).
class NotebookCellWidget extends ConsumerStatefulWidget {
  final String notebookId;
  final NotebookCell cell;
  final int cellIndex;

  const NotebookCellWidget({
    super.key,
    required this.notebookId,
    required this.cell,
    required this.cellIndex,
  });

  @override
  ConsumerState<NotebookCellWidget> createState() => _NotebookCellWidgetState();
}

class _NotebookCellWidgetState extends ConsumerState<NotebookCellWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.cell.source);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(NotebookCellWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cell.source != widget.cell.source &&
        widget.cell.source != _controller.text) {
      _controller.text = widget.cell.source;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final cell = widget.cell;
    final isCode = cell.type == CellType.code;
    final langColor = _languageColor(cell.language);

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: ReorderableDragStartListener(
        index: widget.cellIndex,
        child: Container(
          decoration: BoxDecoration(
            color: tokens.bgLight,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: cell.status == CellStatus.running
                  ? tokens.accent.withValues(alpha: 0.5)
                  : cell.status == CellStatus.error
                  ? tokens.error.withValues(alpha: 0.3)
                  : tokens.border.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cell toolbar
              CellToolbar(notebookId: widget.notebookId, cell: cell),

              // Left language-color indicator + editor area
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: isCode ? langColor : tokens.info,
                      width: 3,
                    ),
                  ),
                ),
                child: isCode
                    ? _buildCodeEditor(tokens)
                    : _buildMarkdownEditor(tokens),
              ),

              // Output area
              if (cell.output != null || cell.status == CellStatus.running)
                CellOutputWidget(cell: cell),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeEditor(dynamic tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: null,
        style: TextStyle(
          fontFamily: EditorDefaults.fontFamily,
          fontSize: FontSizes.sm,
          color: tokens.textPrimary,
          height: 1.6,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.all(Spacing.md),
          filled: true,
          fillColor: tokens.editorBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.xs),
            borderSide: BorderSide.none,
          ),
          hintText: 'Enter code...',
          hintStyle: TextStyle(
            color: tokens.textDisabled,
            fontFamily: EditorDefaults.fontFamily,
            fontSize: FontSizes.sm,
          ),
        ),
        onChanged: (value) {
          ref
              .read(notebookProvider.notifier)
              .updateCellSource(widget.notebookId, widget.cell.id, value);
        },
      ),
    );
  }

  Widget _buildMarkdownEditor(dynamic tokens) {
    final cell = widget.cell;

    if (!cell.isEditing) {
      // Rendered markdown view (double-click to edit)
      return GestureDetector(
        onDoubleTap: () {
          ref
              .read(notebookProvider.notifier)
              .toggleCellEditing(widget.notebookId, cell.id);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.lg,
          ),
          child: cell.source.isEmpty
              ? Text(
                  'Double-click to edit markdown...',
                  style: TextStyle(
                    color: tokens.textDisabled,
                    fontSize: FontSizes.sm,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : SelectableText(
                  cell.source,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    height: 1.6,
                  ),
                ),
        ),
      );
    }

    // Editing mode
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: null,
        autofocus: true,
        style: TextStyle(
          fontSize: FontSizes.sm,
          color: tokens.textPrimary,
          height: 1.6,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.all(Spacing.md),
          filled: true,
          fillColor: tokens.editorBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.xs),
            borderSide: BorderSide.none,
          ),
          hintText: 'Enter markdown...',
          hintStyle: TextStyle(
            color: tokens.textDisabled,
            fontSize: FontSizes.sm,
          ),
        ),
        onChanged: (value) {
          ref
              .read(notebookProvider.notifier)
              .updateCellSource(widget.notebookId, widget.cell.id, value);
        },
        onEditingComplete: () {
          ref
              .read(notebookProvider.notifier)
              .toggleCellEditing(widget.notebookId, cell.id);
        },
      ),
    );
  }
}
