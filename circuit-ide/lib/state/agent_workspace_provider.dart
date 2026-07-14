import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/platform_utils.dart';
import '../models/agent_workspace.dart';
import '../models/git_worktree_models.dart';
import '../models/reviewed_edit.dart';
import '../services/git_worktree_service.dart';
import '../services/summary_index_page_reader.dart';
import '../services/versioned_json_document.dart';
import '../services/worker_cancellation.dart';
import 'context_pack_provider.dart';
import 'agent_workspace_records.dart';
import 'file_tree_provider.dart';
import 'patch_proposal_provider.dart';
import 'work_item_provider.dart';

export 'agent_workspace_records.dart';

const _uuid = Uuid();

class AgentWorkspaceStore {
  static const _schemaKind = 'circuit.agent-workspace';
  static const _schemaVersion = 4;
  static const _projectPolicySchemaKind = 'circuit.project-network-policy';
  static const _projectPolicySchemaVersion = 1;

  final String baseDir;

  AgentWorkspaceStore({String? baseDir})
    : baseDir = baseDir ?? p.join(PlatformUtils.configDir, 'agent_workspace');

  String historyPath(String? rootPath) {
    return p.join(baseDir, '${WorkItemStore.projectKey(rootPath)}.json');
  }

  String summaryIndexPath(String? rootPath) {
    return p.join(
      baseDir,
      '${WorkItemStore.projectKey(rootPath)}.summary.index.jsonl',
    );
  }

  String projectPolicyPath(String? rootPath) {
    return p.join(
      baseDir,
      '${WorkItemStore.projectKey(rootPath)}.network-policy.json',
    );
  }

