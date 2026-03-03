import 'dart:async';

import '../../core/utils/logger.dart';

/// Callback type for spawning a subagent and awaiting its result.
typedef SpawnAndAwaitFn = Future<String> Function(
  String task, {
  String? name,
});

/// Tool executor for the `orchestrate` tool.
/// Spawns a subagent via the provided callback and awaits its response.
class OrchestrateToolExecutor {
  final SpawnAndAwaitFn _spawnAndAwait;
  final Duration timeout;

  OrchestrateToolExecutor({
    required SpawnAndAwaitFn spawnAndAwait,
    this.timeout = const Duration(seconds: 120),
  }) : _spawnAndAwait = spawnAndAwait;

  Future<String> execute(Map<String, dynamic> args) async {
    final task = args['task'] as String?;
    final name = args['name'] as String?;

    if (task == null || task.isEmpty) {
      return 'Error: "task" is required for orchestrate tool';
    }

    Logger.info(
      'Orchestrating subagent "${name ?? "unnamed"}": $task',
      'OrchestrateToolExecutor',
    );

    try {
      final result = await _spawnAndAwait(task, name: name)
          .timeout(timeout);
      return result;
    } on TimeoutException {
      return 'Error: Subagent "${name ?? "unnamed"}" timed out after ${timeout.inSeconds}s';
    } catch (e) {
      Logger.error('Orchestration failed for "${name ?? "unnamed"}"', e);
      return 'Error: Subagent failed — $e';
    }
  }
}
