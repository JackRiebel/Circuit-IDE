import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/notebook_provider.dart';
import '../../state/theme_provider.dart';

/// Supported languages for the default language picker.
const _supportedLanguages = [
  'python',
  'dart',
  'javascript',
  'typescript',
  'bash',
  'ruby',
  'go',
  'rust',
];

/// Top toolbar for the notebook editor: editable name, Run All, Clear Outputs,
/// Add Cell, and default language picker.
class NotebookToolbar extends ConsumerStatefulWidget {
  final String notebookId;

  const NotebookToolbar({super.key, required this.notebookId});

  @override
  ConsumerState<NotebookToolbar> createState() => _NotebookToolbarState();
}

class _NotebookToolbarState extends ConsumerState<NotebookToolbar> {
  bool _isEditingName = false;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final nbState = ref.watch(notebookProvider);
    final notebook =
        nbState.notebooks.where((n) => n.id == widget.notebookId).firstOrNull;

    if (notebook == null) return const SizedBox.shrink();

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.bgLight,
        border: Border(
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          // Notebook name (editable)
          if (_isEditingName)
            SizedBox(
              width: 200,
              child: TextField(
                controller: _nameController,
                autofocus: true,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    borderSide: BorderSide(color: tokens.accent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    borderSide: BorderSide(color: tokens.accent),
                  ),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    ref
                        .read(notebookProvider.notifier)
                        .renameNotebook(widget.notebookId, value);
                  }
                  setState(() => _isEditingName = false);
                },
                onEditingComplete: () {
                  setState(() => _isEditingName = false);
                },
              ),
            )
          else
            GestureDetector(
              onDoubleTap: () {
                _nameController.text = notebook.name;
                setState(() => _isEditingName = true);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.book_outlined,
                    size: 14,
                    color: tokens.accent.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: Spacing.md),
                  Text(
                    notebook.name,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Icon(
                    Icons.edit_outlined,
                    size: 11,
                    color: tokens.textDisabled,
                  ),
                ],
              ),
            ),

          const Spacer(),

          // Default language picker
          _DefaultLanguagePicker(
            notebookId: widget.notebookId,
            currentLanguage: notebook.defaultLanguage,
          ),

          const SizedBox(width: Spacing.lg),

          // Run All button
          _ToolbarAction(
            icon: Icons.play_arrow,
            label: 'Run All',
            color: tokens.success,
            onTap: () {
              ref.read(notebookProvider.notifier).runAll(widget.notebookId);
            },
          ),

          const SizedBox(width: Spacing.md),

          // Clear Outputs button
          _ToolbarAction(
            icon: Icons.clear_all,
            label: 'Clear',
            onTap: () {
              ref
                  .read(notebookProvider.notifier)
                  .clearOutputs(widget.notebookId);
            },
          ),

          const SizedBox(width: Spacing.md),

          // Add Cell button
          _ToolbarAction(
            icon: Icons.add,
            label: 'Cell',
            onTap: () {
              ref
                  .read(notebookProvider.notifier)
                  .addCell(widget.notebookId);
            },
          ),

          const SizedBox(width: Spacing.md),

          // AI Generate button
          _ToolbarAction(
            icon: Icons.auto_awesome,
            label: 'AI',
            color: tokens.accent,
            onTap: () => _showGenerateDialog(context, tokens),
          ),
        ],
      ),
    );
  }

  void _showGenerateDialog(BuildContext context, dynamic tokens) {
    final promptController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.bgMain,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: tokens.border),
        ),
        title: Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: tokens.accent),
            const SizedBox(width: Spacing.md),
            Text(
              'Generate Code with AI',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.lg,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: promptController,
            autofocus: true,
            maxLines: 3,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.sm,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: tokens.bgDark,
              hintText: 'Describe the code you want to generate...',
              hintStyle: TextStyle(color: tokens.textDisabled),
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
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                ref
                    .read(notebookProvider.notifier)
                    .generateCell(widget.notebookId, value);
                Navigator.of(ctx).pop();
              }
            },
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
              final value = promptController.text;
              if (value.isNotEmpty) {
                ref
                    .read(notebookProvider.notifier)
                    .generateCell(widget.notebookId, value);
                Navigator.of(ctx).pop();
              }
            },
            child: Text(
              'Generate',
              style: TextStyle(color: tokens.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarAction extends ConsumerStatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  ConsumerState<_ToolbarAction> createState() => _ToolbarActionState();
}

class _ToolbarActionState extends ConsumerState<_ToolbarAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final color = widget.color ?? tokens.textSecondary;

    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AnimationDurations.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              color: _isHovered
                  ? color.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 13,
                  color: _isHovered
                      ? color
                      : color.withValues(alpha: 0.7),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: FontSizes.xs,
                    color: _isHovered
                        ? color
                        : color.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DefaultLanguagePicker extends ConsumerWidget {
  final String notebookId;
  final String currentLanguage;

  const _DefaultLanguagePicker({
    required this.notebookId,
    required this.currentLanguage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return PopupMenuButton<String>(
      tooltip: 'Default language',
      onSelected: (language) {
        ref
            .read(notebookProvider.notifier)
            .setDefaultLanguage(notebookId, language);
      },
      color: tokens.bgLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
      ),
      offset: const Offset(0, 32),
      itemBuilder: (context) => _supportedLanguages.map((lang) {
        return PopupMenuItem<String>(
          value: lang,
          height: 28,
          child: Text(
            lang,
            style: TextStyle(
              fontSize: FontSizes.xs,
              color: lang == currentLanguage
                  ? tokens.accent
                  : tokens.textPrimary,
              fontWeight: lang == currentLanguage
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.sm),
          color: tokens.bgLighter.withValues(alpha: 0.5),
          border: Border.all(color: tokens.border.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Default: $currentLanguage',
              style: TextStyle(
                fontSize: FontSizes.xs,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
