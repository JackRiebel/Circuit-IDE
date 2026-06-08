import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/workspace_context.dart';
import '../models/agent_run.dart';
import '../services/file_indexer.dart';
import 'agent_run_provider.dart';
import 'file_tree_provider.dart';

class WorkspaceContextController extends Notifier<WorkspaceContextState> {
  int _generation = 0;

  @override
  WorkspaceContextState build() {
    ref.listen(fileTreeProvider, (previous, next) {
      final previousRoot = previous?.rootPath;
      if (next.rootPath != null && next.rootPath != previousRoot) {
        unawaited(openWorkspace(next.rootPath!));
      }
      if (next.rootPath == null && previousRoot != null) {
        state = const WorkspaceContextState();
      }
    });
    return const WorkspaceContextState();
  }

  Future<void> openWorkspace(String rootPath, {bool forceLsdf = false}) async {
    final normalized = p.normalize(rootPath);
    final generation = ++_generation;

    state = WorkspaceContextState(
      rootPath: normalized,
      status: WorkspaceLifecycleStatus.loading,
      message: 'Preparing workspace context...',
    );
    ref
        .read(agentRunProvider.notifier)
        .startRun(
          id: 'workspace:$generation',
          kind: AgentRunKind.backgroundTask,
          model: 'workspace',
          title: 'Index Workspace',
          inputPreview: normalized,
          message: 'Workspace indexing started',
        );

    try {
      await _indexFiles(normalized, generation);
      if (generation != _generation || state.cancelRequested) return;

      state = state.copyWith(
        status: WorkspaceLifecycleStatus.ready,
        message: 'Workspace context ready',
        error: null,
        refreshedAt: DateTime.now(),
        cancelRequested: false,
      );
      ref
          .read(agentRunProvider.notifier)
          .finishRun(AgentRunKind.backgroundTask, outputPreview: state.message);
    } catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(
        status: WorkspaceLifecycleStatus.error,
        message: 'Workspace context failed',
        error: e.toString(),
        refreshedAt: DateTime.now(),
      );
      ref
          .read(agentRunProvider.notifier)
          .finishRun(AgentRunKind.backgroundTask, error: e.toString());
    }
  }

  Future<void> refresh({bool forceLsdf = false}) async {
    final root = state.rootPath;
    if (root == null) return;
    await openWorkspace(root, forceLsdf: forceLsdf);
  }

  void cancel() {
    _generation++;
    state = state.copyWith(
      status: WorkspaceLifecycleStatus.cancelled,
      message: 'Workspace context cancelled',
      cancelRequested: true,
      refreshedAt: DateTime.now(),
    );
    ref
        .read(agentRunProvider.notifier)
        .requestCancel(AgentRunKind.backgroundTask);
    ref
        .read(agentRunProvider.notifier)
        .finishRun(AgentRunKind.backgroundTask, cancelled: true);
  }

  Future<void> _indexFiles(String rootPath, int generation) async {
    state = state.copyWith(
      status: WorkspaceLifecycleStatus.indexing,
      fileIndexProgress: WorkspaceIndexProgress(
        label: 'Indexing files...',
        updatedAt: DateTime.now(),
      ),
    );
    ref
        .read(agentRunProvider.notifier)
        .addEvent(
          AgentRunKind.backgroundTask,
          AgentRunEventType.contextPrepared,
          'Indexing files',
        );

    final indexer = FileIndexer(workingDir: rootPath);
    await indexer.index();
    if (generation != _generation) return;

    state = state.copyWith(
      fileIndexProgress: WorkspaceIndexProgress(
        label: 'File index ready',
        files: indexer.files.where((file) => !file.isDirectory).length,
        directories: indexer.files.where((file) => file.isDirectory).length,
        updatedAt: DateTime.now(),
      ),
    );
    ref
        .read(agentRunProvider.notifier)
        .addEvent(
          AgentRunKind.backgroundTask,
          AgentRunEventType.contextPrepared,
          'File index ready · ${indexer.files.length} entries',
        );
  }
}

final workspaceContextProvider =
    NotifierProvider<WorkspaceContextController, WorkspaceContextState>(
      WorkspaceContextController.new,
    );