  Future<WorkspacePermissionConfiguration> loadProjectPolicy(
    String? rootPath,
  ) async {
    final file = File(projectPolicyPath(rootPath));
    if (!await file.exists()) return const WorkspacePermissionConfiguration();
    final contents = await file.readAsString();
    final document = VersionedJsonDocument.decode(
      jsonDecode(contents),
      expectedKind: _projectPolicySchemaKind,
      currentSchemaVersion: _projectPolicySchemaVersion,
    );
    final payload = document.payload;
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Project network policy payload is invalid.');
    }
    return WorkspacePermissionConfiguration.fromJson(payload);
  }

  Future<void> saveProjectPolicy(
    String? rootPath,
    WorkspacePermissionConfiguration policy,
  ) {
    final document = VersionedJsonDocument(
      kind: _projectPolicySchemaKind,
      schemaVersion: _projectPolicySchemaVersion,
      payload: policy.toJson(),
    );
    return writeVersionedJsonAtomically(
      File(projectPolicyPath(rootPath)),
      document.encode(pretty: true),
    );
  }

  Future<List<AgentTask>> load(String? rootPath) async {
    final file = File(historyPath(rootPath));
    if (!await file.exists()) return const [];
    final contents = await file.readAsString();
    final document = VersionedJsonDocument.decode(
      jsonDecode(contents),
      expectedKind: _schemaKind,
      currentSchemaVersion: _schemaVersion,
    );
    final payload = document.payload;
    if (payload is! List<dynamic>) {
      throw const FormatException('Agent workspace payload is not a list.');
    }
    final tasks = payload
        .whereType<Map<String, dynamic>>()
        .map(AgentTask.fromJson)
        .nonNulls
        .map(_normalizeLoadedTask)
        .toList();
    if (document.schemaVersion < _schemaVersion) {
      await migrateVersionedJsonFile(
        file: file,
        originalContents: contents,
        migratedContents: _encode(tasks),
        previousSchemaVersion: document.schemaVersion,
      );
    }
    return tasks;
  }

  AgentTask _normalizeLoadedTask(AgentTask task) {
    if (task.status == AgentTaskStatus.queued) {
      // Queued work has not started. It remains eligible for FIFO promotion
      // once its recovered predecessor is resumed or cancelled.
      return task.activeRunId == null ? task : task.copyWith(activeRunId: null);
    }
    if (task.backgroundExecutionRequested &&
        (task.status == AgentTaskStatus.running ||
            task.status == AgentTaskStatus.waitingForApproval) &&
        task.completedAt == null &&
        !(task.result?.trim().isNotEmpty ?? false)) {
      // A local provider stream cannot safely continue across an app restart.
      // Preserve the durable task and its thread, then require an explicit
      // resume so the next request is visible and cannot duplicate work.
      return task.copyWith(
        status: AgentTaskStatus.paused,
        activeRunId: null,
        error:
            'Paused because CircuitCode was closed. Resume to continue safely.',
      );
    }
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
      AgentTaskStatus.paused => false,
      AgentTaskStatus.completed ||
      AgentTaskStatus.failed ||
      AgentTaskStatus.cancelled => false,
    };
  }

  Future<void> save(String? rootPath, List<AgentTask> tasks) async {
    final file = File(historyPath(rootPath));
    await writeVersionedJsonAtomically(file, _encode(tasks));
    await _writeSummaryIndex(rootPath, tasks);
  }

  Future<AgentTaskSummaryPage> loadSummaryPage(
    String? rootPath, {
    int offset = 0,
    int limit = 12,
    WorkerCancellationToken? cancellationToken,
  }) async {
    final safeOffset = offset < 0 ? 0 : offset;
    final safeLimit = limit.clamp(1, 100);
    final index = File(summaryIndexPath(rootPath));
    if (!await index.exists()) {
      final tasks = await load(rootPath);
      if (tasks.isNotEmpty) await _writeSummaryIndex(rootPath, tasks);
      return AgentTaskSummaryPage(
        tasks: tasks.skip(safeOffset).take(safeLimit).toList(),
        totalCount: tasks.length,
        offset: safeOffset,
      );
    }
    final indexPage = await const SummaryIndexPageReader().read(
      path: index.path,
      headerKind: 'circuit.agent-task-summary-index',
      offset: safeOffset,
      limit: safeLimit,
      cancellationToken: cancellationToken,
    );
    final page = <AgentTask>[];
    for (final decoded in indexPage.records) {
      try {
        final task = AgentTask.fromJson(Map<String, dynamic>.from(decoded));
        if (task != null) page.add(_normalizeLoadedTask(task));
      } catch (_) {
        // A corrupt metadata row never prevents loading later task history.
      }
    }
    return AgentTaskSummaryPage(
      tasks: page,
      totalCount: indexPage.totalCount,
      offset: safeOffset,
    );
  }

  Future<void> _writeSummaryIndex(
    String? rootPath,
    List<AgentTask> tasks,
  ) async {
    final summaries = tasks.map(_taskSummary).toList();
    final lines = [
      jsonEncode({
        'kind': 'circuit.agent-task-summary-index',
        'version': 1,
        'totalCount': summaries.length,
      }),
      for (final task in summaries) jsonEncode(task.toJson()),
    ];
    await writeVersionedJsonAtomically(
      File(summaryIndexPath(rootPath)),
      '${lines.join('\n')}\n',
    );
  }

  AgentTask _taskSummary(AgentTask task) {
    return AgentTask(
      id: task.id,
      mascotAlias: task.mascotAlias,
      profile: task.profile,
      status: task.status,
      goal: task.goal,
      workspaceMode: task.workspaceMode,
      policy: task.policy,
      workspaceRoot: task.workspaceRoot,
      worktreePath: task.worktreePath,
      worktreeBranch: task.worktreeBranch,
      worktreeBaseRevision: task.worktreeBaseRevision,
      result: task.result,
      error: task.error,
      createdAt: task.createdAt,
      completedAt: task.completedAt,
    );
  }

  String _encode(List<AgentTask> tasks) => VersionedJsonDocument(
    kind: _schemaKind,
    schemaVersion: _schemaVersion,
    payload: tasks.map((task) => task.toJson()).toList(),
  ).encode(pretty: true);
}

class AgentWorkspaceController extends Notifier<AgentWorkspaceState> {
  static const maxQueuedCurrentWorkspaceTasks = 8;
  final _store = AgentWorkspaceStore();
  int _loadGeneration = 0;

  @override
  AgentWorkspaceState build() {
    final initialLoadGeneration = ++_loadGeneration;
    Future.microtask(() => _load(generation: initialLoadGeneration));
    ref.listen(fileTreeProvider, (previous, next) {
      if (previous?.rootPath != next.rootPath) _load();
    });
    return const AgentWorkspaceState(isLoading: true);
  }

