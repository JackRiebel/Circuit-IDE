import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_shell.dart';
import '../../state/command_palette_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';
import 'studio_focus_restoration.dart';

/// The persistent Studio top bar and its task/drawer navigation menus.
class StudioTopBar extends ConsumerWidget {
  const StudioTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final studio = ref.watch(
      studioShellProvider.select(
        (state) => (
          mode: state.mode,
          selectedTaskId: state.selectedTaskId,
          rightProgressPanelVisible: state.rightProgressPanelVisible,
        ),
      ),
    );
    final title = ref.watch(
      studioThreadProvider.select((threadState) {
        final thread = threadState.threadForTaskView(studio.selectedTaskId);
        return switch (studio.mode) {
          StudioMode.home => '',
          StudioMode.project => '',
          StudioMode.task => thread?.title ?? 'Circuit task',
          StudioMode.review => 'Review changes',
          StudioMode.settings => 'Settings',
        };
      }),
    );
    final showThreadMarker = studio.mode == StudioMode.task;

    return Container(
      height: StudioLayoutContract.topBarHeight,
      padding: const EdgeInsets.fromLTRB(14, 0, 7, 0),
      decoration: BoxDecoration(
        color: tokens.studioTopBar,
        border: Border(
          bottom: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.36),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TopBarTitleCluster(
              title: title,
              showThreadMarker: showThreadMarker,
            ),
          ),
          const SizedBox(width: 7),
          const _TopBarOpenInMenu(),
          const SizedBox(width: 3),
          StudioChromeIconButton(
            tooltip: 'Command palette (⌘K)',
            onTap: () => ref.read(commandPaletteProvider.notifier).open(),
            icon: StudioIcons.tuneOutlined,
            width: 25,
            height: 22,
            iconSize: 13,
          ),
          const SizedBox(width: 3),
          StudioChromeIconButton(
            tooltip: studio.rightProgressPanelVisible
                ? 'Hide Progress panel (⌥⌘→)'
                : 'Show Progress panel (⌥⌘→)',
            onTap: () => ref
                .read(studioShellProvider.notifier)
                .toggleRightProgressPanel(),
            icon: StudioIcons.viewSidebarOutlined,
            active: studio.rightProgressPanelVisible,
            focusNode: StudioFocusRestoration.maybeOf(
              context,
            )?.progressToggleFocusNode,
            width: 25,
            height: 22,
            iconSize: 13,
          ),
        ],
      ),
    );
  }
}

class _TopBarTitleCluster extends ConsumerWidget {
  final String title;
  final bool showThreadMarker;

  const _TopBarTitleCluster({
    required this.title,
    required this.showThreadMarker,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    if (title.trim().isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        if (showThreadMarker) ...[
          Tooltip(
            message: 'Current thread',
            child: Icon(StudioIcons.pushPin, color: tokens.textMuted, size: 12),
          ),
          const SizedBox(width: 7),
        ],
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.base,
              height: 1.12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 7),
        const _TopBarOverflowMenu(),
      ],
    );
  }
}

enum _TopBarOpenInAction { review, files, terminal, sideChat }

