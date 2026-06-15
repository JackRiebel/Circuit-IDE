import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../core/utils/platform_utils.dart';
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
import '../../state/studio_project_creator.dart';
import '../../state/studio_project_history_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/studio_thread_search_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/workspace_session_provider.dart';
import 'studio_chrome.dart';

class StudioLeftRail extends ConsumerWidget {
  const StudioLeftRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final history = ref.watch(studioProjectHistoryProvider);
    final projectPaths = [
      ...settings.recentProjects,
      for (final path in history.byPath.keys)
        if (!settings.recentProjects.contains(path)) path,
    ];
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: tokens.studioRail,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tokens.studioRail, tokens.bgMain.withValues(alpha: 0.94)],
        ),
        border: Border(
          right: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.7)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: Spacing.xs),
            _RailTopBar(),
            const SizedBox(height: Spacing.sm),
            _RailAction(
              icon: Icons.edit_square,
              label: 'New task',
              onTap: () => ref.read(studioShellProvider.notifier).openHome(),
            ),
            _RailAction(
              icon: Icons.search,
              label: 'Search',
              onTap: () =>
                  ref.read(studioThreadSearchProvider.notifier).toggle(),
            ),
            _RailAction(
              icon: Icons.create_new_folder_outlined,
              label: 'New project',
              onTap: () => unawaited(_createProject(context, ref)),
            ),
            const _RailSearchBox(),
            const SizedBox(height: Spacing.lg),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const _RailSectionLabel('Projects'),
                  for (final path in projectPaths)
                    _RecentProjectGroup(path: path),
                  if (projectPaths.isEmpty)
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

class _RailSearchBox extends ConsumerWidget {
  const _RailSearchBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(studioThreadSearchProvider);
    if (!search.isOpen) return const SizedBox.shrink();
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.sm, Spacing.sm, 0),
      child: TextField(
        autofocus: true,
        onChanged: ref.read(studioThreadSearchProvider.notifier).setQuery,
        style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.sm),
        decoration: InputDecoration(
          hintText: 'Search tasks',
          hintStyle: TextStyle(color: tokens.textMuted),
          prefixIcon: Icon(Icons.search, size: 16, color: tokens.textMuted),
          suffixIcon: IconButton(
            tooltip: 'Close search',
            onPressed: ref.read(studioThreadSearchProvider.notifier).close,
            icon: Icon(Icons.close, size: 15, color: tokens.textMuted),
          ),
          filled: true,
          fillColor: tokens.studioHover.withValues(alpha: 0.5),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
            borderSide: BorderSide(color: tokens.studioDivider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
            borderSide: BorderSide(color: tokens.studioDivider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
            borderSide: BorderSide(color: tokens.outlineFocus),
          ),
        ),
      ),
    );
  }
}

