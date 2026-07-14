import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/config/studio_feature_flags.dart';
import '../../models/agent_workspace.dart';
import '../../models/studio_right_drawer.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_browser_drawer.dart';
import 'studio_artifacts_drawer.dart';
import 'studio_chrome.dart';
import 'studio_focus_restoration.dart';
import 'studio_context_drawer.dart';
import 'studio_code_drawer.dart';
import 'studio_file_sources_drawer.dart';
import 'studio_motion.dart';
import 'studio_patch_review_drawer.dart';
import 'studio_progress_drawer.dart';
import 'studio_terminal_drawer.dart';

class StudioRightDrawer extends ConsumerWidget {
  final AgentTask? task;

  const StudioRightDrawer({super.key, this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    final width = drawer.width;

    return Semantics(
      container: true,
      label: drawer.collapsed
          ? 'Studio work panel, collapsed'
          : 'Studio work panel, ${_drawerModeLabel(drawer.mode)} view',
      child: AnimatedContainer(
        duration: studioMotionDuration(context, AnimationDurations.panel),
        curve: AnimationCurves.smooth,
        width: width,
        margin: const EdgeInsets.only(top: 48),
        decoration: BoxDecoration(
          color: tokens.studioDrawer.withValues(alpha: 0.94),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomLeft: Radius.circular(12),
          ),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: drawer.collapsed
            ? const _CollapsedDrawer()
            : Column(
                children: [
                  _DrawerHeader(task: task),
                  Expanded(child: _DrawerBody(task: task)),
                ],
              ),
      ),
    );
  }
}

const _visibleDrawerModes = <StudioDrawerMode>[
  StudioDrawerMode.progress,
  if (StudioFeatureFlags.browserPreview) StudioDrawerMode.browser,
  StudioDrawerMode.artifacts,
  StudioDrawerMode.code,
  StudioDrawerMode.diff,
  StudioDrawerMode.files,
  StudioDrawerMode.terminal,
  StudioDrawerMode.context,
];

class _CollapsedDrawer extends ConsumerWidget {
  const _CollapsedDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const SizedBox(height: 5),
        StudioChromeIconButton(
          tooltip: 'Expand right panel',
          onTap: () => _toggleCollapsedAndRestoreFocus(context, ref),
          icon: StudioIcons.chevronLeft,
          width: 30,
          height: 24,
          iconSize: 14,
        ),
      ],
    );
  }
}

class _DrawerHeader extends ConsumerWidget {
  final AgentTask? task;

  const _DrawerHeader({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 7, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              _titleFor(drawer.mode),
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.sm,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _DrawerModeMenu(active: drawer.mode),
          StudioChromeIconButton(
            tooltip: drawer.expanded ? 'Shrink panel' : 'Expand panel',
            onTap: () =>
                ref.read(studioRightDrawerProvider.notifier).toggleExpanded(),
            icon: drawer.expanded
                ? StudioIcons.closeFullscreen
                : StudioIcons.openInFullOutlined,
          ),
          StudioChromeIconButton(
            tooltip: 'Collapse panel',
            onTap: () => _toggleCollapsedAndRestoreFocus(context, ref),
            icon: StudioIcons.chevronRight,
          ),
        ],
      ),
    );
  }

  String _titleFor(StudioDrawerMode mode) {
    return switch (mode) {
      StudioDrawerMode.progress => 'Progress',
      StudioDrawerMode.browser => 'Preview',
      StudioDrawerMode.code => 'Code',
      StudioDrawerMode.diff => 'Diff',
      StudioDrawerMode.files => 'Files',
      StudioDrawerMode.artifacts => 'Artifacts',
      StudioDrawerMode.terminal => 'Terminal',
      StudioDrawerMode.sources => 'Sources',
      StudioDrawerMode.context => 'Context',
    };
  }
}

