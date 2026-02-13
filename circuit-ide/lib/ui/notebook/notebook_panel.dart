import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/editor_provider.dart';
import '../../state/notebook_provider.dart';
import '../../state/theme_provider.dart';

/// Side panel showing a list of notebooks with create/delete actions.
class NotebookPanel extends ConsumerWidget {
  const NotebookPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final nbState = ref.watch(notebookProvider);

    return Column(
      children: [
        // Header + New Notebook button
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'NOTEBOOKS',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              _ToolbarButton(
                icon: Icons.add,
                tooltip: 'New Notebook',
                onTap: () async {
                  final notebook = await ref
                      .read(notebookProvider.notifier)
                      .createNotebook();
                  ref
                      .read(editorProvider.notifier)
                      .openNotebookTab(notebook.id, notebook.name);
                },
              ),
              _ToolbarButton(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onTap: () =>
                    ref.read(notebookProvider.notifier).loadNotebooks(),
              ),
            ],
          ),
        ),

        // Loading state
        if (nbState.isLoading)
          Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: tokens.accent,
                ),
              ),
            ),
          ),

        // Notebook list
        if (!nbState.isLoading)
          Expanded(
            child: nbState.notebooks.isEmpty
                ? _EmptyState(tokens: tokens)
                : ListView.builder(
                    itemCount: nbState.notebooks.length,
                    itemBuilder: (context, index) {
                      final notebook = nbState.notebooks[index];
                      final isActive =
                          notebook.id == nbState.activeNotebookId;

                      return _NotebookItem(
                        notebook: notebook,
                        isActive: isActive,
                        onTap: () {
                          ref
                              .read(notebookProvider.notifier)
                              .setActiveNotebook(notebook.id);
                          ref
                              .read(editorProvider.notifier)
                              .openNotebookTab(notebook.id, notebook.name);
                        },
                        onDelete: () => _confirmDelete(
                          context,
                          ref,
                          tokens,
                          notebook.id,
                          notebook.name,
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    dynamic tokens,
    String id,
    String name,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.bgMain,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: tokens.border),
        ),
        title: Text(
          'Delete Notebook',
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.lg,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "$name"? This cannot be undone.',
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: FontSizes.sm,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              ref.read(notebookProvider.notifier).deleteNotebook(id);
              Navigator.of(ctx).pop();
            },
            child: Text(
              'Delete',
              style: TextStyle(color: tokens.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotebookItem extends ConsumerStatefulWidget {
  final dynamic notebook;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotebookItem({
    required this.notebook,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  ConsumerState<_NotebookItem> createState() => _NotebookItemState();
}

class _NotebookItemState extends ConsumerState<_NotebookItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final notebook = widget.notebook;
    final dateStr = _formatDate(notebook.modifiedAt);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.md,
          ),
          decoration: BoxDecoration(
            color: widget.isActive
                ? tokens.accent.withValues(alpha: 0.08)
                : _isHovered
                    ? tokens.textMuted.withValues(alpha: 0.06)
                    : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: widget.isActive
                    ? tokens.accent
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.book_outlined,
                size: 14,
                color: widget.isActive
                    ? tokens.accent
                    : tokens.textMuted,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notebook.name,
                      style: TextStyle(
                        color: widget.isActive
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                        fontSize: FontSizes.sm,
                        fontWeight: widget.isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${notebook.cells.length} cells  ·  $dateStr',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xxs,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isHovered)
                GestureDetector(
                  onTap: widget.onDelete,
                  child: Padding(
                    padding: const EdgeInsets.only(left: Spacing.sm),
                    child: Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(date);
  }
}

class _EmptyState extends StatelessWidget {
  final dynamic tokens;
  const _EmptyState({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.xl),
                color: tokens.textMuted.withValues(alpha: 0.06),
              ),
              child: Icon(
                Icons.book_outlined,
                size: 20,
                color: tokens.textMuted,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'No notebooks yet',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.sm,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Create a notebook to start\nwriting and running code.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends ConsumerStatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  ConsumerState<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends ConsumerState<_ToolbarButton> {
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
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              color: _isHovered
                  ? tokens.textMuted.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: _isHovered ? tokens.textPrimary : tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