class _TopBarOpenInMenu extends ConsumerWidget {
  const _TopBarOpenInMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return PopupMenuButton<_TopBarOpenInAction>(
      tooltip: 'Open in',
      color: tokens.studioPanel,
      constraints: const BoxConstraints(minWidth: 232, maxWidth: 300),
      elevation: 4,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.42)),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 5),
      onSelected: (action) => _open(ref, action),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _TopBarOpenInAction.review,
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: _OpenInMenuRow(
            icon: StudioIcons.rateReviewOutlined,
            label: 'Review',
            shortcut: '^⇧G',
          ),
        ),
        PopupMenuItem(
          value: _TopBarOpenInAction.terminal,
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: _OpenInMenuRow(
            icon: StudioIcons.terminalOutlined,
            label: 'Terminal',
            shortcut: '⌘J',
          ),
        ),
        PopupMenuItem(
          value: _TopBarOpenInAction.files,
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: _OpenInMenuRow(
            icon: StudioIcons.folderOutlined,
            label: 'Files',
            shortcut: '⌘P',
          ),
        ),
        PopupMenuItem(
          value: _TopBarOpenInAction.sideChat,
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: _OpenInMenuRow(
            icon: StudioIcons.addCircleOutline,
            label: 'Side chat',
            shortcut: '⌥⌘S',
          ),
        ),
      ],
      child: Container(
        height: 26,
        padding: const EdgeInsets.only(left: 8, right: 6),
        decoration: BoxDecoration(
          color: tokens.studioControl.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.36),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              StudioIcons.folderSpecialOutlined,
              color: tokens.textSecondary,
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(
              'Open in',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            Icon(StudioIcons.expandMore, color: tokens.textMuted, size: 14),
          ],
        ),
      ),
    );
  }

  void _open(WidgetRef ref, _TopBarOpenInAction action) {
    final shell = ref.read(studioShellProvider.notifier);
    final drawer = ref.read(studioRightDrawerProvider.notifier);
    switch (action) {
      case _TopBarOpenInAction.review:
        shell.openReview();
      case _TopBarOpenInAction.files:
        shell.showRightProgressPanel();
        drawer.openMode(StudioDrawerMode.files);
      case _TopBarOpenInAction.terminal:
        shell.showRightProgressPanel();
        drawer.openMode(StudioDrawerMode.terminal);
      case _TopBarOpenInAction.sideChat:
        final threadId = ref.read(studioThreadProvider).selectedThreadId;
        if (threadId == null) {
          shell.openHome();
        } else {
          shell.openThread(threadId);
        }
    }
  }
}

class _OpenInMenuRow extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String? shortcut;

  const _OpenInMenuRow({
    required this.icon,
    required this.label,
    this.shortcut,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return SizedBox(
      width: 268,
      height: 28,
      child: Row(
        children: [
          Icon(icon, color: tokens.textMuted, size: 13),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (shortcut != null) ...[
            const SizedBox(width: Spacing.lg),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: tokens.studioControl.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                shortcut!,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _TopBarOverflowAction { settings, home, toggleEnvironment }

class _TopBarOverflowMenu extends ConsumerWidget {
  const _TopBarOverflowMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final rightProgressPanelVisible = ref.watch(
      studioShellProvider.select((state) => state.rightProgressPanelVisible),
    );
    return PopupMenuButton<_TopBarOverflowAction>(
      tooltip: 'Thread options',
      color: tokens.studioPanel,
      elevation: 6,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.56)),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      onSelected: (action) {
        final notifier = ref.read(studioShellProvider.notifier);
        switch (action) {
          case _TopBarOverflowAction.settings:
            notifier.openSettings();
          case _TopBarOverflowAction.home:
            notifier.openHome();
          case _TopBarOverflowAction.toggleEnvironment:
            notifier.toggleRightProgressPanel();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _TopBarOverflowAction.toggleEnvironment,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _OverflowMenuRow(
            icon: StudioIcons.viewSidebarOutlined,
            label: rightProgressPanelVisible
                ? 'Hide Progress panel'
                : 'Show Progress panel',
          ),
        ),
        const PopupMenuItem(
          value: _TopBarOverflowAction.settings,
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: _OverflowMenuRow(
            icon: StudioIcons.infoOutline,
            label: 'Settings',
          ),
        ),
        const PopupMenuItem(
          value: _TopBarOverflowAction.home,
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: _OverflowMenuRow(
            icon: StudioIcons.folderOutlined,
            label: 'Back to projects',
          ),
        ),
      ],
      child: Container(
        width: 26,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Icon(StudioIcons.moreHoriz, color: tokens.textMuted, size: 13),
      ),
    );
  }
}

class _OverflowMenuRow extends ConsumerWidget {
  final IconData icon;
  final String label;

  const _OverflowMenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return SizedBox(
      width: 190,
      height: 28,
      child: Row(
        children: [
          Icon(icon, color: tokens.textMuted, size: 13),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
