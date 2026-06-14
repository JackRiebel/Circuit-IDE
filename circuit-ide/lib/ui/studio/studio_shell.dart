import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/studio_shell.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import '../layout/ide_scaffold.dart';
import 'studio_home.dart';
import 'studio_left_rail.dart';
import 'studio_review_panel.dart';
import 'studio_chrome.dart';
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
      StudioMode.advancedEditor => const IDEScaffold(),
    };
  }
}

class _StudioTopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final studio = ref.watch(studioShellProvider);
    final workspace = ref.watch(agentWorkspaceProvider);
    final task = studio.selectedTaskId == null
        ? workspace.selectedTask
        : workspace.tasks
              .where((candidate) => candidate.id == studio.selectedTaskId)
              .firstOrNull;
    final title = switch (studio.mode) {
      StudioMode.home => '',
      StudioMode.project => '',
      StudioMode.task => task?.goal ?? 'Circuit task',
      StudioMode.review => 'Review changes',
      StudioMode.advancedEditor => 'Advanced Editor',
    };

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioTopBar,
        border: Border(
          bottom: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.78),
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
          Expanded(
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
          if (studio.mode == StudioMode.advancedEditor)
            TextButton.icon(
              onPressed: () =>
                  ref.read(studioShellProvider.notifier).openHome(),
              icon: const Icon(Icons.dashboard_customize_outlined, size: 15),
              label: const Text('Back to Studio'),
            )
          else
            StudioChromeIconButton(
              icon: Icons.terminal_outlined,
              tooltip: 'Open Advanced Editor',
              onTap: () =>
                  ref.read(studioShellProvider.notifier).openAdvancedEditor(),
            ),
        ],
      ),
    );
  }
}