  Future<void> _load({int? generation}) async {
    if (!ref.mounted) return;
    final activeGeneration = generation ?? ++_loadGeneration;
    if (activeGeneration != _loadGeneration) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final rootPath = ref.read(fileTreeProvider).rootPath;
      final tasks = await _store.load(rootPath);
      final projectPolicy = await _store.loadProjectPolicy(rootPath);
      if (!ref.mounted || activeGeneration != _loadGeneration) return;
      state = AgentWorkspaceState(tasks: tasks, projectPolicy: projectPolicy);
    } catch (error) {
      if (!ref.mounted || activeGeneration != _loadGeneration) return;
      state = AgentWorkspaceState(error: error.toString());
    }
  }

  /// Reload persisted task records after a user-initiated project import.
  Future<void> reload() => _load();

  AgentTask startTask({
    required String goal,
    AgentTaskProfile profile = AgentTaskProfile.investigate,
    List<AgentTaskRelationship> relationships = const [],
    AgentTaskWorkspaceMode workspaceMode =
        AgentTaskWorkspaceMode.currentWorkspace,
    bool backgroundExecutionRequested = false,
  }) {
    final trimmed = goal.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(goal, 'goal', 'Goal cannot be empty');
    }
    final alias = _nextAlias();
    final contextPack = ref
        .read(contextPackProvider.notifier)
        .buildForCodingTask(prompt: trimmed);
    final workspaceRoot = ref.read(fileTreeProvider).rootPath;
    final queuedCurrentWorkspaceCount = state.tasks
        .where(
          (candidate) =>
              candidate.workspaceMode ==
                  AgentTaskWorkspaceMode.currentWorkspace &&
              candidate.workspaceRoot == workspaceRoot &&
              candidate.status == AgentTaskStatus.queued,
        )
        .length;
    final queueForWorkspaceSafety =
        workspaceMode == AgentTaskWorkspaceMode.currentWorkspace &&
        state.activeTasks.any(
          (candidate) =>
              candidate.workspaceMode ==
                  AgentTaskWorkspaceMode.currentWorkspace &&
              candidate.workspaceRoot == workspaceRoot &&
              (candidate.status == AgentTaskStatus.running ||
                  candidate.status == AgentTaskStatus.waitingForApproval),
        );
    if (queueForWorkspaceSafety &&
        queuedCurrentWorkspaceCount >= maxQueuedCurrentWorkspaceTasks) {
      throw StateError(
        'This workspace already has $maxQueuedCurrentWorkspaceTasks queued tasks. Resume, cancel, or isolate a task before adding another.',
      );
    }
    final task = AgentTask(
      id: _uuid.v4().substring(0, 8),
      mascotAlias: alias,
      profile: profile,
      status: queueForWorkspaceSafety
          ? AgentTaskStatus.queued
          : AgentTaskStatus.running,
      goal: trimmed,
      workspaceMode: workspaceMode,
      policy: _taskPolicyForProfile(profile),
      workspaceRoot: workspaceRoot,
      backgroundExecutionRequested: backgroundExecutionRequested,
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
      queuedAt: queueForWorkspaceSafety ? _nextQueuedAt() : null,
    );
    _upsert(
      task,
      message: queueForWorkspaceSafety
          ? '${task.mascotAlias} queued until the current workspace is available.'
          : null,
    );
    return task;
  }

  /// Starts a task in a dedicated Git checkout. The task is persisted only
  /// after `git worktree add` has succeeded, so a failed setup can never leave
  /// a task that appears isolated while its tools still target the main tree.
  Future<AgentTask?> startIsolatedTask({
    required String goal,
    AgentTaskProfile profile = AgentTaskProfile.patch,
    List<AgentTaskRelationship> relationships = const [],
  }) async {
    final task = startTask(
      goal: goal,
      profile: profile,
      relationships: relationships,
      workspaceMode: AgentTaskWorkspaceMode.currentWorkspace,
    );
    final isolated = await createIsolatedWorktree(task.id);
    if (isolated != null) return isolated;
    final error = state.error ?? 'Could not create an isolated task worktree.';
    failTask(task.id, error);
    return null;
  }

  Future<AgentTask?> createIsolatedWorktree(String taskId) async {
    final task = _find(taskId);
    if (task == null) {
      state = state.copyWith(error: 'Agent task not found.');
      return null;
    }
    if (task.hasUsableIsolatedWorktree) return task;
    final root = task.workspaceRoot ?? ref.read(fileTreeProvider).rootPath;
    if (root == null || root.trim().isEmpty) {
      state = state.copyWith(
        error: 'Open a Git project before creating an isolated task worktree.',
      );
      return null;
    }
    try {
      final worktree = await GitWorktreeService(
        repositoryRoot: root,
      ).createTaskWorktree(taskId: task.id, taskLabel: task.goal);
      final updated = task.copyWith(
        workspaceMode: AgentTaskWorkspaceMode.isolatedWorktree,
        workspaceRoot: worktree.repositoryRoot,
        worktreePath: worktree.path,
        worktreeBranch: worktree.branch,
        worktreeBaseRevision: worktree.baseRevision,
      );
      _upsert(
        updated,
        message: '${task.mascotAlias} is now isolated in ${worktree.branch}.',
      );
      return updated;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      return null;
    }
  }

  void useCurrentWorkspace(String taskId) {
    final task = _find(taskId);
    if (task == null) return;
    _upsert(
      task.copyWith(workspaceMode: AgentTaskWorkspaceMode.currentWorkspace),
      message: '${task.mascotAlias} will use the current workspace.',
    );
  }

  Future<GitWorktreeHandoffPreview?> previewWorktreeHandoff(
    String taskId,
  ) async {
    final task = _find(taskId);
    if (task?.worktreePath == null ||
        task?.worktreeBranch == null ||
        task?.worktreeBaseRevision == null ||
        task?.workspaceRoot == null) {
      state = state.copyWith(
        error: 'This task has no isolated worktree to hand off.',
      );
      return null;
    }
    try {
      return await GitWorktreeService(
        repositoryRoot: task!.workspaceRoot!,
      ).previewHandoff(
        worktree: GitTaskWorktree(
          repositoryRoot: task.workspaceRoot!,
          path: task.worktreePath!,
          branch: task.worktreeBranch!,
          baseRevision: task.worktreeBaseRevision!,
        ),
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
      return null;
    }
  }

  Future<GitWorktreeHandoffResult?> applyWorktreeHandoff(
    String taskId,
    GitWorktreeHandoffPreview preview, {
    required bool confirmed,
  }) async {
    final task = _find(taskId);
    if (task?.workspaceRoot == null) return null;
    try {
      final result = await GitWorktreeService(
        repositoryRoot: task!.workspaceRoot!,
      ).applyHandoff(preview, confirmed: confirmed);
      if (result.applied) {
        _upsert(
          task,
          message:
              '${task.mascotAlias} handoff merged into the local workspace.',
        );
      } else {
        state = state.copyWith(error: result.evidence);
      }
      return result;
    } catch (error) {
      state = state.copyWith(error: error.toString());
      return null;
    }
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
    final message = '${task.mascotAlias} completed.';
    _upsert(
      task.copyWith(
        status: AgentTaskStatus.completed,
        activeRunId: null,
        error: null,
        result: result,
        queuedAt: null,
        completedAt: DateTime.now(),
      ),
      message: message,
    );
    _promoteQueuedWorkspaceTask(task, terminalMessage: message);
  }

  void failTask(String taskId, String error) {
    final task = _find(taskId);
    if (task == null) return;
    final message = '${task.mascotAlias} failed.';
    _upsert(
      task.copyWith(
        status: AgentTaskStatus.failed,
        activeRunId: null,
        error: error,
        queuedAt: null,
        completedAt: DateTime.now(),
      ),
      message: message,
    );
    _promoteQueuedWorkspaceTask(task, terminalMessage: message);
  }

  void cancelTask(String taskId) {
    final task = _find(taskId);
    if (task == null) return;
    final message = '${task.mascotAlias} cancelled.';
    _upsert(
      task.copyWith(
        status: AgentTaskStatus.cancelled,
        activeRunId: null,
        queuedAt: null,
        completedAt: DateTime.now(),
      ),
      message: message,
    );
    _promoteQueuedWorkspaceTask(task, terminalMessage: message);
  }

  void _promoteQueuedWorkspaceTask(
    AgentTask releasedTask, {
    required String terminalMessage,
  }) {
    if (!_isCurrentWorkspaceOwner(releasedTask)) {
      return;
    }
    final queued =
        state.tasks
            .where(
              (task) =>
                  task.workspaceMode ==
                      AgentTaskWorkspaceMode.currentWorkspace &&
                  task.workspaceRoot == releasedTask.workspaceRoot &&
                  task.status == AgentTaskStatus.queued,
            )
            .toList()
          ..sort(_compareQueuedTasks);
    if (queued.isEmpty) return;
    final next = queued.first;
    _upsert(
      next.copyWith(
        status: AgentTaskStatus.running,
        queuedAt: null,
        completedAt: null,
      ),
      message: '$terminalMessage ${next.mascotAlias} started from the queue.',
    );
  }

  bool pauseTask(String taskId) {
    final task = _find(taskId);
    if (task == null ||
        (task.status != AgentTaskStatus.queued &&
            task.status != AgentTaskStatus.running)) {
      return false;
    }
    final wasWorkspaceOwner = _isCurrentWorkspaceOwner(task);
    final message =
        '${task.mascotAlias} paused. Resume when this workspace is available.';
    _upsert(
      task.copyWith(
        status: AgentTaskStatus.paused,
        activeRunId: null,
        queuedAt: null,
      ),
      message: message,
    );
    if (wasWorkspaceOwner) {
      _promoteQueuedWorkspaceTask(task, terminalMessage: message);
    }
    return true;
  }

  /// Atomically claims a user-started task before the UI asks Studio to
  /// dispatch it. A claim prevents duplicate listeners from starting the same
  /// task and is replaced by the real request id after registration.
  String? claimBackgroundExecution(String taskId) {
    final task = _find(taskId);
    if (task == null ||
        !task.backgroundExecutionRequested ||
        task.status != AgentTaskStatus.running ||
        task.activeRunId != null) {
      return null;
    }
    final claimId = 'background-claim-${_uuid.v4()}';
    _upsert(task.copyWith(activeRunId: claimId));
    return claimId;
  }

  /// Replaces an in-memory dispatch claim with the request id owned by the
  /// Studio runtime. If a user paused or cancelled during preflight, the
  /// caller must cancel that request instead of allowing it to continue.
  bool bindBackgroundExecutionRequest(
    String taskId, {
    required String claimId,
    required String requestId,
  }) {
    final task = _find(taskId);
    if (task == null ||
        task.activeRunId != claimId ||
        (task.status != AgentTaskStatus.running &&
            task.status != AgentTaskStatus.waitingForApproval)) {
      return false;
    }
    _upsert(task.copyWith(activeRunId: requestId));
    return true;
  }

  /// Releases a dispatch claim when another Studio request won the runtime.
  /// The task remains durable and will be retried only after the lifecycle
  /// becomes idle; it is never silently failed just because it waited.
  bool releaseBackgroundExecutionClaim(String taskId, String claimId) {
    final task = _find(taskId);
    if (task == null || task.activeRunId != claimId) return false;
    _upsert(
      task.copyWith(activeRunId: null),
      message: '${task.mascotAlias} is waiting for the Studio runtime.',
    );
    return true;
  }

  bool resumeTask(String taskId) {
    final task = _find(taskId);
    if (task == null || task.status != AgentTaskStatus.paused) return false;
    final hasCurrentWorkspaceOwner =
        task.workspaceMode == AgentTaskWorkspaceMode.currentWorkspace &&
        state.activeTasks.any(
          (candidate) =>
              candidate.id != task.id &&
              candidate.workspaceMode ==
                  AgentTaskWorkspaceMode.currentWorkspace &&
              candidate.workspaceRoot == task.workspaceRoot &&
              (candidate.status == AgentTaskStatus.running ||
                  candidate.status == AgentTaskStatus.waitingForApproval),
        );
    final resumesIntoQueue = hasCurrentWorkspaceOwner;
    _upsert(
      task.copyWith(
        status: resumesIntoQueue
            ? AgentTaskStatus.queued
            : AgentTaskStatus.running,
        activeRunId: null,
        error: null,
        queuedAt: resumesIntoQueue ? _nextQueuedAt() : null,
        completedAt: null,
      ),
      message: resumesIntoQueue
          ? '${task.mascotAlias} queued to resume.'
          : '${task.mascotAlias} resumed.',
    );
    return true;
  }

  bool _isCurrentWorkspaceOwner(AgentTask task) {
    return task.workspaceMode == AgentTaskWorkspaceMode.currentWorkspace &&
        (task.status == AgentTaskStatus.running ||
            task.status == AgentTaskStatus.waitingForApproval);
  }

  DateTime _nextQueuedAt() {
    DateTime? latestQueuedAt;
    for (final task in state.tasks) {
      if (task.status != AgentTaskStatus.queued) continue;
      final queuePosition = task.queuedAt ?? task.createdAt;
      if (latestQueuedAt == null || queuePosition.isAfter(latestQueuedAt)) {
        latestQueuedAt = queuePosition;
      }
    }
    final now = DateTime.now();
    if (latestQueuedAt != null && !now.isAfter(latestQueuedAt)) {
      return latestQueuedAt.add(const Duration(microseconds: 1));
    }
    return now;
  }

  int _compareQueuedTasks(AgentTask first, AgentTask second) {
    final position = (first.queuedAt ?? first.createdAt).compareTo(
      second.queuedAt ?? second.createdAt,
    );
    return position != 0 ? position : first.id.compareTo(second.id);
  }

  void selectTask(String? taskId) {
    state = state.copyWith(selectedTaskId: taskId);
  }

  /// Saves the current project's network boundary and applies it to existing
  /// task records as well, so an already-open task cannot retain an obsolete
  /// network grant after the project owner tightens the policy.
  Future<void> setProjectNetworkPolicy(
    WorkspacePermissionConfiguration policy,
  ) async {
    _loadGeneration++;
    final sanitizedRules = policy.networkRules
        .map((rule) => WorkspaceNetworkRule.fromJson(rule.toJson()))
        .whereType<WorkspaceNetworkRule>()
        .toList(growable: false);
    final sanitized = policy.copyWith(networkRules: sanitizedRules);
    final tasks = state.tasks
        .map(
          (task) => task.copyWith(
            policy: task.policy.copyWith(
              externalNetwork: sanitized.externalNetwork,
              networkRules: sanitized.networkRules,
            ),
          ),
        )
        .toList(growable: false);
    state = state.copyWith(tasks: tasks, projectPolicy: sanitized, error: null);
    try {
      final rootPath = ref.read(fileTreeProvider).rootPath;
      await _store.saveProjectPolicy(rootPath, sanitized);
      await _store.save(rootPath, tasks);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        error: 'Could not save project network policy: $error',
      );
    }
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
      artifacts: upsertAgentTaskArtifact(
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
        artifacts: upsertAgentTaskArtifact(
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
      'Workspace: ${task.workspaceMode.name}',
      if (task.effectiveWorkspaceRoot != null)
        'Workspace root: ${task.effectiveWorkspaceRoot}',
      if (task.worktreeBranch != null)
        'Worktree branch: ${task.worktreeBranch}',
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

  WorkspacePermissionConfiguration _taskPolicyForProfile(
    AgentTaskProfile profile,
  ) {
    final profilePolicy = AgentTaskProfileSpec.forProfile(profile).policy;
    return profilePolicy.copyWith(
      externalNetwork: state.projectPolicy.externalNetwork,
      networkRules: state.projectPolicy.networkRules,
    );
  }

  void _upsert(AgentTask task, {String? message}) {
    // A user mutation wins over any slower project-load snapshot that started
    // before it. Otherwise opening Studio and immediately starting a task can
    // erase the task when the initial disk read finishes.
    _loadGeneration++;
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

final agentWorkspaceProvider =
    NotifierProvider<AgentWorkspaceController, AgentWorkspaceState>(
      AgentWorkspaceController.new,
    );
