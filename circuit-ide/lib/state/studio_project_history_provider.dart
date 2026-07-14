import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_workspace.dart';
import '../models/studio_thread.dart';
import '../services/project_history_path_scanner.dart';
import '../services/worker_cancellation.dart';
import 'agent_workspace_provider.dart';
import 'file_tree_provider.dart';
import 'settings_provider.dart';
import 'studio_thread_provider.dart';

class StudioProjectHistory {
  final List<AgentTask> tasks;
  final List<StudioThread> threads;
  final int totalTaskCount;
  final int totalThreadCount;
  final bool hasMoreTasks;
  final bool hasMoreThreads;

  const StudioProjectHistory({
    this.tasks = const [],
    this.threads = const [],
    this.totalTaskCount = 0,
    this.totalThreadCount = 0,
    this.hasMoreTasks = false,
    this.hasMoreThreads = false,
  });
}

class StudioProjectHistoryState {
  final Map<String, StudioProjectHistory> byPath;
  final bool isLoading;

  const StudioProjectHistoryState({
    this.byPath = const {},
    this.isLoading = false,
  });
}

class StudioProjectHistoryController
    extends Notifier<StudioProjectHistoryState> {
  final _taskStore = AgentWorkspaceStore();
  final _threadStore = StudioThreadStore();
  final _pathScanner = const ProjectHistoryPathScanner();
  int _loadGeneration = 0;
  WorkerCancellationToken? _pathScanCancellation;

  @override
  StudioProjectHistoryState build() {
    Future.microtask(_load);
    ref.listen(settingsProvider.select((settings) => settings.recentProjects), (
      previous,
      next,
    ) {
      _load();
    });
    ref.listen(fileTreeProvider.select((state) => state.rootPath), (
      previous,
      next,
    ) {
      _load();
    });
    ref.onDispose(() {
      _pathScanCancellation?.cancel('Project history controller disposed.');
      _pathScanCancellation = null;
    });
    return const StudioProjectHistoryState(isLoading: true);
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    _pathScanCancellation?.cancel('Project history refresh superseded.');
    final cancellation = WorkerCancellationToken();
    _pathScanCancellation = cancellation;
    List<String> paths;
    try {
      paths = await _projectPaths(cancellationToken: cancellation);
    } on WorkerCancelledException {
      return;
    } finally {
      if (identical(_pathScanCancellation, cancellation)) {
        _pathScanCancellation = null;
      }
    }
    if (!ref.mounted || generation != _loadGeneration) return;
    if (paths.isEmpty) {
      state = const StudioProjectHistoryState();
      return;
    }
    state = StudioProjectHistoryState(byPath: state.byPath, isLoading: true);
    final next = <String, StudioProjectHistory>{};
    for (final path in paths) {
      try {
        final taskPage = await _taskStore.loadSummaryPage(path);
        final threadPage = await _threadStore.loadSummaryPage(path);
        next[path] = StudioProjectHistory(
          tasks: taskPage.tasks,
          threads: threadPage.threads,
          totalTaskCount: taskPage.totalCount,
          totalThreadCount: threadPage.totalCount,
          hasMoreTasks: taskPage.hasMore,
          hasMoreThreads: threadPage.hasMore,
        );
      } catch (_) {
        next[path] = const StudioProjectHistory();
      }
      if (!ref.mounted || generation != _loadGeneration) return;
    }
    if (!ref.mounted || generation != _loadGeneration) return;
    state = StudioProjectHistoryState(byPath: next);
    _mergeLiveProject();
  }

  void _mergeLiveProject() {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;
    state = StudioProjectHistoryState(
      byPath: {
        ...state.byPath,
        rootPath: StudioProjectHistory(
          tasks: ref.read(agentWorkspaceProvider).tasks,
          threads: ref.read(studioThreadProvider).threads,
          totalTaskCount: ref.read(agentWorkspaceProvider).tasks.length,
          totalThreadCount: ref.read(studioThreadProvider).threads.length,
        ),
      },
      isLoading: state.isLoading,
    );
  }

  Future<void> loadMoreHistory(String path, {int pageSize = 24}) async {
    final history = state.byPath[path];
    if (history == null || (!history.hasMoreTasks && !history.hasMoreThreads)) {
      return;
    }
    final taskPage = history.hasMoreTasks
        ? await _taskStore.loadSummaryPage(
            path,
            offset: history.tasks.length,
            limit: pageSize,
          )
        : null;
    final threadPage = history.hasMoreThreads
        ? await _threadStore.loadSummaryPage(
            path,
            offset: history.threads.length,
            limit: pageSize,
          )
        : null;
    if (!ref.mounted) return;
    final knownTaskIds = history.tasks.map((task) => task.id).toSet();
    final tasks = [
      ...history.tasks,
      if (taskPage != null)
        ...taskPage.tasks.where((task) => knownTaskIds.add(task.id)),
    ];
    final knownThreadIds = history.threads.map((thread) => thread.id).toSet();
    final threads = [
      ...history.threads,
      if (threadPage != null)
        ...threadPage.threads.where((thread) => knownThreadIds.add(thread.id)),
    ];
    state = StudioProjectHistoryState(
      byPath: {
        ...state.byPath,
        path: StudioProjectHistory(
          tasks: tasks,
          threads: threads,
          totalTaskCount: taskPage?.totalCount ?? history.totalTaskCount,
          totalThreadCount: threadPage?.totalCount ?? history.totalThreadCount,
          hasMoreTasks: taskPage?.hasMore ?? history.hasMoreTasks,
          hasMoreThreads: threadPage?.hasMore ?? history.hasMoreThreads,
        ),
      },
      isLoading: state.isLoading,
    );
  }

  @Deprecated('Use loadMoreHistory to page task and thread metadata together.')
  Future<void> loadMoreThreads(String path, {int pageSize = 24}) =>
      loadMoreHistory(path, pageSize: pageSize);

  Future<List<String>> _projectPaths({
    WorkerCancellationToken? cancellationToken,
  }) async {
    final configured = ref.read(settingsProvider).recentProjects;
    final recovered = await _pathScanner.recover(
      storageDirectories: [_taskStore.baseDir, _threadStore.baseDir],
      cancellationToken: cancellationToken,
    );
    return [
      ...configured,
      for (final path in recovered)
        if (!configured.contains(path)) path,
    ];
  }
}

final studioProjectHistoryProvider =
    NotifierProvider<StudioProjectHistoryController, StudioProjectHistoryState>(
      StudioProjectHistoryController.new,
    );
