import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/git_worktree_models.dart';

/// Creates task-specific worktrees and performs an explicit, guarded handoff.
///
/// This service never force-pushes, resets, checks out the user's main
/// workspace, or deletes a worktree. A handoff is only allowed when the source
/// checkout is clean and still at the revision from which the task was split.
class GitWorktreeService {
  final String repositoryRoot;

  const GitWorktreeService({required this.repositoryRoot});

  Future<GitTaskWorktree> createTaskWorktree({
    required String taskId,
    required String taskLabel,
  }) async {
    final root = await _repositoryRoot();
    final baseRevision = await _required(root, ['rev-parse', 'HEAD']);
    final safeTaskId = _safeSegment(taskId);
    final branch = 'circuit/task-$safeTaskId';
    final baseName = _safeSegment(p.basename(root));
    final path = p.join(
      p.dirname(root),
      '.circuit-worktrees',
      baseName,
      safeTaskId,
    );
    if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
      throw StateError('An isolated worktree already exists for this task.');
    }
    final branchExists = await _run(root, [
      'show-ref',
      '--verify',
      '--quiet',
      'refs/heads/$branch',
    ]);
    if (branchExists.ok) {
      throw StateError('The task branch "$branch" already exists.');
    }
    await Directory(p.dirname(path)).create(recursive: true);
    final add = await _run(root, [
      'worktree',
      'add',
      '-b',
      branch,
      path,
      baseRevision,
    ]);
    if (!add.ok) {
      throw StateError(_failure('Could not create isolated worktree', add));
    }
    return GitTaskWorktree(
      repositoryRoot: root,
      path: path,
      branch: branch,
      baseRevision: baseRevision,
    );
  }

  Future<GitWorktreeHandoffPreview> previewHandoff({
    required GitTaskWorktree worktree,
  }) async {
    final root = await _repositoryRoot();
    if (p.normalize(root) != p.normalize(worktree.repositoryRoot)) {
      return _blocked(worktree, 'This task belongs to a different repository.');
    }
    if (await FileSystemEntity.type(worktree.path) !=
        FileSystemEntityType.directory) {
      return _blocked(
        worktree,
        'The isolated worktree directory no longer exists.',
      );
    }
    final rootStatus = await _run(root, ['status', '--porcelain']);
    if (!rootStatus.ok) {
      return _blocked(
        worktree,
        _failure('Could not inspect the local workspace', rootStatus),
      );
    }
    if (rootStatus.output.trim().isNotEmpty) {
      return _blocked(
        worktree,
        'The local workspace has uncommitted changes. Review or commit them before applying this task result.',
      );
    }
    final currentHead = await _required(root, ['rev-parse', 'HEAD']);
    if (currentHead != worktree.baseRevision) {
      return _blocked(
        worktree,
        'The local branch moved since this task started. Rebase or create a new isolated task before handoff.',
      );
    }
    final taskStatus = await _run(worktree.path, ['status', '--porcelain']);
    if (!taskStatus.ok) {
      return _blocked(
        worktree,
        _failure('Could not inspect the task worktree', taskStatus),
      );
    }
    final branchHead = await _run(root, ['rev-parse', worktree.branch]);
    if (!branchHead.ok) {
      return _blocked(worktree, 'The task branch no longer exists.');
    }
    final mergeCheck = await _run(root, [
      'merge-tree',
      '--write-tree',
      worktree.baseRevision,
      worktree.branch,
    ]);
    if (!mergeCheck.ok) {
      return _blocked(
        worktree,
        'This task result would conflict with the local branch. Resolve it in review before handoff.',
      );
    }
    final commitCount = await _integer(root, [
      'rev-list',
      '--count',
      '${worktree.baseRevision}..${worktree.branch}',
    ]);
    final diff = await _run(worktree.path, ['diff', '--binary', 'HEAD']);
    final committedDiff = await _run(root, [
      'diff',
      '--binary',
      '${worktree.baseRevision}...${worktree.branch}',
    ]);
    final changed = await _run(worktree.path, [
      'status',
      '--porcelain',
      '--untracked-files=all',
    ]);
    final changedPaths = _changedPaths(changed.output);
    final combinedDiff = [
      if (committedDiff.output.trim().isNotEmpty) committedDiff.output.trim(),
      if (diff.output.trim().isNotEmpty) diff.output.trim(),
    ].join('\n\n');
    final hasUncommitted = taskStatus.output.trim().isNotEmpty;
    if (commitCount == 0 && !hasUncommitted) {
      return _blocked(worktree, 'This task worktree has no changes to apply.');
    }
    return GitWorktreeHandoffPreview(
      repositoryRoot: root,
      worktreePath: worktree.path,
      branch: worktree.branch,
      baseRevision: worktree.baseRevision,
      summary: hasUncommitted
          ? 'Review ${changedPaths.length} changed file${changedPaths.length == 1 ? '' : 's'} from ${worktree.branch}. Applying will create a task commit in the isolated worktree, then merge it into the clean local workspace.'
          : 'Review $commitCount task commit${commitCount == 1 ? '' : 's'} from ${worktree.branch} before merging into the clean local workspace.',
      diffPreview: combinedDiff,
      changedPaths: changedPaths,
      commitCount: commitCount,
    );
  }

  Future<GitWorktreeHandoffResult> applyHandoff(
    GitWorktreeHandoffPreview preview, {
    required bool confirmed,
  }) async {
    if (!confirmed) {
      return GitWorktreeHandoffResult(
        preview: preview,
        applied: false,
        evidence: 'Cancelled before either workspace changed.',
      );
    }
    if (!preview.canApply) {
      return GitWorktreeHandoffResult(
        preview: preview,
        applied: false,
        evidence: preview.blockedReason ?? 'This handoff is blocked.',
      );
    }
    final current = await previewHandoff(
      worktree: GitTaskWorktree(
        repositoryRoot: preview.repositoryRoot,
        path: preview.worktreePath,
        branch: preview.branch,
        baseRevision: preview.baseRevision,
      ),
    );
    if (!current.canApply) {
      return GitWorktreeHandoffResult(
        preview: current,
        applied: false,
        evidence:
            current.blockedReason ??
            'The handoff changed and must be reviewed again.',
      );
    }
    final taskStatus = await _run(current.worktreePath, [
      'status',
      '--porcelain',
    ]);
    if (taskStatus.output.trim().isNotEmpty) {
      final staged = await _run(current.worktreePath, ['add', '-A']);
      if (!staged.ok) {
        return GitWorktreeHandoffResult(
          preview: current,
          applied: false,
          evidence: _failure(
            'Could not stage the reviewed task changes',
            staged,
          ),
        );
      }
      final commit = await _run(current.worktreePath, [
        'commit',
        '-m',
        'Circuit task handoff: ${_safeSegment(p.basename(current.worktreePath))}',
      ]);
      if (!commit.ok) {
        return GitWorktreeHandoffResult(
          preview: current,
          applied: false,
          evidence: _failure(
            'Could not create the reviewed task handoff commit',
            commit,
          ),
        );
      }
    }
    final merged = await _run(current.repositoryRoot, [
      'merge',
      '--no-ff',
      '--no-edit',
      current.branch,
    ]);
    return GitWorktreeHandoffResult(
      preview: current,
      applied: merged.ok,
      evidence: merged.ok
          ? 'Merged isolated task branch ${current.branch} into the local workspace. The worktree remains available for audit and cleanup.'
          : _failure('Git did not merge the isolated task branch', merged),
    );
  }

  Future<String> _repositoryRoot() async {
    final result = await _run(repositoryRoot, ['rev-parse', '--show-toplevel']);
    if (!result.ok || result.output.trim().isEmpty) {
      throw StateError(
        _failure('A Git repository is required for worktree isolation', result),
      );
    }
    return p.normalize(result.output.trim());
  }

  Future<String> _required(String root, List<String> args) async {
    final result = await _run(root, args);
    if (!result.ok || result.output.trim().isEmpty) {
      throw StateError(
        _failure('Git could not complete ${args.first}', result),
      );
    }
    return result.output.trim();
  }

  Future<int> _integer(String root, List<String> args) async {
    final result = await _run(root, args);
    return result.ok ? int.tryParse(result.output.trim()) ?? 0 : 0;
  }

  Future<_GitResult> _run(String directory, List<String> args) async {
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: directory,
      ).timeout(const Duration(seconds: 30));
      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();
      return _GitResult(
        result.exitCode == 0,
        result.exitCode == 0 ? stdout : (stderr.isNotEmpty ? stderr : stdout),
      );
    } on TimeoutException {
      return const _GitResult(false, 'Git operation timed out.');
    } catch (error) {
      return _GitResult(false, error.toString());
    }
  }

  GitWorktreeHandoffPreview _blocked(GitTaskWorktree worktree, String reason) {
    return GitWorktreeHandoffPreview(
      repositoryRoot: worktree.repositoryRoot,
      worktreePath: worktree.path,
      branch: worktree.branch,
      baseRevision: worktree.baseRevision,
      summary: reason,
      canApply: false,
      blockedReason: reason,
    );
  }

  String _failure(String prefix, _GitResult result) {
    final detail = result.output.trim();
    return detail.isEmpty ? '$prefix.' : '$prefix: $detail';
  }

  String _safeSegment(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return normalized.isEmpty
        ? 'task'
        : normalized.substring(0, normalized.length.clamp(1, 48));
  }

  List<String> _changedPaths(String porcelain) {
    final paths = <String>{};
    for (final line in porcelain.split('\n')) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 2) continue;
      paths.add(fields.last);
    }
    return paths.toList()..sort();
  }
}

class _GitResult {
  final bool ok;
  final String output;

  const _GitResult(this.ok, this.output);
}
