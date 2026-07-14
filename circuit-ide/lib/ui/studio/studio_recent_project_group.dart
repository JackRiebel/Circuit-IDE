import 'dart:async';

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
import '../../state/command_run_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_project_history_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/studio_thread_search_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/workspace_session_provider.dart';
import 'studio_chrome.dart';
import 'studio_rail_row.dart';
import 'studio_workspace_opening.dart';

/// The wall clock used for compact rail age labels. Production reads the
/// current time; deterministic visual fixtures override this without changing
/// the user-facing age-label policy.
final studioRailNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

const _maxCollapsedRailConversations = 8;

/// Displays a project and its bounded, filter-aware task history in the rail.
class StudioRecentProjectGroup extends ConsumerStatefulWidget {
  final String path;

  const StudioRecentProjectGroup({super.key, required this.path});

  @override
  ConsumerState<StudioRecentProjectGroup> createState() =>
      _RecentProjectGroupState();
}

class _RecentProjectGroupState extends ConsumerState<StudioRecentProjectGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    final name = p.basename(path);
    final rootPath = ref.watch(
      fileTreeProvider.select((state) => state.rootPath),
    );
    final isSelectedProject = rootPath == path;
    final searchState = ref.watch(studioThreadSearchProvider);
    final query = searchState.query.trim().toLowerCase();
    final history = isSelectedProject
        ? null
        : ref.watch(
            studioProjectHistoryProvider.select((state) => state.byPath[path]),
          );
    final workspace = isSelectedProject
        ? ref.watch(agentWorkspaceProvider)
        : null;
    final threadState = isSelectedProject
        ? ref.watch(studioThreadProvider)
        : null;
    final runningCommandTaskKey = isSelectedProject
        ? ref.watch(commandRunProvider.select(_runningCommandTaskKey))
        : '';
    final runningCommandTaskIds = runningCommandTaskKey.isEmpty
        ? const <String>{}
        : runningCommandTaskKey.split('\u001f').toSet();
    final tasks = isSelectedProject
        ? workspace?.tasks ?? []
        : history?.tasks ?? [];
    final threads =
        (isSelectedProject
                ? (threadState?.threads ?? [])
                : (history?.threads ?? []))
            .where((thread) => thread.archived == searchState.showArchived)
            .toList()
          ..sort((left, right) {
            if (left.pinned != right.pinned) return left.pinned ? -1 : 1;
            return right.updatedAt.compareTo(left.updatedAt);
          });
    final selectedTaskId = isSelectedProject
        ? ref.watch(studioShellProvider.select((state) => state.selectedTaskId))
        : null;
    final selectedThreadId = threadState?.selectedThreadId;
    final threadTaskIds = threads
        .map((thread) => thread.taskId)
        .whereType<String>()
        .toSet();
    final projectSummary = StudioRailProjectSummary(
      path: path,
      name: name,
      selected: isSelectedProject,
      taskCount:
          (isSelectedProject
              ? threads.length
              : history?.totalThreadCount ?? threads.length) +
          (isSelectedProject
              ? tasks.where((task) => !threadTaskIds.contains(task.id)).length
              : history?.totalTaskCount ?? tasks.length),
    );
    final taskSummaries = [
      for (final task in tasks)
        if (!threadTaskIds.contains(task.id) &&
            (query.isEmpty || task.goal.toLowerCase().contains(query)) &&
            studioRailMatchesTaskFilter(
              _displayStateForTask(
                task,
                threads.where((thread) => thread.taskId == task.id).firstOrNull,
                isSelected: isSelectedProject && task.id == selectedTaskId,
                hasRunningCommand: runningCommandTaskIds.contains(task.id),
              ),
              searchState.statusFilter,
            ))
          StudioRailTaskSummary(
            id: task.id,
            title: task.goal,
            selected: isSelectedProject && task.id == selectedTaskId,
            updatedAt: task.completedAt ?? task.createdAt,
            displayState: _displayStateForTask(
              task,
              threads.where((thread) => thread.taskId == task.id).firstOrNull,
              isSelected: isSelectedProject && task.id == selectedTaskId,
              hasRunningCommand: runningCommandTaskIds.contains(task.id),
            ),
          ),
    ];
    final threadSummaries = [
      for (final thread in threads)
        if ((query.isEmpty || thread.title.toLowerCase().contains(query)) &&
            studioRailMatchesTaskFilter(
              TaskDisplayState.fromLifecycle(
                StudioTaskLifecycleState.fromThread(thread),
              ),
              searchState.statusFilter,
            ))
          StudioRailTaskSummary(
            id: thread.id,
            title: thread.title,
            selected:
                isSelectedProject &&
                selectedTaskId == null &&
                selectedThreadId == thread.id,
            updatedAt: thread.updatedAt,
            pinned: thread.pinned,
            archived: thread.archived,
            displayState: TaskDisplayState.fromLifecycle(
              StudioTaskLifecycleState.fromThread(thread),
            ),
          ),
    ];
    final conversationEntries = [
      for (final task in taskSummaries) (summary: task, isTask: true),
      for (final thread in threadSummaries) (summary: thread, isTask: false),
    ];
    final projectExpanded = isSelectedProject || _expanded || query.isNotEmpty;
    final displayedEntries = projectExpanded
        ? _visibleConversationEntries(
            conversationEntries,
            expanded: _expanded || query.isNotEmpty,
          )
        : const <({StudioRailTaskSummary summary, bool isTask})>[];
    final hiddenCount = conversationEntries.length - displayedEntries.length;
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
          for (final entry in displayedEntries)
            _ConversationRow(
              summary: entry.summary,
              onArchive: isSelectedProject && !entry.isTask
                  ? () => ref
                        .read(studioThreadProvider.notifier)
                        .archiveThread(entry.summary.id)
                  : null,
              onRestore: isSelectedProject && !entry.isTask
                  ? () => ref
                        .read(studioThreadProvider.notifier)
                        .restoreThread(entry.summary.id)
                  : null,
              onTogglePinned: isSelectedProject && !entry.isTask
                  ? () => ref
                        .read(studioThreadProvider.notifier)
                        .setThreadPinned(
                          entry.summary.id,
                          !entry.summary.pinned,
                        )
                  : null,
              onRename: isSelectedProject && !entry.isTask
                  ? (title) => ref
                        .read(studioThreadProvider.notifier)
                        .renameThread(entry.summary.id, title)
                  : null,
              onDelete: isSelectedProject && !entry.isTask
                  ? () => ref
                        .read(studioThreadProvider.notifier)
                        .deleteThread(entry.summary.id)
                  : null,
              onTap: () => unawaited(
                entry.isTask
                    ? _openTask(
                        ref,
                        projectPath: path,
                        taskId: entry.summary.id,
                      )
                    : _openThread(
                        ref,
                        projectPath: path,
                        threadId: entry.summary.id,
                      ),
              ),
            ),
          if (!isSelectedProject && !projectExpanded && hiddenCount > 0)
            _ShowMoreConversationsRow(
              label:
                  'Show $hiddenCount recent ${hiddenCount == 1 ? 'task' : 'tasks'}',
              onTap: () => setState(() => _expanded = true),
            )
          else if (hiddenCount > 0)
            _ShowMoreConversationsRow(
              hiddenCount: hiddenCount,
              onTap: () => setState(() => _expanded = true),
            ),
          if (_expanded &&
              query.isEmpty &&
              conversationEntries.length > _maxCollapsedRailConversations)
            _ShowMoreConversationsRow(
              label: 'Show fewer',
              onTap: () => setState(() => _expanded = false),
            ),
          if (!isSelectedProject &&
              projectExpanded &&
              query.isEmpty &&
              (history?.hasMoreTasks == true ||
                  history?.hasMoreThreads == true))
            _ShowMoreConversationsRow(
              label: 'Load more history',
              onTap: () {
                setState(() => _expanded = true);
                unawaited(
                  ref
                      .read(studioProjectHistoryProvider.notifier)
                      .loadMoreHistory(path),
                );
              },
            ),
        ],
      ),
    );
  }

  List<({StudioRailTaskSummary summary, bool isTask})>
  _visibleConversationEntries(
    List<({StudioRailTaskSummary summary, bool isTask})> entries, {
    required bool expanded,
  }) {
    if (expanded || entries.length <= _maxCollapsedRailConversations) {
      return entries;
    }
    final visible = entries.take(_maxCollapsedRailConversations).toList();
    for (final entry in entries.skip(_maxCollapsedRailConversations)) {
      if (entry.summary.selected &&
          !visible.any(
            (candidate) => candidate.summary.id == entry.summary.id,
          )) {
        visible.add(entry);
      }
    }
    return visible;
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
      recordBoundStudioWorkspace(
        ref,
        requestedPath: projectPath,
        binding: result,
      );
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
      recordBoundStudioWorkspace(
        ref,
        requestedPath: projectPath,
        binding: result,
      );
      await ref.read(studioThreadProvider.notifier).reload();
    }
    ref.read(agentWorkspaceProvider.notifier).selectTask(null);
    ref.read(studioShellProvider.notifier).openThread(threadId);
  }
}

