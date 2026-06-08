import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_view_models.dart';
import '../../models/workspace_open_result.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/command_run_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';

class StudioLeftRail extends ConsumerWidget {
  const StudioLeftRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
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
            _RailAction(
              icon: Icons.create_new_folder_outlined,
              label: 'New project',
              onTap: () => unawaited(_chooseProjectRoot(ref)),
            ),
            const SizedBox(height: Spacing.xl),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const _RailSectionLabel('Projects'),
                  for (final path in settings.recentProjects)
                    _RecentProjectGroup(path: path),
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
            tooltip: 'Open project folder',
            onPressed: () => unawaited(_chooseProjectRoot(ref)),
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
}

Future<void> _chooseProjectRoot(WidgetRef ref) async {
  final result = await FilePicker.platform.getDirectoryPath();
  if (result == null) return;
  final openResult = await ref
      .read(fileTreeProvider.notifier)
      .openDirectory(result);
  if (!openResult.success) return;
  ref.read(settingsProvider.notifier).addRecentProject(result);
  ref.read(studioShellProvider.notifier).openProject(result);
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

  const _RecentProjectGroup({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = p.basename(path);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final isSelectedProject = rootPath == path;
    final workspace = ref.watch(agentWorkspaceProvider);
    final threadState = ref.watch(studioThreadProvider);
    final chat = ref.watch(chatProvider);
    final commands = ref.watch(commandRunProvider).values;
    final tasks = isSelectedProject
        ? workspace.tasks.take(4).toList()
        : const [];
    final selectedTaskId = ref.watch(studioShellProvider).selectedTaskId;
    final projectSummary = StudioRailProjectSummary(
      path: path,
      name: name,
      selected: isSelectedProject,
      taskCount: tasks.length,
    );
    final taskSummaries = [
      for (final task in tasks)
        StudioRailTaskSummary(
          id: task.id,
          title: task.goal,
          selected: task.id == selectedTaskId,
          displayState: _displayStateForTask(
            task,
            threadState.threadForTask(task.id),
            isSelected: task.id == selectedTaskId,
            chat: chat,
            commands: commands,
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProjectRow(summary: projectSummary),
          for (final task in taskSummaries)
            Padding(
              padding: const EdgeInsets.only(
                left: Spacing.xxl,
                right: Spacing.md,
              ),
              child: _ConversationRow(
                summary: task,
                onTap: () {
                  ref.read(agentWorkspaceProvider.notifier).selectTask(task.id);
                  ref.read(studioShellProvider.notifier).openTask(task.id);
                },
              ),
            ),
        ],
      ),
    );
  }
}

TaskDisplayState _displayStateForTask(
  AgentTask task,
  StudioThread? thread, {
  required bool isSelected,
  required ChatState chat,
  required Iterable<CommandRun> commands,
}) {
  if (thread != null) {
    return TaskDisplayState.fromLifecycle(
      StudioTaskLifecycleState.fromThread(thread),
    );
  }
  return TaskDisplayState.derive(
    task: task,
    isChatProcessing: isSelected && chat.isProcessing,
    isChatStreaming: isSelected && chat.isStreaming,
    hasAssistantResponse: isSelected && hasAssistantResponse(chat.messages),
    hasPendingApproval: isSelected && chat.pendingConfirmation != null,
    commands: isSelected ? commands : const [],
    chatError: isSelected ? chat.error : null,
  );
}

class _ProjectRow extends ConsumerWidget {
  final StudioRailProjectSummary summary;

  const _ProjectRow({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final selected = summary.selected;
    return InkWell(
      onTap: () => unawaited(_open(ref)),
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        decoration: BoxDecoration(
          color: selected
              ? tokens.studioHover.withValues(alpha: 0.86)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: selected
              ? Border.all(color: tokens.outlineSoft.withValues(alpha: 0.7))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              color: selected ? tokens.textPrimary : tokens.textSecondary,
              size: 16,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                summary.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? tokens.textPrimary : tokens.textSecondary,
                  fontSize: FontSizes.sm,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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
        .openDirectory(summary.path);
    if (!result.success) {
      if (result.recentProjectStatus == RecentProjectStatus.missing) {
        ref.read(settingsProvider.notifier).removeRecentProject(summary.path);
      }
      return;
    }
    ref.read(settingsProvider.notifier).addRecentProject(summary.path);
    ref.read(studioShellProvider.notifier).openProject(summary.path);
  }
}

class _ConversationRow extends ConsumerWidget {
  final StudioRailTaskSummary summary;
  final VoidCallback onTap;

  const _ConversationRow({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final selected = summary.selected;
    final display = summary.displayState;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.lg),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        decoration: BoxDecoration(
          color: selected
              ? tokens.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                summary.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? tokens.textPrimary : tokens.textSecondary,
                  fontSize: FontSizes.sm,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? tokens.accent.withValues(alpha: 0.22)
                    : tokens.textMuted.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                display.label,
                style: TextStyle(
                  color: display.needsAttention
                      ? tokens.warning
                      : selected
                      ? tokens.textPrimary
                      : tokens.textMuted,
                  fontSize: FontSizes.xxs,
                  fontWeight: selected || display.needsAttention
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
