import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/notebook_provider.dart';
import '../../state/theme_provider.dart';
import 'notebook_cell.dart';
import 'notebook_toolbar.dart';

/// Main editor-area view for a notebook. Displays a toolbar at the top
/// and a reorderable list of cells below.
class NotebookEditor extends ConsumerWidget {
  final String notebookId;

  const NotebookEditor({super.key, required this.notebookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final nbState = ref.watch(notebookProvider);
    final notebook = nbState.notebooks
        .where((n) => n.id == notebookId)
        .firstOrNull;

    if (notebook == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: tokens.accent,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'Loading notebook...',
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
          ],
        ),
      );
    }

    return Container(
      color: tokens.editorBg,
      child: Column(
        children: [
          // Toolbar
          NotebookToolbar(notebookId: notebookId),

          // Cell list
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.xxl,
                vertical: Spacing.lg,
              ),
              buildDefaultDragHandles: false,
              itemCount: notebook.cells.length,
              onReorder: (oldIndex, newIndex) {
                ref
                    .read(notebookProvider.notifier)
                    .reorderCells(notebookId, oldIndex, newIndex);
              },
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: Colors.transparent,
                  elevation: 4,
                  shadowColor: Colors.black26,
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final cell = notebook.cells[index];
                return NotebookCellWidget(
                  key: ValueKey(cell.id),
                  notebookId: notebookId,
                  cell: cell,
                  cellIndex: index,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
