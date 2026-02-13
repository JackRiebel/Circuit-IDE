import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/file_node.dart';
import '../../state/theme_provider.dart';
import '../../theme/icon_theme.dart';

class FileTreeItem extends ConsumerStatefulWidget {
  final FileNode node;
  final VoidCallback onTap;
  final void Function(Offset position)? onSecondaryTap;

  const FileTreeItem({
    super.key,
    required this.node,
    required this.onTap,
    this.onSecondaryTap,
  });

  @override
  ConsumerState<FileTreeItem> createState() => _FileTreeItemState();
}

class _FileTreeItemState extends ConsumerState<FileTreeItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final indent = widget.node.depth * 16.0 + 8.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTap != null
            ? (details) => widget.onSecondaryTap!(details.globalPosition)
            : null,
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          height: 24,
          color: _isHovering
              ? tokens.accent.withValues(alpha: 0.05)
              : Colors.transparent,
          padding: EdgeInsets.only(left: indent),
          child: Row(
            children: [
              if (widget.node.isDirectory) ...[
                AnimatedRotation(
                  turns: widget.node.isExpanded ? 0.25 : 0,
                  duration: AnimationDurations.fast,
                  child: Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: tokens.textMuted,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  widget.node.isExpanded
                      ? Icons.folder_open_outlined
                      : Icons.folder_outlined,
                  size: 15,
                  color: tokens.warning,
                ),
              ] else ...[
                const SizedBox(width: 16),
                Icon(
                  FileIconTheme.getIcon(widget.node.name),
                  size: 15,
                  color: FileIconTheme.getColor(widget.node.name),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: widget.node.name,
                  waitDuration: const Duration(milliseconds: 500),
                  child: Text(
                    widget.node.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _isHovering
                          ? tokens.textPrimary
                          : widget.node.isDirectory
                              ? tokens.textSecondary
                              : tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
