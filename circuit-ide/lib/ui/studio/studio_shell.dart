import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/studio_shell.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';
import 'studio_home.dart';
import 'studio_left_rail.dart';
import 'studio_review_panel.dart';
import 'studio_settings_view.dart';
import 'studio_task_view.dart';

class StudioShell extends ConsumerWidget {
  const StudioShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final studio = ref.watch(studioShellProvider);

    return Row(
      children: [
        const StudioLeftRail(),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: tokens.studioCanvas,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
              ),
              border: Border(
                left: BorderSide(
                  color: tokens.studioDivider.withValues(alpha: 0.72),
                ),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _StudioTopBar(),
                Expanded(child: _StudioBody(mode: studio.mode)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StudioBody extends StatelessWidget {
  final StudioMode mode;

  const _StudioBody({required this.mode});

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      StudioMode.home => const StudioHome(),
      StudioMode.project => const StudioHome(),
      StudioMode.task => const StudioTaskView(),
      StudioMode.review => const StudioReviewPanel(),
      StudioMode.settings => const StudioSettingsView(),
    };
  }
}

class _StudioTopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final studio = ref.watch(studioShellProvider);
    final threadState = ref.watch(studioThreadProvider);
    final thread =
        threadState.threadForTaskView(studio.selectedTaskId) ??
        threadState.selectedThread;
    final title = switch (studio.mode) {
      StudioMode.home => '',
      StudioMode.project => '',
      StudioMode.task => thread?.title ?? 'Circuit task',
      StudioMode.review => 'Review changes',
      StudioMode.settings => 'Settings',
    };

    return Container(
      height: 46,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      decoration: BoxDecoration(
        color: tokens.studioTopBar,
        border: Border(
          bottom: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.62),
          ),
        ),
      ),
      child: Row(
        children: [
          StudioChromeIconButton(
            tooltip: 'Back',
            onTap: () => ref.read(studioShellProvider.notifier).openHome(),
            icon: Icons.arrow_back,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(child: _TopBarTitle(title: title)),
          if (title.trim().isNotEmpty) ...[
            const SizedBox(width: Spacing.sm),
            const _TopBarOverflowMenu(),
          ],
          const SizedBox(width: Spacing.sm),
          StudioChromeIconButton(
            tooltip: 'Review changes',
            onTap: () => ref.read(studioShellProvider.notifier).openReview(),
            icon: Icons.rate_review_outlined,
            active: studio.mode == StudioMode.review,
          ),
          const SizedBox(width: Spacing.xs),
          StudioChromeIconButton(
            tooltip: studio.rightProgressPanelVisible
                ? 'Hide Environment panel'
                : 'Show Environment panel',
            onTap: () => ref
                .read(studioShellProvider.notifier)
                .toggleRightProgressPanel(),
            icon: Icons.view_sidebar_outlined,
            active: studio.rightProgressPanelVisible,
          ),
        ],
      ),
    );
  }
}

class _TopBarTitle extends ConsumerWidget {
  final String title;

  const _TopBarTitle({required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    if (title.trim().isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Tooltip(
          message: 'Current thread',
          child: Icon(Icons.push_pin, color: tokens.textMuted, size: 14),
        ),
        const SizedBox(width: Spacing.md),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.base,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

enum _TopBarOverflowAction { review, settings, home, toggleEnvironment }

class _TopBarOverflowMenu extends ConsumerWidget {
  const _TopBarOverflowMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final studio = ref.watch(studioShellProvider);
    return PopupMenuButton<_TopBarOverflowAction>(
      tooltip: 'Thread options',
      color: tokens.studioPanel,
      elevation: 10,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.7)),
      ),
      onSelected: (action) {
        final notifier = ref.read(studioShellProvider.notifier);
        switch (action) {
          case _TopBarOverflowAction.review:
            notifier.openReview();
          case _TopBarOverflowAction.settings:
            notifier.openSettings();
          case _TopBarOverflowAction.home:
            notifier.openHome();
          case _TopBarOverflowAction.toggleEnvironment:
            notifier.toggleRightProgressPanel();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _TopBarOverflowAction.review,
          child: Text('Review changes'),
        ),
        PopupMenuItem(
          value: _TopBarOverflowAction.toggleEnvironment,
          child: Text(
            studio.rightProgressPanelVisible
                ? 'Hide Progress panel'
                : 'Show Progress panel',
          ),
        ),
        const PopupMenuItem(
          value: _TopBarOverflowAction.settings,
          child: Text('Settings'),
        ),
        const PopupMenuItem(
          value: _TopBarOverflowAction.home,
          child: Text('Back to projects'),
        ),
      ],
      child: Container(
        width: 30,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Icon(Icons.more_horiz, color: tokens.textMuted, size: 15),
      ),
    );
  }
}
