import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/logger.dart';
import '../enums/event_type.dart';
import '../models/ghost_mode_models.dart';
import 'agent_manager_provider.dart';
import 'connection_provider.dart';
import 'editor_provider.dart';

const _ghostPausedMessage =
    'Ghost Mode is paused while Studio uses the request-local turn runtime. '
    'Run this task from Studio so it inherits intent routing, scoped approvals, and deterministic patch review.';

class GhostModeState {
  final List<GhostTask> tasks;

  const GhostModeState({this.tasks = const []});

  int get runningCount =>
      tasks.where((t) => t.status == GhostStatus.running).length;
  GhostTask? get latestCompleted => tasks.cast<GhostTask?>().firstWhere(
    (t) => t!.status == GhostStatus.completed,
    orElse: () => null,
  );

  GhostModeState copyWith({List<GhostTask>? tasks}) =>
      GhostModeState(tasks: tasks ?? this.tasks);
}

class GhostModeNotifier extends Notifier<GhostModeState> {
  @override
  GhostModeState build() => const GhostModeState();
  bool get _ghostModeEnabled => false;

  Future<void> startGhost(String description) async {
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) return;

    final task = GhostTask(description: description);
    if (!_ghostModeEnabled) {
      state = state.copyWith(
        tasks: [
          task.copyWith(
            status: GhostStatus.failed,
            completedAt: DateTime.now(),
            error: _ghostPausedMessage,
          ),
          ...state.tasks,
        ],
      );

      service.events.emit(EventType.ghostFailed, {
        'taskId': task.id,
        'error': _ghostPausedMessage,
      });
      Logger.info('Ghost Mode launch paused', 'GhostMode');
      return;
    }

    state = state.copyWith(
      tasks: [
        task.copyWith(status: GhostStatus.running),
        ...state.tasks,
      ],
    );

    service.events.emit(EventType.ghostStarted, {'taskId': task.id});

    // Snapshot files before changes
    final workingDir = service.state.workingDir;
    final beforeSnapshots = await _snapshotDir(workingDir);

    try {
      // Run via agent manager (auto-approve)
      final agentManager = ref.read(agentManagerProvider.notifier);
      final response = await agentManager.spawnAndAwait(
        description,
        name: 'Ghost',
      );

      // Snapshot files after changes
      final afterSnapshots = await _snapshotDir(workingDir);

      // Compute diffs
      final diffs = _computeDiffs(beforeSnapshots, afterSnapshots);

      // Count totals
      int totalAdds = 0;
      int totalDels = 0;
      for (final d in diffs) {
        totalAdds += d.additions;
        totalDels += d.deletions;
      }

      final summaryText = diffs.isEmpty
          ? 'No files changed'
          : '${diffs.length} file${diffs.length > 1 ? 's' : ''} (+$totalAdds -$totalDels)';

      _updateTask(
        task.id,
        (t) => t.copyWith(
          status: GhostStatus.completed,
          completedAt: DateTime.now(),
          diffs: diffs,
          summary: summaryText,
        ),
      );

      service.events.emit(EventType.ghostCompleted, {
        'taskId': task.id,
        'summary': summaryText,
        'response': response,
      });

      Logger.info('Ghost completed: $summaryText', 'GhostMode');
    } catch (e) {
      _updateTask(
        task.id,
        (t) => t.copyWith(
          status: GhostStatus.failed,
          completedAt: DateTime.now(),
          error: e.toString(),
        ),
      );

      service.events.emit(EventType.ghostFailed, {
        'taskId': task.id,
        'error': e.toString(),
      });

      Logger.error('Ghost failed', e);
    }
  }

  void viewChanges(String taskId) {
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    final editor = ref.read(editorProvider.notifier);

    for (final diff in task.diffs) {
      editor.openDiffTab(
        'Before',
        'After (Ghost)',
        diff.beforeContent,
        diff.afterContent,
      );
    }
  }

  Future<void> undoGhost(String taskId) async {
    final task = state.tasks.firstWhere((t) => t.id == taskId);
    if (task.status != GhostStatus.completed) return;

    final service = ref.read(agentServiceProvider);
    final workingDir = service.state.workingDir;

    // Revert each file to its before state
    for (final diff in task.diffs) {
      try {
        final file = File('$workingDir/${diff.filePath}');
        if (diff.isNew) {
          if (await file.exists()) await file.delete();
        } else {
          await file.writeAsString(diff.beforeContent);
        }
      } catch (e) {
        Logger.error('Failed to revert ghost file: ${diff.filePath}', e);
      }
    }

    _updateTask(taskId, (t) => t.copyWith(status: GhostStatus.undone));
    service.events.emit(EventType.ghostUndone, {'taskId': taskId});
    Logger.info('Ghost undone: $taskId', 'GhostMode');
  }

  void dismissTask(String taskId) {
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.id != taskId).toList(),
    );
  }

  void _updateTask(String id, GhostTask Function(GhostTask) updater) {
    state = state.copyWith(
      tasks: state.tasks.map((t) {
        if (t.id == id) return updater(t);
        return t;
      }).toList(),
    );
  }

  Future<Map<String, String>> _snapshotDir(String dir) async {
    final snapshots = <String, String>{};
    try {
      await for (final entity in Directory(
        dir,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final relPath = entity.path.substring(dir.length + 1);
          // Skip hidden dirs, build artifacts, etc.
          if (relPath.startsWith('.') ||
              relPath.contains('/.') ||
              relPath.contains('/build/') ||
              relPath.startsWith('build/')) {
            continue;
          }
          // Only text-like files
          if (_isTextFile(relPath)) {
            try {
              snapshots[relPath] = await entity.readAsString();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      Logger.error('Snapshot dir failed', e);
    }
    return snapshots;
  }

  List<GhostFileDiff> _computeDiffs(
    Map<String, String> before,
    Map<String, String> after,
  ) {
    final diffs = <GhostFileDiff>[];
    final allPaths = {...before.keys, ...after.keys};

    for (final path in allPaths) {
      final beforeContent = before[path];
      final afterContent = after[path];

      if (beforeContent == afterContent) continue;

      final beforeLines = (beforeContent ?? '').split('\n');
      final afterLines = (afterContent ?? '').split('\n');

      // Simple line count diff
      int adds = 0;
      int dels = 0;
      for (final line in afterLines) {
        if (!beforeLines.contains(line)) adds++;
      }
      for (final line in beforeLines) {
        if (!afterLines.contains(line)) dels++;
      }

      if (adds == 0 && dels == 0) continue;

      diffs.add(
        GhostFileDiff(
          filePath: path,
          beforeContent: beforeContent ?? '',
          afterContent: afterContent ?? '',
          additions: adds,
          deletions: dels,
          isNew: beforeContent == null,
          isDeleted: afterContent == null,
        ),
      );
    }

    return diffs;
  }

  bool _isTextFile(String path) {
    const textExtensions = {
      '.dart',
      '.yaml',
      '.yml',
      '.json',
      '.md',
      '.txt',
      '.xml',
      '.html',
      '.css',
      '.js',
      '.ts',
      '.py',
      '.sh',
      '.toml',
      '.lock',
      '.gradle',
      '.properties',
      '.cfg',
      '.ini',
      '.env',
    };
    for (final ext in textExtensions) {
      if (path.endsWith(ext)) return true;
    }
    return false;
  }
}

final ghostModeProvider = NotifierProvider<GhostModeNotifier, GhostModeState>(
  GhostModeNotifier.new,
);