class _ShowMoreConversationsRow extends ConsumerWidget {
  final int? hiddenCount;
  final String? label;
  final VoidCallback onTap;

  const _ShowMoreConversationsRow({
    this.hiddenCount,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final text = label ?? 'Show $hiddenCount more';
    return Padding(
      padding: const EdgeInsets.fromLTRB(31, 1, 10, 2),
      child: StudioFocusableActionSurface(
        key: const ValueKey('studio-rail-history-toggle'),
        semanticLabel: text,
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textMuted.withValues(alpha: 0.82),
              fontSize: FontSizes.xs,
              height: 1.1,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

TaskDisplayState _displayStateForTask(
  AgentTask task,
  StudioThread? thread, {
  required bool isSelected,
  required bool hasRunningCommand,
}) {
  if (thread != null) {
    return TaskDisplayState.fromLifecycle(
      StudioTaskLifecycleState.fromThread(thread),
    );
  }
  if (isSelected && hasRunningCommand) {
    return const TaskDisplayState(
      kind: TaskDisplayKind.runningCommand,
      label: 'Running',
      isActive: true,
    );
  }
  return TaskDisplayState.derive(
    task: task,
    isChatProcessing: false,
    isChatStreaming: false,
    hasAssistantResponse: false,
    hasPendingApproval: false,
    commands: const [],
    chatError: null,
  );
}

String _runningCommandTaskKey(Map<String, CommandRun> state) {
  final ids =
      state.values
          .where((command) => command.status == CommandRunStatus.running)
          .map((command) => command.taskId)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();
  return ids.join('\u001f');
}

class _ProjectRow extends ConsumerWidget {
  final StudioRailProjectSummary summary;

  const _ProjectRow({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = summary.selected;
    return StudioRailRow(
      icon: StudioIcons.folderOutlined,
      label: summary.name,
      selected: selected,
      project: true,
      onTap: () => unawaited(_open(ref)),
      hoverTrailing: StudioChromeIconButton(
        icon: StudioIcons.editOutlined,
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
    recordBoundStudioWorkspace(
      ref,
      requestedPath: summary.path,
      binding: result,
    );
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
    recordBoundStudioWorkspace(
      ref,
      requestedPath: summary.path,
      binding: result,
    );
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
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final VoidCallback? onTogglePinned;
  final bool Function(String)? onRename;
  final bool Function()? onDelete;

  const _ConversationRow({
    required this.summary,
    required this.onTap,
    this.onArchive,
    this.onRestore,
    this.onTogglePinned,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = summary.selected;
    final display = summary.displayState;
    final showStatusIndicator = studioRailShouldShowStatusIndicator(display);
    final ageLabel = studioRailAgeLabel(
      summary.updatedAt,
      now: ref.watch(studioRailNowProvider)(),
    );
    final ageOrStatus = showStatusIndicator
        ? StudioRailTaskStatusIndicator(display: display)
        : ageLabel == null
        ? null
        : _RailAgeLabel(label: ageLabel);
    return StudioRailRow(
      label: summary.title,
      selected: selected,
      leftIndent: Spacing.xxl,
      onTap: onTap,
      hoverTrailing: onArchive == null
          ? null
          : _ThreadActionMenu(
              summary: summary,
              onArchive: onArchive,
              onRestore: onRestore,
              onTogglePinned: onTogglePinned,
              onRename: onRename,
              onDelete: onDelete,
            ),
      trailing: summary.pinned
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(StudioIcons.pushPin, size: 12),
                if (ageOrStatus != null) ...[
                  const SizedBox(width: Spacing.xs),
                  ageOrStatus,
                ],
              ],
            )
          : ageOrStatus,
    );
  }
}

enum _ThreadRailAction { rename, pin, archive, restore, delete }

class _ThreadActionMenu extends StatelessWidget {
  final StudioRailTaskSummary summary;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final VoidCallback? onTogglePinned;
  final bool Function(String)? onRename;
  final bool Function()? onDelete;

  const _ThreadActionMenu({
    required this.summary,
    this.onArchive,
    this.onRestore,
    this.onTogglePinned,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ThreadRailAction>(
      tooltip: 'Task actions',
      icon: const Icon(StudioIcons.moreHoriz, size: 16),
      onSelected: (action) => _handle(context, action),
      itemBuilder: (context) => [
        if (!summary.archived) ...[
          const PopupMenuItem(
            value: _ThreadRailAction.rename,
            child: Text('Rename'),
          ),
          PopupMenuItem(
            value: _ThreadRailAction.pin,
            child: Text(summary.pinned ? 'Unpin' : 'Pin'),
          ),
          const PopupMenuItem(
            value: _ThreadRailAction.archive,
            child: Text('Archive'),
          ),
        ] else ...[
          const PopupMenuItem(
            value: _ThreadRailAction.restore,
            child: Text('Restore to rail'),
          ),
          const PopupMenuItem(
            value: _ThreadRailAction.delete,
            child: Text('Delete permanently'),
          ),
        ],
      ],
    );
  }

  Future<void> _handle(BuildContext context, _ThreadRailAction action) async {
    switch (action) {
      case _ThreadRailAction.rename:
        final title = await _promptForTitle(context, summary.title);
        if (title != null) onRename?.call(title);
      case _ThreadRailAction.pin:
        onTogglePinned?.call();
      case _ThreadRailAction.archive:
        onArchive?.call();
      case _ThreadRailAction.restore:
        onRestore?.call();
      case _ThreadRailAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete archived task?'),
            content: const Text(
              'This permanently deletes the archived task history. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true) onDelete?.call();
    }
  }

  Future<String?> _promptForTitle(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Task title'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim().isEmpty ?? true ? null : result?.trim();
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

/// Compact rail state that remains distinguishable without relying on color:
/// executing work uses a progress ring, queued work a clock, and
/// attention-needed work a warning shape. Assistive technology receives the
/// full textual state.
class StudioRailTaskStatusIndicator extends ConsumerWidget {
  final TaskDisplayState display;

  const StudioRailTaskStatusIndicator({super.key, required this.display});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final active = display.isActive;
    final queued = display.kind == TaskDisplayKind.queued;
    final color = display.needsAttention
        ? tokens.warning.withValues(alpha: 0.88)
        : tokens.textMuted.withValues(alpha: 0.74);
    return Semantics(
      container: true,
      label: 'Task status: ${display.label}',
      child: Tooltip(
        message: display.label,
        child: queued
            ? SizedBox(
                width: 12,
                height: 12,
                child: Center(
                  child: Icon(
                    StudioIcons.scheduleOutlined,
                    color: color,
                    size: 12,
                  ),
                ),
              )
            : active
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
                  child: Icon(
                    StudioIcons.warningAmberRounded,
                    color: color,
                    size: 12,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Applies the shared rail status filter to a projected task state.
bool studioRailMatchesTaskFilter(
  TaskDisplayState display,
  StudioThreadStatusFilter filter,
) => switch (filter) {
  StudioThreadStatusFilter.all => true,
  StudioThreadStatusFilter.active => display.isActive,
  StudioThreadStatusFilter.attention => display.needsAttention,
  StudioThreadStatusFilter.completed =>
    display.kind == TaskDisplayKind.done ||
        display.kind == TaskDisplayKind.cancelled ||
        display.kind == TaskDisplayKind.failed,
};
