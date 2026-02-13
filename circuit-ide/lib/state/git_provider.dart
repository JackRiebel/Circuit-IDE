import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/git_models.dart';
import '../state/file_tree_provider.dart';

class GitState {
  final GitStatus status;
  final List<GitCommit> recentCommits;
  final bool isLoading;
  final String? error;

  const GitState({
    this.status = const GitStatus(),
    this.recentCommits = const [],
    this.isLoading = false,
    this.error,
  });

  GitState copyWith({
    GitStatus? status,
    List<GitCommit>? recentCommits,
    bool? isLoading,
    String? error,
  }) {
    return GitState(
      status: status ?? this.status,
      recentCommits: recentCommits ?? this.recentCommits,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class GitNotifier extends Notifier<GitState> {
  @override
  GitState build() => const GitState();

  String? get _workingDir => ref.read(fileTreeProvider).rootPath;

  Future<(bool, String)> _runGit(List<String> args) async {
    if (_workingDir == null) return (false, 'No working directory');
    try {
      final result = await Process.run('git', args,
          workingDirectory: _workingDir);
      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();
      if (result.exitCode != 0) {
        return (false, stderr.isNotEmpty ? stderr : stdout);
      }
      return (true, stdout);
    } catch (e) {
      return (false, e.toString());
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);

    // Get status
    final (statusOk, statusOutput) =
        await _runGit(['status', '--porcelain', '-b']);
    if (!statusOk) {
      state = state.copyWith(isLoading: false, error: statusOutput);
      return;
    }

    final lines = statusOutput.split('\n');
    String branch = '';
    final staged = <GitFileChange>[];
    final unstaged = <GitFileChange>[];
    final untracked = <GitFileChange>[];

    for (final line in lines) {
      if (line.startsWith('##')) {
        branch = line.substring(3).split('...').first;
        continue;
      }
      if (line.length < 4) continue;

      final indexStatus = line[0];
      final workTreeStatus = line[1];
      final path = line.substring(3).trim();

      if (indexStatus == '?' && workTreeStatus == '?') {
        untracked.add(GitFileChange(
          path: path,
          type: GitChangeType.untracked,
        ));
      } else {
        if (indexStatus != ' ' && indexStatus != '?') {
          staged.add(GitFileChange(
            path: path,
            type: GitChangeType.fromCode(indexStatus),
          ));
        }
        if (workTreeStatus != ' ' && workTreeStatus != '?') {
          unstaged.add(GitFileChange(
            path: path,
            type: GitChangeType.fromCode(workTreeStatus),
          ));
        }
      }
    }

    // Get recent commits
    final (logOk, logOutput) = await _runGit(
        ['log', '--oneline', '--format=%H|%h|%s|%an|%aI', '-20']);
    final commits = <GitCommit>[];
    if (logOk && logOutput.isNotEmpty) {
      for (final line in logOutput.split('\n')) {
        final parts = line.split('|');
        if (parts.length >= 5) {
          commits.add(GitCommit(
            hash: parts[0],
            shortHash: parts[1],
            message: parts[2],
            author: parts[3],
            date: DateTime.tryParse(parts[4]) ?? DateTime.now(),
          ));
        }
      }
    }

    state = state.copyWith(
      status: GitStatus(
        branch: branch,
        staged: staged,
        unstaged: unstaged,
        untracked: untracked,
      ),
      recentCommits: commits,
      isLoading: false,
      error: null,
    );
  }

  Future<String> stageFile(String path) async {
    final (ok, output) = await _runGit(['add', path]);
    if (ok) await refresh();
    return ok ? 'Staged: $path' : 'Error: $output';
  }

  Future<String> unstageFile(String path) async {
    final (ok, output) = await _runGit(['reset', 'HEAD', path]);
    if (ok) await refresh();
    return ok ? 'Unstaged: $path' : 'Error: $output';
  }

  Future<String> commit(String message) async {
    final (ok, output) = await _runGit(['commit', '-m', message]);
    if (ok) await refresh();
    return ok ? 'Committed: $output' : 'Error: $output';
  }

  Future<String> getDiff({String? path, bool staged = false}) async {
    final args = ['diff'];
    if (staged) args.add('--cached');
    if (path != null) args.add(path);
    final (ok, output) = await _runGit(args);
    return ok ? (output.isEmpty ? 'No changes' : output) : 'Error: $output';
  }
}

final gitProvider =
    NotifierProvider<GitNotifier, GitState>(GitNotifier.new);
