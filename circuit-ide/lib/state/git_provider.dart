import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/git_models.dart';
import '../services/git_review_service.dart';
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

  GitReviewService? get _reviewService {
    final root = _workingDir;
    return root == null || root.trim().isEmpty
        ? null
        : GitReviewService(workingDirectory: root);
  }

  Future<(bool, String)> _runGit(List<String> args) async {
    if (_workingDir == null) return (false, 'No working directory');
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: _workingDir,
      );
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
    final (statusOk, statusOutput) = await _runGit([
      'status',
      '--porcelain',
      '-b',
    ]);
    if (!statusOk) {
      state = state.copyWith(isLoading: false, error: statusOutput);
      return;
    }

    final lines = statusOutput.split('\n');
    String branch = '';
    String? upstream;
    var ahead = 0;
    var behind = 0;
    final staged = <GitFileChange>[];
    final unstaged = <GitFileChange>[];
    final untracked = <GitFileChange>[];

    for (final line in lines) {
      if (line.startsWith('##')) {
        final header = line.substring(3).trim();
        final trackingStart = header.indexOf('...');
        branch = trackingStart < 0
            ? header
            : header.substring(0, trackingStart);
        if (trackingStart >= 0) {
          final tracked = header.substring(trackingStart + 3);
          final stateStart = tracked.indexOf(' [');
          upstream =
              (stateStart < 0 ? tracked : tracked.substring(0, stateStart))
                  .trim();
          final counts = RegExp(r'\[([^\]]+)\]').firstMatch(tracked)?.group(1);
          if (counts != null) {
            for (final value in counts.split(',')) {
              final part = value.trim();
              final count = RegExp(
                r'^(ahead|behind)\s+(\d+)$',
              ).firstMatch(part);
              if (count == null) continue;
              final amount = int.tryParse(count.group(2)!) ?? 0;
              if (count.group(1) == 'ahead') ahead = amount;
              if (count.group(1) == 'behind') behind = amount;
            }
          }
        }
        continue;
      }
      if (line.length < 4) continue;

      final indexStatus = line[0];
      final workTreeStatus = line[1];
      final path = line.substring(3).trim();

      if (indexStatus == '?' && workTreeStatus == '?') {
        untracked.add(GitFileChange(path: path, type: GitChangeType.untracked));
      } else {
        if (indexStatus != ' ' && indexStatus != '?') {
          staged.add(
            GitFileChange(
              path: path,
              type: GitChangeType.fromCode(indexStatus),
            ),
          );
        }
        if (workTreeStatus != ' ' && workTreeStatus != '?') {
          unstaged.add(
            GitFileChange(
              path: path,
              type: GitChangeType.fromCode(workTreeStatus),
            ),
          );
        }
      }
    }

    // Get recent commits
    final (logOk, logOutput) = await _runGit([
      'log',
      '--oneline',
      '--format=%H|%h|%s|%an|%aI',
      '-20',
    ]);
    final commits = <GitCommit>[];
    if (logOk && logOutput.isNotEmpty) {
      for (final line in logOutput.split('\n')) {
        final parts = line.split('|');
        if (parts.length >= 5) {
          commits.add(
            GitCommit(
              hash: parts[0],
              shortHash: parts[1],
              message: parts[2],
              author: parts[3],
              date: DateTime.tryParse(parts[4]) ?? DateTime.now(),
            ),
          );
        }
      }
    }

    state = state.copyWith(
      status: GitStatus(
        branch: branch,
        upstream: upstream?.isEmpty == true ? null : upstream,
        ahead: ahead,
        behind: behind,
        staged: staged,
        unstaged: unstaged,
        untracked: untracked,
      ),
      recentCommits: commits,
      isLoading: false,
      error: null,
    );
  }

  Future<GitMutationPreview> previewStage(String path) =>
      _withReview((service) => service.previewStage(path));

  Future<GitMutationPreview> previewUnstage(String path) =>
      _withReview((service) => service.previewUnstage(path));

  Future<GitMutationPreview> previewDiscardFile(String path) =>
      _withReview((service) => service.previewDiscardFile(path));

  Future<List<GitDiffHunk>> unstagedHunks(String path) async {
    final service = _reviewService;
    return service == null ? const [] : service.unstagedHunks(path);
  }

  Future<GitMutationPreview> previewDiscardHunk(GitDiffHunk hunk) =>
      _withReview((service) => service.previewDiscardHunk(hunk));

  Future<GitMutationPreview> previewCommit(String message) =>
      _withReview((service) => service.previewCommit(message));

  Future<GitMutationPreview> previewCreateBranch(String branchName) =>
      _withReview((service) => service.previewCreateBranch(branchName));

  Future<GitMutationPreview> previewPush() =>
      _withReview((service) => service.previewPush());

  Future<GitMutationResult> applyPreview(
    GitMutationPreview preview, {
    required bool confirmed,
  }) async {
    final service = _reviewService;
    if (service == null) {
      return GitMutationResult(
        preview: preview,
        applied: false,
        evidence: 'Open a Git workspace before applying this operation.',
        undoGuidance: preview.undoGuidance,
      );
    }
    final result = await service.apply(preview, confirmed: confirmed);
    if (result.applied) await refresh();
    return result;
  }

  Future<GitMutationPreview> _withReview(
    Future<GitMutationPreview> Function(GitReviewService service) action,
  ) async {
    final service = _reviewService;
    if (service == null) {
      return const GitMutationPreview(
        type: GitMutationType.stage,
        title: 'Git workspace unavailable',
        summary: 'Open a Git workspace before reviewing changes.',
        undoGuidance: 'No files were changed.',
        canApply: false,
        blockedReason: 'No working directory is open.',
      );
    }
    return action(service);
  }

  Future<String> getDiff({String? path, bool staged = false}) async {
    final args = ['diff'];
    if (staged) args.add('--cached');
    if (path != null) args.add(path);
    final (ok, output) = await _runGit(args);
    return ok ? (output.isEmpty ? 'No changes' : output) : 'Error: $output';
  }
}

final gitProvider = NotifierProvider<GitNotifier, GitState>(GitNotifier.new);
