import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/workspace_open_result.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';

class StudioLeftRail extends ConsumerWidget {
  const StudioLeftRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final tasks = ref.watch(agentWorkspaceProvider).tasks;
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: tokens.studioRail,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.studioRail.withValues(alpha: 0.96),
            tokens.bgMain.withValues(alpha: 0.92),
          ],
        ),
        border: Border(right: BorderSide(color: tokens.studioDivider)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: Spacing.sm),
            _RailTopBar(),
            const SizedBox(height: Spacing.md),
            _RailAction(
              icon: Icons.edit_square,
              label: 'New task',
              onTap: () => ref.read(studioShellProvider.notifier).openHome(),
            ),
            _RailAction(icon: Icons.search, label: 'Search', onTap: () {}),
            _RailAction(
              icon: Icons.hub_outlined,
              label: 'Plugins',
              onTap: () {},
            ),
            _RailAction(
              icon: Icons.schedule_outlined,
              label: 'Automations',
              onTap: () {},
            ),
            _RailAction(
              icon: Icons.phone_iphone_outlined,
              label: 'Circuit mobile',
              onTap: () {},
            ),
            const SizedBox(height: Spacing.xl),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const _RailSectionLabel('Projects'),
                  for (final path in settings.recentProjects.take(8))
                    _RecentProjectGroup(
                      path: path,
                      taskCount: tasks.where((task) => true).length,
                    ),
                  if (settings.recentProjects.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg,
                        vertical: Spacing.sm,
                      ),
                      child: Text(
                        'No recent projects',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.sm,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _RailAction(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () {
                ref.read(studioShellProvider.notifier).openAdvancedEditor();
                ref.read(editorProvider.notifier).openSettingsTab();
              },
            ),
            const SizedBox(height: Spacing.md),
          ],
        ),
      ),
    );
  }
}

class _RailTopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          const SizedBox(width: 74),
          IconButton(
            tooltip: 'Open project',
            onPressed: () => unawaited(_openProject(ref)),
            icon: Icon(
              Icons.download_for_offline,
              color: tokens.accent,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProject(WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    final openResult = await ref
        .read(fileTreeProvider.notifier)
        .openDirectory(result);
    if (!openResult.success) return;
    ref.read(settingsProvider.notifier).addRecentProject(result);
    ref.read(studioShellProvider.notifier).openProject(result);
  }
}

class _RailAction extends ConsumerWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RailAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Row(
            children: [
              Icon(icon, size: 16, color: tokens.textSecondary),
              const SizedBox(width: Spacing.md),
              Text(
                label,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.sm,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailSectionLabel extends ConsumerWidget {
  final String label;

  const _RailSectionLabel(this.label);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.lg,
        Spacing.md,
        Spacing.sm,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: FontSizes.sm,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RecentProjectGroup extends ConsumerWidget {
  final String path;
  final int taskCount;

  const _RecentProjectGroup({required this.path, required this.taskCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final name = p.basename(path);
    final tasks = ref.watch(agentWorkspaceProvider).tasks.take(2).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProjectRow(name: name, path: path),
          for (var i = 0; i < tasks.length; i++)
            Padding(
              padding: const EdgeInsets.only(
                left: Spacing.xxl,
                right: Spacing.md,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.lg),
                onTap: () {
                  ref
                      .read(agentWorkspaceProvider.notifier)
                      .selectTask(tasks[i].id);
                  ref.read(studioShellProvider.notifier).openTask(tasks[i].id);
                },
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tasks[i].goal,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: FontSizes.sm,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.textMuted.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          '⌘${i + 1}',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: FontSizes.xxs,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProjectRow extends ConsumerWidget {
  final String name;
  final String path;

  const _ProjectRow({required this.name, required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      onTap: () => unawaited(_open(ref)),
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, color: tokens.textSecondary, size: 16),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(WidgetRef ref) async {
    final result = await ref
        .read(fileTreeProvider.notifier)
        .openDirectory(path);
    if (!result.success) {
      if (result.recentProjectStatus == RecentProjectStatus.missing) {
        ref.read(settingsProvider.notifier).removeRecentProject(path);
      }
      return;
    }
    ref.read(settingsProvider.notifier).addRecentProject(path);
    ref.read(studioShellProvider.notifier).openProject(path);
  }
}
