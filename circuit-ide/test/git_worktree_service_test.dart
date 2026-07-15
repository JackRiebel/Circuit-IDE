import 'dart:io';

import 'package:circuit_ide/services/git_worktree_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'two isolated tasks keep concurrent edits separate and hand off only after review',
    () async {
      final root = await Directory.systemTemp.createTemp('git_worktree_tasks_');
      final worktreeRoot = Directory(
        p.join(
          p.dirname(root.path),
          '.circuit-worktrees',
          p.basename(root.path),
        ),
      );
      addTearDown(() async {
        await _deleteIfPresent(worktreeRoot);
        await _deleteIfPresent(root);
      });
      await _git(root.path, ['init']);
      await _git(root.path, ['config', 'user.email', 'circuit@example.test']);
      await _git(root.path, ['config', 'user.name', 'Circuit Test']);
      final localFile = File(p.join(root.path, 'config.txt'));
      await localFile.writeAsString('base\n');
      await _git(root.path, ['add', '--', 'config.txt']);
      await _git(root.path, ['commit', '-m', 'Initial config']);

      final service = GitWorktreeService(repositoryRoot: root.path);
      final first = await service.createTaskWorktree(
        taskId: 'first-task',
        taskLabel: 'First task',
      );
      final second = await service.createTaskWorktree(
        taskId: 'second-task',
        taskLabel: 'Second task',
      );

      await File(p.join(first.path, 'config.txt')).writeAsString('first\n');
      await File(p.join(second.path, 'config.txt')).writeAsString('second\n');

      expect(await localFile.readAsString(), 'base\n');
      expect(
        await File(p.join(first.path, 'config.txt')).readAsString(),
        'first\n',
      );
      expect(
        await File(p.join(second.path, 'config.txt')).readAsString(),
        'second\n',
      );

      final firstPreview = await service.previewHandoff(worktree: first);
      expect(firstPreview.canApply, isTrue, reason: firstPreview.blockedReason);
      expect(firstPreview.changedPaths, contains('config.txt'));
      expect(
        (await service.applyHandoff(firstPreview, confirmed: false)).applied,
        isFalse,
      );
      expect(await localFile.readAsString(), 'base\n');

      final applied = await service.applyHandoff(firstPreview, confirmed: true);
      expect(applied.applied, isTrue, reason: applied.evidence);
      expect(await localFile.readAsString(), 'first\n');

      // The second task's checkout has not been touched by the first task's
      // handoff, and its stale handoff is blocked rather than overwriting the
      // newly merged local result.
      expect(
        await File(p.join(second.path, 'config.txt')).readAsString(),
        'second\n',
      );
      final stalePreview = await service.previewHandoff(worktree: second);
      expect(stalePreview.canApply, isFalse);
      expect(stalePreview.blockedReason, contains('local branch moved'));
    },
  );
}

Future<void> _git(String workingDirectory, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode == 0) return;
  final stderr = (result.stderr as String).trim();
  final stdout = (result.stdout as String).trim();
  fail('git ${args.join(' ')} failed: ${stderr.isNotEmpty ? stderr : stdout}');
}

Future<void> _deleteIfPresent(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } catch (_) {
    // Teardown is best effort when Git has already cleaned a temporary tree.
  }
}
