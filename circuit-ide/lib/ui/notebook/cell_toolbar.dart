import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/notebook.dart';
import '../../state/notebook_provider.dart';
import '../../state/theme_provider.dart';

/// Supported languages for the language picker dropdown.
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

/// Per-cell toolbar with run, type toggle, language picker, and delete buttons.
class CellToolbar extends ConsumerWidget {
  final String notebookId;
  final NotebookCell cell;

  const CellToolbar({super.key, required this.notebookId, required this.cell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final isCode = cell.type == CellType.code;
    final isRunning = cell.status == CellStatus.running;

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      decoration: BoxDecoration(
        color: tokens.bgLighter.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(Radii.md),
          topRight: Radius.circular(Radii.md),
        ),
      ),
      child: Row(
        children: [
          // Execution order badge
          if (cell.executionOrder != null)
            Container(
              margin: const EdgeInsets.only(right: Spacing.md),
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm + 2,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Text(
                '[${cell.executionOrder}]',
                style: TextStyle(
                  fontSize: FontSizes.xxs,
                  color: tokens.accent,
                  fontFamily: EditorDefaults.fontFamily,
                ),
              ),
            ),

          // Cell type indicator
          Text(
            isCode ? 'Code' : 'Markdown',
            style: TextStyle(
              fontSize: FontSizes.xxs,
              color: tokens.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),

          const Spacer(),

          // Run button (code cells only)
          if (isCode)
            _ToolbarIconButton(
              icon: isRunning ? Icons.stop : Icons.play_arrow,
              tooltip: isRunning ? 'Stop' : 'Run Cell',
              color: isRunning ? tokens.warning : tokens.success,
              onTap: () {
                ref
                    .read(notebookProvider.notifier)
                    .executeCell(notebookId, cell.id);
              },
            ),

          // Type toggle
          _ToolbarIconButton(
            icon: isCode ? Icons.text_snippet_outlined : Icons.code,
            tooltip: isCode ? 'Switch to Markdown' : 'Switch to Code',
            onTap: () {
              ref
                  .read(notebookProvider.notifier)
                  .toggleCellType(notebookId, cell.id);
            },
          ),

          // Language picker (code cells only)
          if (isCode)
            _LanguagePicker(
              notebookId: notebookId,
              cellId: cell.id,
              currentLanguage: cell.language,
            ),

          // Delete
          _ToolbarIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete Cell',
            onTap: () {
              ref
                  .read(notebookProvider.notifier)
                  .deleteCell(notebookId, cell.id);
            },
          ),
        ],
      ),
    );
  }
}

class _ToolbarIconButton extends ConsumerStatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  ConsumerState<_ToolbarIconButton> createState() => _ToolbarIconButtonState();
}

class _ToolbarIconButtonState extends ConsumerState<_ToolbarIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final iconColor = widget.color ?? tokens.textMuted;

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
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(left: Spacing.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.xs),
              color: _isHovered
                  ? tokens.textMuted.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              size: 13,
              color: _isHovered ? iconColor : iconColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguagePicker extends ConsumerWidget {
  final String notebookId;
  final String cellId;
  final String currentLanguage;

  const _LanguagePicker({
    required this.notebookId,
    required this.cellId,
    required this.currentLanguage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Padding(
      padding: const EdgeInsets.only(left: Spacing.sm),
      child: PopupMenuButton<String>(
        tooltip: 'Change language',
        onSelected: (language) {
          ref
              .read(notebookProvider.notifier)
              .setCellLanguage(notebookId, cellId, language);
        },
        color: tokens.bgLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
        ),
        offset: const Offset(0, 24),
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
            horizontal: Spacing.sm + 1,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.xs),
            color: tokens.bgLighter.withValues(alpha: 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentLanguage,
                style: TextStyle(
                  fontSize: FontSizes.xxs,
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 12, color: tokens.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
