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
import '../../state/command_run_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_project_creator.dart';
import '../../state/studio_project_history_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/studio_thread_search_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/workspace_session_provider.dart';
import '../../theme/theme_tokens.dart';
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
          colors: [
            tokens.studioRail.withValues(alpha: 0.98),
            tokens.studioRail,
            tokens.bgMain.withValues(alpha: 0.9),
          ],
          stops: const [0, 0.64, 1],
        ),
        border: Border(
          right: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.46),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 5),
            _RailTopBar(),
            const SizedBox(height: 6),
            _RailAction(
              icon: Icons.edit_square,
              label: 'New chat',
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
            const SizedBox(height: 9),
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
                          fontSize: FontSizes.xs,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _RailAction(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () =>
                  ref.read(studioShellProvider.notifier).openSettings(),
            ),
            const SizedBox(height: 7),
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
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 7, Spacing.sm, 0),
      child: SizedBox(
        height: 28,
        child: TextField(
          autofocus: true,
          onChanged: ref.read(studioThreadSearchProvider.notifier).setQuery,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.xs,
            height: 1.1,
          ),
          decoration: InputDecoration(
            hintText: 'Search chats',
            hintStyle: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
            ),
            prefixIcon: Icon(Icons.search, size: 14, color: tokens.textMuted),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 26,
              minHeight: 26,
            ),
            suffixIcon: StudioChromeIconButton(
              tooltip: 'Close search',
              onTap: ref.read(studioThreadSearchProvider.notifier).close,
              icon: Icons.close,
              width: 24,
              height: 22,
              iconSize: 14,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 26,
              minHeight: 26,
            ),
            filled: true,
            fillColor: tokens.studioHover.withValues(alpha: 0.24),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: 0,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(
                color: tokens.studioDivider.withValues(alpha: 0.36),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(
                color: tokens.studioDivider.withValues(alpha: 0.36),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(
                color: tokens.outlineFocus.withValues(alpha: 0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailTopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioShellProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Row(
        children: [
          const _WindowDot(color: Color(0xFFFF5F57)),
          const SizedBox(width: 8),
          const _WindowDot(color: Color(0xFFFFBD2E)),
          const SizedBox(width: 8),
          const _WindowDot(color: Color(0xFF28C840)),
          const SizedBox(width: 17),
          StudioChromeIconButton(
            tooltip: 'Back',
            onTap: studio.canNavigateBack
                ? ref.read(studioShellProvider.notifier).navigateBack
                : null,
            icon: Icons.arrow_back,
            width: 24,
            height: 22,
            iconSize: 14,
          ),
          const SizedBox(width: 4),
          StudioChromeIconButton(
            tooltip: 'Forward',
            onTap: studio.canNavigateForward
                ? ref.read(studioShellProvider.notifier).navigateForward
                : null,
            icon: Icons.arrow_forward,
            width: 24,
            height: 22,
            iconSize: 14,
          ),
          const Spacer(),
          StudioChromeIconButton(
            tooltip: 'Open project folder',
            onTap: () => unawaited(_chooseProjectRoot(ref)),
            icon: Icons.arrow_downward,
            active: true,
            prominent: true,
            width: 28,
            height: 28,
            iconSize: 14,
          ),
        ],
      ),
    );
  }
}

class _WindowDot extends StatelessWidget {
  final Color color;

  const _WindowDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.46)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create project',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.base,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                'Name a new folder for this Circuit task.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.28,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    height: 1.18,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Project name',
                    labelStyle: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                    ),
                    floatingLabelStyle: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                    ),
                    filled: true,
                    fillColor: tokens.studioControl.withValues(alpha: 0.72),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      borderSide: BorderSide(
                        color: tokens.studioDivider.withValues(alpha: 0.62),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      borderSide: BorderSide(
                        color: tokens.studioDivider.withValues(alpha: 0.62),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      borderSide: BorderSide(
                        color: tokens.outlineFocus.withValues(alpha: 0.76),
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.fromLTRB(9, 7, 5, 7),
                decoration: BoxDecoration(
                  color: tokens.studioControl.withValues(alpha: 0.56),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(
                    color: tokens.studioDivider.withValues(alpha: 0.52),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _parentPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xs,
                          height: 1.2,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _chooseParent,
                      style: _dialogTextButtonStyle(tokens),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: _dialogTextButtonStyle(tokens),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  FilledButton(
                    onPressed: _submit,
                    style: _dialogFilledButtonStyle(tokens),
                    child: const Text('Create'),
                  ),
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

  ButtonStyle _dialogTextButtonStyle(ThemeTokens tokens) {
    return TextButton.styleFrom(
      minimumSize: const Size(0, 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 0),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: tokens.textMuted,
      textStyle: const TextStyle(
        fontSize: FontSizes.xs,
        height: 1.1,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    );
  }

  ButtonStyle _dialogFilledButtonStyle(ThemeTokens tokens) {
    return FilledButton.styleFrom(
      minimumSize: const Size(0, 28),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: tokens.textPrimary,
      foregroundColor: tokens.bgDark,
      textStyle: const TextStyle(
        fontSize: FontSizes.xs,
        height: 1.1,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
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
      padding: const EdgeInsets.fromLTRB(12, 10, Spacing.md, 3),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.textMuted.withValues(alpha: 0.62),
          fontSize: FontSizes.xs,
          fontWeight: FontWeight.w500,
          height: 1.1,
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
    final commands = ref.watch(commandRunProvider).values;
    final tasks = isSelectedProject ? workspace.tasks : history?.tasks ?? [];
    final threads = isSelectedProject
        ? threadState.threads
        : history?.threads ?? [];
    final selectedTaskId = ref.watch(studioShellProvider).selectedTaskId;
    final selectedThreadId = threadState.selectedThreadId;
    final threadTaskIds = threads
        .map((thread) => thread.taskId)
        .whereType<String>()
        .toSet();
    final projectSummary = StudioRailProjectSummary(
      path: path,
      name: name,
      selected: isSelectedProject,
      taskCount:
          threads.length +
          tasks.where((task) => !threadTaskIds.contains(task.id)).length,
    );
    final taskSummaries = [
      for (final task in tasks)
        if (!threadTaskIds.contains(task.id) &&
            (query.isEmpty || task.goal.toLowerCase().contains(query)))
          StudioRailTaskSummary(
            id: task.id,
            title: task.goal,
            selected: isSelectedProject && task.id == selectedTaskId,
            updatedAt: task.completedAt ?? task.createdAt,
            displayState: _displayStateForTask(
              task,
              threads.where((thread) => thread.taskId == task.id).firstOrNull,
              isSelected: isSelectedProject && task.id == selectedTaskId,
              commands: commands,
            ),
          ),
    ];
    final threadSummaries = [
      for (final thread in threads)
        if (query.isEmpty || thread.title.toLowerCase().contains(query))
          StudioRailTaskSummary(
            id: thread.id,
            title: thread.title,
            selected:
                isSelectedProject &&
                selectedTaskId == null &&
                selectedThreadId == thread.id,
            updatedAt: thread.updatedAt,
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
      padding: const EdgeInsets.only(bottom: 5),
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
  required Iterable<CommandRun> commands,
}) {
  if (thread != null) {
    return TaskDisplayState.fromLifecycle(
      StudioTaskLifecycleState.fromThread(thread),
    );
  }
  return TaskDisplayState.derive(
    task: task,
    isChatProcessing: false,
    isChatStreaming: false,
    hasAssistantResponse: false,
    hasPendingApproval: false,
    commands: isSelected
        ? commands.where((command) => command.taskId == task.id)
        : const [],
    chatError: null,
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
      hoverTrailing: StudioChromeIconButton(
        icon: Icons.edit_outlined,
        tooltip: 'New thread in ${summary.name}',
        width: 22,
        height: 22,
        iconSize: 12,
        onTap: () => unawaited(_newThread(ref)),
      ),
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

  Future<void> _newThread(WidgetRef ref) async {
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
    final thread = ref
        .read(studioThreadProvider.notifier)
        .createBlankThread(model: ref.read(settingsProvider).ciscoModel);
    ref.read(agentWorkspaceProvider.notifier).selectTask(null);
    ref.read(studioShellProvider.notifier).openThread(thread.id);
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
    final showStatusIndicator = studioRailShouldShowStatusIndicator(display);
    final ageLabel = studioRailAgeLabel(summary.updatedAt);
    return StudioRailRow(
      label: summary.title,
      selected: selected,
      leftIndent: Spacing.xxl,
      onTap: onTap,
      trailing: showStatusIndicator
          ? _RailStatusIndicator(display: display)
          : ageLabel == null
          ? null
          : _RailAgeLabel(label: ageLabel),
    );
  }
}

bool studioRailShouldShowStatusIndicator(TaskDisplayState display) {
  return display.isActive || display.needsAttention;
}

String? studioRailAgeLabel(DateTime? updatedAt, {DateTime? now}) {
  if (updatedAt == null) return null;
  final current = now ?? DateTime.now();
  final delta = current.difference(updatedAt);
  if (delta.isNegative) return 'now';
  if (delta.inMinutes < 1) return 'now';
  if (delta.inHours < 1) return '${delta.inMinutes}m';
  if (delta.inDays < 1) return '${delta.inHours}h';
  if (delta.inDays < 7) return '${delta.inDays}d';
  if (delta.inDays < 30) return '${(delta.inDays / 7).floor()}w';
  if (delta.inDays < 365) return '${(delta.inDays / 30).floor()}mo';
  return '${(delta.inDays / 365).floor()}y';
}

class _RailAgeLabel extends ConsumerWidget {
  final String label;

  const _RailAgeLabel({required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: tokens.textMuted.withValues(alpha: 0.78),
        fontSize: FontSizes.xs,
        height: 1.1,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _RailStatusIndicator extends ConsumerWidget {
  final TaskDisplayState display;

  const _RailStatusIndicator({required this.display});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final active = display.isActive;
    final color = display.needsAttention
        ? tokens.warning.withValues(alpha: 0.88)
        : tokens.textMuted.withValues(alpha: 0.74);
    return Tooltip(
      message: display.label,
      child: active
          ? SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                backgroundColor: tokens.studioDivider.withValues(alpha: 0.36),
              ),
            )
          : SizedBox(
              width: 12,
              height: 12,
              child: Center(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
    );
  }
}