class _RailTopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Row(
        children: [
          const SizedBox(width: 74),
          StudioChromeIconButton(
            tooltip: 'Open project folder',
            onTap: () => unawaited(_chooseProjectRoot(ref)),
            icon: Icons.download_for_offline,
            active: true,
            width: 30,
            height: 28,
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
      .read(workspaceSessionProvider.notifier)
      .openWorkspaceAndBindAgent(result);
  if (!openResult.success) return;
  ref.read(settingsProvider.notifier).addRecentProject(result);
  ref.read(studioShellProvider.notifier).openProject(result);
}

Future<void> _createProject(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<_NewProjectResult>(
    context: context,
    builder: (context) => const _NewProjectDialog(),
  );
  if (result == null) return;
  final path = await StudioProjectCreator.createProject(
    name: result.name,
    parentPath: result.parentPath,
  );
  final openResult = await ref
      .read(workspaceSessionProvider.notifier)
      .openWorkspaceAndBindAgent(path);
  if (!openResult.success) return;
  ref.read(settingsProvider.notifier).addRecentProject(path);
  ref.read(studioShellProvider.notifier).openProject(path);
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
    return StudioRailRow(icon: icon, label: label, onTap: onTap);
  }
}

class _NewProjectResult {
  final String name;
  final String parentPath;

  const _NewProjectResult({required this.name, required this.parentPath});
}

class _NewProjectDialog extends ConsumerStatefulWidget {
  const _NewProjectDialog();

  @override
  ConsumerState<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends ConsumerState<_NewProjectDialog> {
  late final TextEditingController _nameController;
  late String _parentPath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'New Circuit project');
    _parentPath = PlatformUtils.defaultProjectsDir;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    return Dialog(
      backgroundColor: tokens.studioPanel,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create project',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.lg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                'Name a new folder for this Circuit task.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.sm,
                ),
              ),
              const SizedBox(height: Spacing.lg),
              TextField(
                controller: _nameController,
                autofocus: true,
                style: TextStyle(color: tokens.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Project name',
                  labelStyle: TextStyle(color: tokens.textMuted),
                  filled: true,
                  fillColor: tokens.studioControl,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: tokens.studioDivider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: tokens.studioDivider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: tokens.outlineFocus),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: tokens.studioControl.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.studioDivider),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 16,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        _parentPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.sm,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _chooseParent,
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  FilledButton(onPressed: _submit, child: const Text('Create')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseParent() async {
    final result = await FilePicker.platform.getDirectoryPath(
      initialDirectory: Directory(_parentPath).existsSync()
          ? _parentPath
          : null,
    );
    if (result == null || !mounted) return;
    setState(() => _parentPath = result);
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(
      context,
    ).pop(_NewProjectResult(name: name, parentPath: _parentPath));
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
        Spacing.lg,
        Spacing.lg,
        Spacing.md,
        Spacing.xs,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: FontSizes.xs,
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
    final query = ref
        .watch(studioThreadSearchProvider)
        .query
        .trim()
        .toLowerCase();
    final workspace = ref.watch(agentWorkspaceProvider);
    final threadState = ref.watch(studioThreadProvider);
    final history = ref.watch(studioProjectHistoryProvider).byPath[path];
    final chat = ref.watch(chatProvider);
    final commands = ref.watch(commandRunProvider).values;
    final tasks = isSelectedProject ? workspace.tasks : history?.tasks ?? [];
    final threads = isSelectedProject
        ? threadState.threads
        : history?.threads ?? [];
    final selectedTaskId = ref.watch(studioShellProvider).selectedTaskId;
    final selectedThreadId = threadState.selectedThreadId;
    final projectSummary = StudioRailProjectSummary(
      path: path,
      name: name,
      selected: isSelectedProject,
      taskCount: tasks.length,
    );
    final taskIds = tasks.map((task) => task.id).toSet();
    final taskSummaries = [
      for (final task in tasks)
        if (query.isEmpty || task.goal.toLowerCase().contains(query))
          StudioRailTaskSummary(
            id: task.id,
            title: task.goal,
            selected: isSelectedProject && task.id == selectedTaskId,
            displayState: _displayStateForTask(
              task,
              threads.where((thread) => thread.taskId == task.id).firstOrNull,
              isSelected: isSelectedProject && task.id == selectedTaskId,
              chat: chat,
              commands: commands,
            ),
          ),
    ];
    final threadSummaries = [
      for (final thread in threads)
        if ((thread.taskId == null || !taskIds.contains(thread.taskId)) &&
            (query.isEmpty || thread.title.toLowerCase().contains(query)))
          StudioRailTaskSummary(
            id: thread.id,
            title: thread.title,
            selected:
                isSelectedProject &&
                selectedTaskId == null &&
                selectedThreadId == thread.id,
            displayState: TaskDisplayState.fromLifecycle(
              StudioTaskLifecycleState.fromThread(thread),
            ),
          ),
    ];
    if (query.isNotEmpty &&
        !name.toLowerCase().contains(query) &&
        taskSummaries.isEmpty &&
        threadSummaries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProjectRow(summary: projectSummary),
          for (final task in taskSummaries)
            _ConversationRow(
              summary: task,
              onTap: () =>
                  unawaited(_openTask(ref, projectPath: path, taskId: task.id)),
            ),
          for (final thread in threadSummaries)
            _ConversationRow(
              summary: thread,
              onTap: () => unawaited(
                _openThread(ref, projectPath: path, threadId: thread.id),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openTask(
    WidgetRef ref, {
    required String projectPath,
    required String taskId,
  }) async {
    if (ref.read(fileTreeProvider).rootPath != projectPath) {
      final result = await ref
          .read(workspaceSessionProvider.notifier)
          .openWorkspaceAndBindAgent(projectPath);
      if (!result.success) {
        if (result.openResult?.recentProjectStatus ==
            RecentProjectStatus.missing) {
          ref.read(settingsProvider.notifier).removeRecentProject(projectPath);
        }
        return;
      }
      ref.read(settingsProvider.notifier).addRecentProject(projectPath);
      ref.read(studioShellProvider.notifier).openProject(projectPath);
    }
    ref.read(agentWorkspaceProvider.notifier).selectTask(taskId);
    ref.read(studioShellProvider.notifier).openTask(taskId);
  }

  Future<void> _openThread(
    WidgetRef ref, {
    required String projectPath,
    required String threadId,
  }) async {
    if (ref.read(fileTreeProvider).rootPath != projectPath) {
      final result = await ref
          .read(workspaceSessionProvider.notifier)
          .openWorkspaceAndBindAgent(projectPath);
      if (!result.success) {
        if (result.openResult?.recentProjectStatus ==
            RecentProjectStatus.missing) {
          ref.read(settingsProvider.notifier).removeRecentProject(projectPath);
        }
        return;
      }
      ref.read(settingsProvider.notifier).addRecentProject(projectPath);
      ref.read(studioShellProvider.notifier).openProject(projectPath);
      await ref.read(studioThreadProvider.notifier).reload();
    }
    ref.read(agentWorkspaceProvider.notifier).selectTask(null);
    ref.read(studioShellProvider.notifier).openThread(threadId);
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
    final selected = summary.selected;
    return StudioRailRow(
      icon: Icons.folder_outlined,
      label: summary.name,
      selected: selected,
      project: true,
      onTap: () => unawaited(_open(ref)),
    );
  }

  Future<void> _open(WidgetRef ref) async {
    final result = await ref
        .read(workspaceSessionProvider.notifier)
        .openWorkspaceAndBindAgent(summary.path);
    if (!result.success) {
      if (result.openResult?.recentProjectStatus ==
          RecentProjectStatus.missing) {
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
    final selected = summary.selected;
    final display = summary.displayState;
    return StudioRailRow(
      label: summary.title,
      selected: selected,
      leftIndent: Spacing.xxl,
      onTap: onTap,
      trailing: StudioMiniChip(
        label: display.label,
        attention: display.needsAttention,
      ),
    );
  }
}
