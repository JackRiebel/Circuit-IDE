import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/editor_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/icon_theme.dart';

class EditorTabBar extends ConsumerWidget {
  const EditorTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(editorProvider);
    final tokens = ref.watch(themeProvider);

    return Container(
      height: LayoutDimensions.tabBarHeight,
      decoration: BoxDecoration(
        color: tokens.bgLight,
        border: Border(
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: editorState.tabs.length,
              itemBuilder: (context, index) {
                final tab = editorState.tabs[index];
                final isActive = index == editorState.activeTabIndex;

                return _EditorTab(
                  fileName: tab.fileName,
                  filePath: tab.filePath,
                  isActive: isActive,
                  isModified: tab.isModified,
                  onTap: () => ref
                      .read(editorProvider.notifier)
                      .setActiveTab(index),
                  onClose: () => ref
                      .read(editorProvider.notifier)
                      .closeTab(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorTab extends ConsumerStatefulWidget {
  final String fileName;
  final String filePath;
  final bool isActive;
  final bool isModified;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _EditorTab({
    required this.fileName,
    required this.filePath,
    required this.isActive,
    required this.isModified,
    required this.onTap,
    required this.onClose,
  });

  @override
  ConsumerState<_EditorTab> createState() => _EditorTabState();
}

class _EditorTabState extends ConsumerState<_EditorTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: widget.filePath,
      waitDuration: const Duration(milliseconds: 500),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kMiddleMouseButton) {
            widget.onClose();
          }
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          decoration: BoxDecoration(
            color: widget.isActive
                ? tokens.tabActive
                : _isHovered
                    ? tokens.tabHover
                    : tokens.tabInactive,
            border: Border(
              top: BorderSide(
                color: widget.isActive
                    ? tokens.tabIndicator
                    : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(
                color: tokens.border.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.filePath == 'circuit://settings'
                    ? Icons.tune_outlined
                    : FileIconTheme.getIcon(widget.fileName),
                size: 14,
                color: widget.filePath == 'circuit://settings'
                    ? tokens.textSecondary
                    : FileIconTheme.getColor(widget.fileName),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.fileName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isActive
                        ? tokens.textPrimary
                        : tokens.textSecondary,
                    fontSize: FontSizes.sm,
                    fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.isModified) ...[
                const SizedBox(width: 4),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.accent,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: AnimatedOpacity(
                    duration: AnimationDurations.fast,
                    opacity: _isHovered || widget.isActive ? 0.7 : 0,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }
}
