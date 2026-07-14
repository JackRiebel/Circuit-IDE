import 'package:collection/collection.dart';

import '../models/agent_workspace.dart';

const _agentWorkspaceSentinel = Object();

class AgentWorkspaceState {
  final List<AgentTask> tasks;
  final WorkspacePermissionConfiguration projectPolicy;
  final bool isLoading;
  final String? selectedTaskId;
  final String? message;
  final String? error;

  const AgentWorkspaceState({
    this.tasks = const [],
    this.projectPolicy = const WorkspacePermissionConfiguration(),
    this.isLoading = false,
    this.selectedTaskId,
    this.message,
    this.error,
  });

  List<AgentTask> get activeTasks => tasks
      .where(
        (task) =>
            task.status == AgentTaskStatus.queued ||
            task.status == AgentTaskStatus.running ||
            task.status == AgentTaskStatus.paused ||
            task.status == AgentTaskStatus.waitingForApproval,
      )
      .toList(growable: false);

  List<AgentTask> get recentTasks => tasks
      .where(
        (task) =>
            task.status == AgentTaskStatus.completed ||
            task.status == AgentTaskStatus.failed ||
            task.status == AgentTaskStatus.cancelled,
      )
      .toList(growable: false);

  /// Tasks that may enter the execution scheduler. Paused tasks remain visible
  /// in [activeTasks] but are deliberately excluded until the user resumes
  /// them into the queue.
  List<AgentTask> get runnableTasks => tasks
      .where(
        (task) =>
            task.status == AgentTaskStatus.queued ||
            task.status == AgentTaskStatus.running ||
            task.status == AgentTaskStatus.waitingForApproval,
      )
      .toList(growable: false);

  AgentTask? get selectedTask {
    if (selectedTaskId == null) return activeTasks.firstOrNull;
    return tasks.where((task) => task.id == selectedTaskId).firstOrNull;
  }

  AgentWorkspaceState copyWith({
    List<AgentTask>? tasks,
    WorkspacePermissionConfiguration? projectPolicy,
    bool? isLoading,
    Object? selectedTaskId = _agentWorkspaceSentinel,
    Object? message = _agentWorkspaceSentinel,
    Object? error = _agentWorkspaceSentinel,
  }) {
    return AgentWorkspaceState(
      tasks: tasks ?? this.tasks,
      projectPolicy: projectPolicy ?? this.projectPolicy,
      isLoading: isLoading ?? this.isLoading,
      selectedTaskId: identical(selectedTaskId, _agentWorkspaceSentinel)
          ? this.selectedTaskId
          : selectedTaskId as String?,
      message: identical(message, _agentWorkspaceSentinel)
          ? this.message
          : message as String?,
      error: identical(error, _agentWorkspaceSentinel)
          ? this.error
          : error as String?,
    );
  }
}

/// A transient, user-visible handoff when an active background task reaches a
/// terminal state. It is derived from two durable snapshots rather than stored
/// with task history, so reopening a project never replays old notifications.
class AgentTaskCompletionNotice {
  final String taskId;
  final String message;

  const AgentTaskCompletionNotice({
    required this.taskId,
    required this.message,
  });
}

AgentTaskCompletionNotice? taskCompletionNotice(
  AgentWorkspaceState? previous,
  AgentWorkspaceState next,
) {
  if (previous == null) return null;
  final previousById = {for (final task in previous.tasks) task.id: task};
  for (final task in next.tasks) {
    final before = previousById[task.id];
    if (before == null || !_isActiveTaskStatus(before.status)) continue;
    if (!_isTerminalTaskStatus(task.status)) continue;
    final status = switch (task.status) {
      AgentTaskStatus.completed => 'completed',
      AgentTaskStatus.failed => 'failed',
      AgentTaskStatus.cancelled => 'was cancelled',
      _ => '',
    };
    final resultHint =
        task.status == AgentTaskStatus.completed &&
            (task.result?.trim().isNotEmpty ?? false)
        ? ' Open the task to review the result.'
        : '';
    return AgentTaskCompletionNotice(
      taskId: task.id,
      message: '${task.mascotAlias} $status: ${task.goal}.$resultHint',
    );
  }
  return null;
}

bool _isActiveTaskStatus(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.queued ||
    AgentTaskStatus.running ||
    AgentTaskStatus.paused ||
    AgentTaskStatus.waitingForApproval => true,
    AgentTaskStatus.completed ||
    AgentTaskStatus.failed ||
    AgentTaskStatus.cancelled => false,
  };
}

bool _isTerminalTaskStatus(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.completed ||
    AgentTaskStatus.failed ||
    AgentTaskStatus.cancelled => true,
    AgentTaskStatus.queued ||
    AgentTaskStatus.running ||
    AgentTaskStatus.paused ||
    AgentTaskStatus.waitingForApproval => false,
  };
}

class AgentTaskSummaryPage {
  final List<AgentTask> tasks;
  final int totalCount;
  final int offset;

  const AgentTaskSummaryPage({
    required this.tasks,
    required this.totalCount,
    required this.offset,
  });

  int get nextOffset => offset + tasks.length;
  bool get hasMore => nextOffset < totalCount;
}

List<AgentTaskArtifact> upsertAgentTaskArtifact(
  List<AgentTaskArtifact> artifacts,
  AgentTaskArtifact artifact,
) {
  return [
    artifact,
    ...artifacts.where((candidate) => candidate.id != artifact.id),
  ];
}
