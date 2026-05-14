import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../enums/connection_status.dart';
import '../../state/connection_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/layout_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/terminal_provider.dart';
import 'activity_bar.dart';
import 'side_panel.dart';
import 'status_bar.dart';
import 'resizable_split.dart';
import '../editor/editor_area.dart';
import '../terminal/terminal_panel.dart';
import '../chat/chat_panel.dart';

class IDEScaffold extends ConsumerStatefulWidget {
  const IDEScaffold({super.key});

  @override
  ConsumerState<IDEScaffold> createState() => _IDEScaffoldState();
}

class _IDEScaffoldState extends ConsumerState<IDEScaffold> {
  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final showSidePanel = ref.watch(sidePanelVisibleProvider);
    final showChatPanel = ref.watch(chatPanelVisibleProvider);
    final layoutSizes = ref.watch(ideLayoutSizesProvider);
    final terminalState = ref.watch(terminalProvider);

    return Column(
      children: [
        const _TitleBar(),

        // Main content
        Expanded(
          child: Row(
            children: [
              const ActivityBar(),

              if (showSidePanel) ...[
                SizedBox(
                  width: layoutSizes.sidePanelWidth,
                  child: const SidePanel(),
                ),
                ResizableHandle(
                  direction: Axis.horizontal,
                  onDrag: (delta) {
                    ref
                        .read(ideLayoutSizesProvider.notifier)
                        .setSidePanelWidth(layoutSizes.sidePanelWidth + delta);
                  },
                  color: tokens.border,
                ),
              ],

              Expanded(
                child: Column(
                  children: [
                    const Expanded(child: EditorArea()),
                    if (terminalState.isVisible) ...[
                      ResizableHandle(
                        direction: Axis.vertical,
                        onDrag: (delta) {
                          ref
                              .read(terminalProvider.notifier)
                              .setHeight(terminalState.height - delta);
                        },
                        color: tokens.border,
                      ),
                      SizedBox(
                        height: terminalState.height,
                        child: const TerminalPanel(),
                      ),
                    ],
                  ],
                ),
              ),

              if (showChatPanel) ...[
                ResizableHandle(
                  direction: Axis.horizontal,
                  onDrag: (delta) {
                    ref
                        .read(ideLayoutSizesProvider.notifier)
                        .setChatPanelWidth(layoutSizes.chatPanelWidth - delta);
                  },
                  color: tokens.border,
                ),
                SizedBox(
                  width: layoutSizes.chatPanelWidth,
                  child: const ChatPanel(),
                ),
              ],
            ],
          ),
        ),

        const StatusBar(),
      ],
    );
  }
}

class _TitleBar extends ConsumerWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final activeTab = ref.watch(editorProvider).activeTab;
    final connectionStatus = ref.watch(connectionStatusProvider);
    final settings = ref.watch(settingsProvider);
    final terminalVisible = ref.watch(terminalProvider).isVisible;
    final chatVisible = ref.watch(chatPanelVisibleProvider);

    final workspaceName = rootPath == null
        ? 'No workspace'
        : p.basename(rootPath);
    final activeFile = activeTab?.filePath.startsWith('circuit://') ?? true
        ? null
        : activeTab?.fileName;

    return Container(
      height: LayoutDimensions.titleBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      decoration: BoxDecoration(
        color: tokens.bgDark,
        border: Border(
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.45)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 70),
          _TitlePill(
            icon: Icons.folder_open_outlined,
            label: workspaceName,
            muted: rootPath == null,
          ),
          const SizedBox(width: Spacing.md),
          if (activeFile != null)
            Expanded(
              child: _TitlePill(
                icon: activeTab!.isModified
                    ? Icons.circle
                    : Icons.description_outlined,
                label: activeFile,
                tooltip: activeTab.filePath,
                accent: activeTab.isModified ? tokens.warning : null,
              ),
            )
          else
            const Spacer(),
          Text(
            'CircuitCode',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.md,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          _ConnectionPill(
            status: connectionStatus,
            label: settings.activeProvider.shortName,
          ),
          const SizedBox(width: Spacing.md),
          _TitleIconButton(
            icon: Icons.terminal,
            tooltip: terminalVisible ? 'Hide terminal' : 'Show terminal',
            selected: terminalVisible,
            onTap: () => ref.read(terminalProvider.notifier).toggle(),
          ),
          const SizedBox(width: Spacing.sm),
          _TitleIconButton(
            icon: Icons.auto_awesome,
            tooltip: chatVisible ? 'Hide AI assistant' : 'Show AI assistant',
            selected: chatVisible,
            onTap: () => ref.read(chatPanelVisibleProvider.notifier).toggle(),
          ),
          const SizedBox(width: Spacing.md),
        ],
      ),
    );
  }
}

class _TitlePill extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final bool muted;
  final Color? accent;

  const _TitlePill({
    required this.icon,
    required this.label,
    this.tooltip,
    this.muted = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = accent ?? (muted ? tokens.textMuted : tokens.textSecondary);

    return Tooltip(
      message: tooltip ?? label,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: tokens.bgLight.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: tokens.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionPill extends ConsumerWidget {
  final ConnectionStatus status;
  final String label;

  const _ConnectionPill({required this.status, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = switch (status) {
      ConnectionStatus.connected => tokens.success,
      ConnectionStatus.connecting => tokens.warning,
      ConnectionStatus.error => tokens.error,
      ConnectionStatus.disconnected => tokens.textMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleIconButton extends ConsumerWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _TitleIconButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          width: 28,
          height: 24,
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected
                  ? tokens.accent.withValues(alpha: 0.24)
                  : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            size: 15,
            color: selected ? tokens.accent : tokens.textMuted,
          ),
        ),
      ),
    );
  }
}
