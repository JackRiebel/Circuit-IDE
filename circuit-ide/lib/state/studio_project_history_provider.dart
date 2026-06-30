import 'dart:convert';
import 'dart:io';

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
  int _loadGeneration = 0;

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
    return const StudioProjectHistoryState(isLoading: true);
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final paths = await _projectPaths();
    if (!ref.mounted || generation != _loadGeneration) return;
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
          threads: await _threadStore.loadSummaries(path),
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
        ),
      },
      isLoading: state.isLoading,
    );
  }

  Future<List<String>> _projectPaths() async {
    final configured = ref.read(settingsProvider).recentProjects;
    final recovered = <String>{};
    for (final dirPath in [_taskStore.baseDir, _threadStore.baseDir]) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final name = entity.uri.pathSegments.last.replaceFirst('.json', '');
        final decoded = _decodeProjectKey(name);
        if (decoded != null && await Directory(decoded).exists()) {
          recovered.add(decoded);
        }
      }
    }
    return [
      ...configured,
      for (final path in recovered)
        if (!configured.contains(path)) path,
    ];
  }

  String? _decodeProjectKey(String key) {
    if (key == 'scratch') return null;
    try {
      final normalized = base64Url.normalize(key);
      return utf8.decode(base64Url.decode(normalized));
    } catch (_) {
      return null;
    }
  }
}

final studioProjectHistoryProvider =
    NotifierProvider<StudioProjectHistoryController, StudioProjectHistoryState>(
      StudioProjectHistoryController.new,
    );
