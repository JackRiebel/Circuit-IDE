import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/platform_utils.dart';
import '../models/agent_workspace.dart';
import '../models/reviewed_edit.dart';
import 'context_pack_provider.dart';
import 'file_tree_provider.dart';
import 'patch_proposal_provider.dart';
import 'work_item_provider.dart';

const _uuid = Uuid();

class AgentWorkspaceState {
  final List<AgentTask> tasks;
  final bool isLoading;
  final String? selectedTaskId;
  final String? message;
  final String? error;

  const AgentWorkspaceState({
    this.tasks = const [],
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

  AgentTask? get selectedTask {
    if (selectedTaskId == null) return activeTasks.firstOrNull;
    return tasks.where((task) => task.id == selectedTaskId).firstOrNull;
  }

  AgentWorkspaceState copyWith({
    List<AgentTask>? tasks,
    bool? isLoading,
    Object? selectedTaskId = _sentinel,
    Object? message = _sentinel,
    Object? error = _sentinel,
  }) {
    return AgentWorkspaceState(
      tasks: tasks ?? this.tasks,
      isLoading: isLoading ?? this.isLoading,
      selectedTaskId: identical(selectedTaskId, _sentinel)
          ? this.selectedTaskId
          : selectedTaskId as String?,
      message: identical(message, _sentinel)
          ? this.message
          : message as String?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

class AgentWorkspaceStore {
  final String baseDir;

  AgentWorkspaceStore({String? baseDir})
    : baseDir = baseDir ?? p.join(PlatformUtils.configDir, 'agent_workspace');

  String historyPath(String? rootPath) {
    return p.join(baseDir, '${WorkItemStore.projectKey(rootPath)}.json');
  }

  Future<List<AgentTask>> load(String? rootPath) async {
    final file = File(historyPath(rootPath));
    if (!await file.exists()) return const [];
    final json = jsonDecode(await file.readAsString()) as List<dynamic>;
    return json
        .whereType<Map<String, dynamic>>()
        .map(AgentTask.fromJson)
        .nonNulls
        .map(_normalizeLoadedTask)
        .toList();
  }

  AgentTask _normalizeLoadedTask(AgentTask task) {
    if (!_isLoadedActiveTask(task.status)) {
      return task.activeRunId == null ? task : task.copyWith(activeRunId: null);
    }
    final hasResult = task.result?.trim().isNotEmpty ?? false;
    final hasError = task.error?.trim().isNotEmpty ?? false;
    if (task.completedAt != null || hasResult) {
      return task.copyWith(
        status: hasError ? AgentTaskStatus.failed : AgentTaskStatus.completed,
        activeRunId: null,
        error: hasError ? task.error : null,
      );
    }
    return task.copyWith(
      status: AgentTaskStatus.failed,
      activeRunId: null,
      error: task.error ?? 'Interrupted while CircuitCode was closed.',
      completedAt: DateTime.now(),
    );
  }

  bool _isLoadedActiveTask(AgentTaskStatus status) {
    return switch (status) {
      AgentTaskStatus.queued ||
      AgentTaskStatus.running ||
      AgentTaskStatus.waitingForApproval => true,
      AgentTaskStatus.completed ||
      AgentTaskStatus.failed ||
      AgentTaskStatus.cancelled => false,
    };
  }

  Future<void> save(String? rootPath, List<AgentTask> tasks) async {
    final file = File(historyPath(rootPath));
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(tasks.map((task) => task.toJson()).toList()),
    );
  }
}

class AgentWorkspaceController extends Notifier<AgentWorkspaceState> {
  final _store = AgentWorkspaceStore();

  @override
  AgentWorkspaceState build() {
    Future.microtask(_load);
    ref.listen(fileTreeProvider, (previous, next) {
      if (previous?.rootPath != next.rootPath) _load();
    });
    return const AgentWorkspaceState(isLoading: true);
  }

  Future<void> _load() async {
    if (!ref.mounted) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final tasks = await _store.load(ref.read(fileTreeProvider).rootPath);
      if (!ref.mounted) return;
      state = AgentWorkspaceState(tasks: tasks);
    } catch (error) {
      if (!ref.mounted) return;
      state = AgentWorkspaceState(error: error.toString());
    }
  }

  AgentTask startTask({
    required String goal,
    AgentTaskProfile profile = AgentTaskProfile.investigate,
    List<AgentTaskRelationship> relationships = const [],
  }) {
    final trimmed = goal.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(goal, 'goal', 'Goal cannot be empty');
    }
    final alias = _nextAlias();
    final contextPack = ref
        .read(contextPackProvider.notifier)
        .buildForCodingTask(prompt: trimmed);
    final task = AgentTask(
      id: _uuid.v4().substring(0, 8),
      mascotAlias: alias,
      profile: profile,
      status: AgentTaskStatus.running,
      goal: trimmed,
      contextPackId: contextPack.id,
      artifacts: [
        AgentTaskArtifact(
          id: contextPack.id,
          type: AgentTaskArtifactType.contextPack,
          title: 'Context pack',
          detail:
              '${contextPack.visibleItems.length} items · ~${contextPack.estimatedTokens} tokens',
          createdAt: DateTime.now(),
        ),
      ],
      relationships: relationships,
      createdAt: DateTime.now(),
    );
    _upsert(task);
    return task;
  }

  void markWaitingForApproval(String taskId, {String? message}) {
    final task = _find(taskId);
    if (task == null) return;
    _upsert(
      task.copyWith(
        status: AgentTaskStatus.waitingForApproval,
        result: message,
      ),
      message: message ?? '${task.mascotAlias} is waiting for review.',
    );
  }

  void completeTask(String taskId, {String? result}) {
    final task = _find(taskId);
    if (task == null) return;
    _upsert(
      task.copyWith(
        status: AgentTaskStatus.completed,
        result: result,
        completedAt: DateTime.now(),
      ),
      message: '${task.mascotAlias} completed.',
    );
  }

  void failTask(String taskId, String error) {
    final task = _find(taskId);
    if (task == null) return;
    _upsert(
      task.copyWith(
        status: AgentTaskStatus.failed,
        error: error,
        completedAt: DateTime.now(),
      ),
      message: '${task.mascotAlias} failed.',
    );
  }

  void cancelTask(String taskId) {
    final task = _find(taskId);
    if (task == null) return;
    _upsert(
      task.copyWith(
        status: AgentTaskStatus.cancelled,
        completedAt: DateTime.now(),
      ),
      message: '${task.mascotAlias} cancelled.',
    );
  }

  void selectTask(String? taskId) {
    state = state.copyWith(selectedTaskId: taskId);
  }

  void attachPatchSet(String taskId, ProposedPatchSet patchSet) {
    final task = _find(taskId);
    if (task == null) return;
    final nextStatus = switch (patchSet.approvalStatus) {
      PatchApprovalStatus.rejected => AgentTaskStatus.completed,
      PatchApprovalStatus.approved => AgentTaskStatus.completed,
      PatchApprovalStatus.revisionRequested => AgentTaskStatus.running,
      PatchApprovalStatus.proposed => AgentTaskStatus.waitingForApproval,
    };
    final updated = task.copyWith(
      status: nextStatus,
      patchSetIds: {...task.patchSetIds, patchSet.id}.toList(),
      checkpointIds: {
        ...task.checkpointIds,
        if (patchSet.checkpointId != null) patchSet.checkpointId!,
      }.toList(),
      artifacts: _upsertArtifact(
        task.artifacts,
        AgentTaskArtifact(
          id: patchSet.id,
          type: AgentTaskArtifactType.patchProposal,
          title: patchSet.title,
          detail:
              '${patchSet.fileCount} files · ${patchSet.approvalStatus.name}',
          createdAt: DateTime.now(),
        ),
      ),
    );
    _upsert(updated, message: '${task.mascotAlias} proposed a patch.');
  }

  void attachCommandRun(String taskId, String commandRunId, String command) {
    final task = _find(taskId);
    if (task == null) return;
    _upsert(
      task.copyWith(
        commandRunIds: {...task.commandRunIds, commandRunId}.toList(),
        artifacts: _upsertArtifact(
          task.artifacts,
          AgentTaskArtifact(
            id: commandRunId,
            type: AgentTaskArtifactType.commandRun,
            title: 'Command run',
            detail: command,
            createdAt: DateTime.now(),
          ),
        ),
      ),
    );
  }

  List<ProposedPatchSet> comparablePatchSets() {
    final history = ref.read(patchProposalProvider).history;
    final ids = state.tasks.expand((task) => task.patchSetIds).toSet();
    return history.where((patchSet) => ids.contains(patchSet.id)).toList();
  }

  String compareProposals() {
    final proposals = comparablePatchSets();
    if (proposals.isEmpty) return 'No supervised agent proposals yet.';
    return [
      'CircuitCode proposal comparison',
      for (final patch in proposals)
        '- ${patch.title}: ${patch.fileCount} files, ${patch.approvalStatus.name}${patch.comparisonSummary == null ? '' : ' — ${patch.comparisonSummary}'}',
    ].join('\n');
  }

  String diagnosticsFor(String taskId) {
    final task = _find(taskId);
    if (task == null) return 'Agent task not found.';
    return [
      'CircuitCode agent task diagnostics',
      'Task: ${task.mascotAlias} (${task.profile.name})',
      'Status: ${task.status.name}',
      'Goal: ${task.goal}',
      if (task.contextPackId != null) 'Context pack: ${task.contextPackId}',
      if (task.patchSetIds.isNotEmpty)
        'Patch proposals: ${task.patchSetIds.join(', ')}',
      if (task.commandRunIds.isNotEmpty)
        'Commands: ${task.commandRunIds.join(', ')}',
      if (task.checkpointIds.isNotEmpty)
        'Checkpoints: ${task.checkpointIds.join(', ')}',
      if (task.result != null) 'Result: ${task.result}',
      if (task.error != null) 'Error: ${task.error}',
    ].join('\n');
  }

  String _nextAlias() {
    final activeAliases = state.activeTasks
        .map((task) => task.mascotAlias)
        .toSet();
    for (var i = 0; i < AgentMascotAlias.pool.length; i++) {
      final alias = AgentMascotNamePool.aliasForIndex(i);
      if (!activeAliases.contains(alias)) return alias;
    }
    return AgentMascotNamePool.aliasForIndex(state.tasks.length);
  }

  AgentTask? _find(String id) {
    return state.tasks.where((task) => task.id == id).firstOrNull;
  }

  void _upsert(AgentTask task, {String? message}) {
    final tasks = [
      task,
      ...state.tasks.where((candidate) => candidate.id != task.id),
    ];
    state = state.copyWith(
      tasks: tasks,
      selectedTaskId: task.id,
      isLoading: false,
      message: message,
      error: null,
    );
    _persist(tasks);
  }

  Future<void> _persist(List<AgentTask> tasks) async {
    await _store.save(ref.read(fileTreeProvider).rootPath, tasks);
  }
}

List<AgentTaskArtifact> _upsertArtifact(
  List<AgentTaskArtifact> artifacts,
  AgentTaskArtifact artifact,
) {
  return [
    artifact,
    ...artifacts.where((candidate) => candidate.id != artifact.id),
  ];
}

final agentWorkspaceProvider =
    NotifierProvider<AgentWorkspaceController, AgentWorkspaceState>(
      AgentWorkspaceController.new,
    );

const _sentinel = Object();
