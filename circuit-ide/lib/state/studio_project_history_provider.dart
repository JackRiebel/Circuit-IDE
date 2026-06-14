import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_workspace.dart';
import '../models/studio_thread.dart';
import 'agent_workspace_provider.dart';
import 'file_tree_provider.dart';
import 'settings_provider.dart';
import 'studio_thread_provider.dart';

class StudioProjectHistory {
  final List<AgentTask> tasks;
  final List<StudioThread> threads;

  const StudioProjectHistory({this.tasks = const [], this.threads = const []});
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
    ref.listen(agentWorkspaceProvider, (previous, next) => _mergeLiveProject());
    ref.listen(studioThreadProvider, (previous, next) => _mergeLiveProject());
    return const StudioProjectHistoryState(isLoading: true);
  }

  Future<void> _load() async {
    final paths = ref.read(settingsProvider).recentProjects;
    if (paths.isEmpty) {
      state = const StudioProjectHistoryState();
      return;
    }
    state = StudioProjectHistoryState(byPath: state.byPath, isLoading: true);
    final next = <String, StudioProjectHistory>{};
    for (final path in paths) {
      try {
        next[path] = StudioProjectHistory(
          tasks: await _taskStore.load(path),
          threads: await _threadStore.load(path),
        );
      } catch (_) {
        next[path] = const StudioProjectHistory();
      }
    }
    state = StudioProjectHistoryState(byPath: next);
    _mergeLiveProject();
  }

  void _mergeLiveProject() {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;
    if (!ref.read(settingsProvider).recentProjects.contains(rootPath)) return;
    state = StudioProjectHistoryState(
      byPath: {
        ...state.byPath,
        rootPath: StudioProjectHistory(
          tasks: ref.read(agentWorkspaceProvider).tasks,
          threads: ref.read(studioThreadProvider).threads,
        ),
      },
      isLoading: state.isLoading,
    );
  }
}

final studioProjectHistoryProvider =
    NotifierProvider<StudioProjectHistoryController, StudioProjectHistoryState>(
      StudioProjectHistoryController.new,
    );