void _toggleCollapsedAndRestoreFocus(BuildContext context, WidgetRef ref) {
  ref.read(studioRightDrawerProvider.notifier).toggleCollapsed();
  StudioFocusRestoration.maybeOf(context)?.restoreToProgressToggle();
}

class _DrawerModeMenu extends ConsumerWidget {
  final StudioDrawerMode active;

  const _DrawerModeMenu({required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return PopupMenuButton<StudioDrawerMode>(
      tooltip: 'Open drawer view',
      color: tokens.studioPanel,
      elevation: 10,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.7)),
      ),
      onSelected: (mode) =>
          ref.read(studioRightDrawerProvider.notifier).openMode(mode),
      itemBuilder: (context) => [
        for (final mode in _visibleDrawerModes)
          PopupMenuItem<StudioDrawerMode>(
            height: 34,
            value: mode,
            child: Row(
              children: [
                Icon(
                  _drawerModeIcon(mode),
                  color: mode == active
                      ? tokens.textSecondary
                      : tokens.textMuted,
                  size: 13,
                ),
                const SizedBox(width: Spacing.md),
                Text(
                  _drawerModeLabel(mode),
                  style: TextStyle(
                    color: mode == active
                        ? tokens.textSecondary
                        : tokens.textMuted,
                    fontSize: FontSizes.xs,
                    fontWeight: mode == active
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: SizedBox(
        width: 26,
        height: 22,
        child: Icon(
          StudioIcons.tuneOutlined,
          color: tokens.textMuted,
          size: 13,
        ),
      ),
    );
  }
}

IconData _drawerModeIcon(StudioDrawerMode mode) {
  return switch (mode) {
    StudioDrawerMode.progress => StudioIcons.radioButtonChecked,
    StudioDrawerMode.browser => StudioIcons.language,
    StudioDrawerMode.code => StudioIcons.code,
    StudioDrawerMode.diff => StudioIcons.differenceOutlined,
    StudioDrawerMode.files => StudioIcons.folderOutlined,
    StudioDrawerMode.artifacts => StudioIcons.filePresentOutlined,
    StudioDrawerMode.terminal => StudioIcons.terminalOutlined,
    StudioDrawerMode.sources => StudioIcons.travelExplore,
    StudioDrawerMode.context => StudioIcons.inventory2Outlined,
  };
}

String _drawerModeLabel(StudioDrawerMode mode) {
  return switch (mode) {
    StudioDrawerMode.progress => 'Progress',
    StudioDrawerMode.browser => 'Browser preview',
    StudioDrawerMode.code => 'Code',
    StudioDrawerMode.diff => 'Diff',
    StudioDrawerMode.files => 'Files',
    StudioDrawerMode.artifacts => 'Artifacts',
    StudioDrawerMode.terminal => 'Terminal output',
    StudioDrawerMode.sources => 'Sources',
    StudioDrawerMode.context => 'Context details',
  };
}

class _DrawerBody extends ConsumerWidget {
  final AgentTask? task;

  const _DrawerBody({this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(studioRightDrawerProvider).mode;
    final safeMode =
        mode == StudioDrawerMode.browser && !StudioFeatureFlags.browserPreview
        ? StudioDrawerMode.sources
        : mode;
    return switch (safeMode) {
      StudioDrawerMode.progress => StudioProgressDrawer(task: task),
      StudioDrawerMode.browser => const StudioBrowserDrawer(),
      StudioDrawerMode.code => const StudioCodeDrawer(),
      StudioDrawerMode.diff => StudioPatchReviewDrawer(task: task),
      StudioDrawerMode.files => const StudioFilesDrawer(),
      StudioDrawerMode.artifacts => StudioArtifactsDrawer(task: task),
      StudioDrawerMode.terminal => StudioTerminalDrawer(task: task),
      StudioDrawerMode.sources => StudioSourcesDrawer(task: task),
      StudioDrawerMode.context => StudioContextDrawer(task: task),
    };
  }
}
