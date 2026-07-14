import 'dart:async';
import 'dart:io';

import '../models/git_models.dart';

/// Typed Git review boundary used by the product UI.
///
/// Every mutation begins as a preview. [apply] rejects an unconfirmed or
/// blocked preview and invokes Git with argument arrays only; no operation is
/// built as a shell command. The service deliberately refuses force pushes
/// and untracked-file deletion.
class GitReviewService {
  final String workingDirectory;

  const GitReviewService({required this.workingDirectory});

  Future<GitMutationPreview> previewStage(String path) async {
    final diff = await _diff(path: path);
    return _preview(
      type: GitMutationType.stage,
      title: 'Stage $path',
      summary: 'Add this file to the next commit.',
      paths: [path],
      diff: diff,
      undo: 'Use Unstage before committing to remove it from the index.',
    );
  }

  Future<GitMutationPreview> previewUnstage(String path) async {
    final diff = await _diff(path: path, staged: true);
    return _preview(
      type: GitMutationType.unstage,
      title: 'Unstage $path',
      summary:
          'Remove this file from the index while keeping its working-copy changes.',
      paths: [path],
      diff: diff,
      undo: 'Use Stage to add the same file back to the index.',
    );
  }

  Future<GitMutationPreview> previewDiscardFile(String path) async {
    final diff = await _diff(path: path);
    if (diff.trim().isEmpty) {
      return _blocked(
        GitMutationType.discardFile,
        'Discard $path',
        'No tracked unstaged diff is available to discard.',
        paths: [path],
        undo: 'No files were changed.',
      );
    }
    return _preview(
      type: GitMutationType.discardFile,
      title: 'Discard uncommitted changes in $path',
      summary:
          'Restore this tracked file from HEAD. This removes the shown working-copy changes.',
      paths: [path],
      diff: diff,
      undo:
          'After discard, recover only from a checkpoint, commit, or another backup.',
    );
  }

  Future<List<GitDiffHunk>> unstagedHunks(String path) async {
    final diff = await _diff(path: path);
    return _parseHunks(path, diff);
  }

  Future<GitMutationPreview> previewDiscardHunk(GitDiffHunk hunk) async {
    if (hunk.patch.trim().isEmpty) {
      return _blocked(
        GitMutationType.discardHunk,
        'Discard selected hunk',
        'The selected diff hunk is empty.',
        paths: [hunk.path],
        undo: 'No files were changed.',
        hunk: hunk,
      );
    }
    return _preview(
      type: GitMutationType.discardHunk,
      title: 'Discard selected hunk in ${hunk.path}',
      summary:
          'Reverse only the selected working-copy hunk if the file still matches this preview.',
      paths: [hunk.path],
      diff: hunk.patch,
      undo:
          'After discard, recover this hunk only from a checkpoint, commit, or another backup.',
      hunk: hunk,
    );
  }

  Future<GitMutationPreview> previewCommit(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || trimmed.length > 200) {
      return _blocked(
        GitMutationType.commit,
        'Commit staged changes',
        'Enter a commit message between 1 and 200 characters.',
        undo: 'No commit was created.',
        commitMessage: trimmed,
      );
    }
    final diff = await _diff(staged: true);
    if (diff.trim().isEmpty) {
      return _blocked(
        GitMutationType.commit,
        'Commit staged changes',
        'There are no staged changes to commit.',
        undo: 'No commit was created.',
        commitMessage: trimmed,
      );
    }
    return _preview(
      type: GitMutationType.commit,
      title: 'Commit staged changes',
      summary: 'Create one local commit: $trimmed',
      diff: diff,
      undo: 'Use Reset --soft HEAD~1 if the commit has not been pushed.',
      commitMessage: trimmed,
    );
  }

  Future<GitMutationPreview> previewCreateBranch(String branchName) async {
    final trimmed = branchName.trim();
    final validation = await _run(['check-ref-format', '--branch', trimmed]);
    if (!validation.ok) {
      return _blocked(
        GitMutationType.createBranch,
        'Create branch',
        'Choose a valid, unused branch name.',
        undo: 'No branch was created.',
        branchName: trimmed,
      );
    }
    final existing = await _run([
      'show-ref',
      '--verify',
      '--quiet',
      'refs/heads/$trimmed',
    ]);
    if (existing.ok) {
      return _blocked(
        GitMutationType.createBranch,
        'Create branch',
        'The branch "$trimmed" already exists.',
        undo: 'No branch was created.',
        branchName: trimmed,
      );
    }
    return _preview(
      type: GitMutationType.createBranch,
      title: 'Create and switch to $trimmed',
      summary:
          'Create a new local branch at the current commit and switch the workspace to it.',
      undo:
          'Switch back to the prior branch; delete $trimmed only after confirming it is no longer needed.',
      branchName: trimmed,
    );
  }

  Future<GitMutationPreview> previewPush() async {
    final upstream = await _run([
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{upstream}',
    ]);
    if (!upstream.ok || upstream.output.trim().isEmpty) {
      return _blocked(
        GitMutationType.push,
        'Push current branch',
        'The current branch has no configured upstream. Create or select a branch with an upstream first.',
        undo:
            'A push cannot be automatically undone; no remote changes were made.',
      );
    }
    final counts = await _run([
      'rev-list',
      '--left-right',
      '--count',
      '@{upstream}...HEAD',
    ]);
    final parts = counts.output.split(RegExp(r'\s+'));
    final behind = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final ahead = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    if (behind > 0) {
      return _blocked(
        GitMutationType.push,
        'Push current branch',
        'The upstream has $behind commit${behind == 1 ? '' : 's'} not in this workspace. Pull/rebase and review before pushing.',
        undo: 'No remote changes were made.',
      );
    }
    if (ahead == 0) {
      return _blocked(
        GitMutationType.push,
        'Push current branch',
        'There are no local commits waiting to push.',
        undo: 'No remote changes were made.',
      );
    }
    return _preview(
      type: GitMutationType.push,
      title: 'Push current branch',
      summary:
          'Push $ahead local commit${ahead == 1 ? '' : 's'} to ${upstream.output.trim()}. Force push is never available here.',
      undo:
          'A push changes the shared remote. Revert with a new reviewed commit if necessary.',
    );
  }

  Future<GitMutationResult> apply(
    GitMutationPreview preview, {
    required bool confirmed,
  }) async {
    if (!confirmed) {
      return GitMutationResult(
        preview: preview,
        applied: false,
        evidence: 'Cancelled before Git changed anything.',
        undoGuidance: preview.undoGuidance,
      );
    }
    if (!preview.canApply) {
      return GitMutationResult(
        preview: preview,
        applied: false,
        evidence: preview.blockedReason ?? 'This Git operation is blocked.',
        undoGuidance: preview.undoGuidance,
      );
    }
    final result = await switch (preview.type) {
      GitMutationType.stage => _run(['add', '--', ...preview.affectedPaths]),
      GitMutationType.unstage => _run([
        'restore',
        '--staged',
        '--',
        ...preview.affectedPaths,
      ]),
      GitMutationType.discardFile => _run([
        'restore',
        '--source=HEAD',
        '--worktree',
        '--',
        ...preview.affectedPaths,
      ]),
      GitMutationType.discardHunk => _applyReverseHunk(preview.hunk!),
      GitMutationType.commit => _run(['commit', '-m', preview.commitMessage!]),
      GitMutationType.createBranch => _run([
        'switch',
        '-c',
        preview.branchName!,
      ]),
      GitMutationType.push => _run(['push']),
    };
    return GitMutationResult(
      preview: preview,
      applied: result.ok,
      evidence: result.ok
          ? _successEvidence(preview, result.output)
          : result.output.isEmpty
          ? 'Git did not complete ${preview.title.toLowerCase()}.'
          : result.output,
      undoGuidance: preview.undoGuidance,
    );
  }

  Future<String> _diff({String? path, bool staged = false}) async {
    final args = ['diff', if (staged) '--cached'];
    if (path != null) args.addAll(['--', path]);
    final result = await _run(args);
    return result.ok ? result.output : '';
  }

  Future<_GitCommandResult> _applyReverseHunk(GitDiffHunk hunk) async {
    try {
      final process = await Process.start('git', [
        'apply',
        '--reverse',
        '--whitespace=nowarn',
        '-',
      ], workingDirectory: workingDirectory);
      process.stdin.write(hunk.patch);
      await process.stdin.close();
      final output = await Future.wait([
        process.stdout.transform(const SystemEncoding().decoder).join(),
        process.stderr.transform(const SystemEncoding().decoder).join(),
      ]);
      final code = await process.exitCode;
      final stdout = output[0].trim();
      final stderr = output[1].trim();
      return _GitCommandResult(code == 0, stderr.isNotEmpty ? stderr : stdout);
    } catch (error) {
      return _GitCommandResult(false, error.toString());
    }
  }

  Future<_GitCommandResult> _run(List<String> args) async {
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: workingDirectory,
      ).timeout(const Duration(seconds: 30));
      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();
      return _GitCommandResult(
        result.exitCode == 0,
        result.exitCode == 0
            ? stdout
            : stderr.isNotEmpty
            ? stderr
            : stdout,
      );
    } on TimeoutException {
      return const _GitCommandResult(false, 'Git operation timed out.');
    } catch (error) {
      return _GitCommandResult(false, error.toString());
    }
  }

  GitMutationPreview _preview({
    required GitMutationType type,
    required String title,
    required String summary,
    List<String> paths = const [],
    String diff = '',
    required String undo,
    String? commitMessage,
    String? branchName,
    GitDiffHunk? hunk,
  }) => GitMutationPreview(
    type: type,
    title: title,
    summary: summary,
    affectedPaths: paths,
    diffPreview: diff,
    undoGuidance: undo,
    commitMessage: commitMessage,
    branchName: branchName,
    hunk: hunk,
  );

  GitMutationPreview _blocked(
    GitMutationType type,
    String title,
    String reason, {
    List<String> paths = const [],
    required String undo,
    String? commitMessage,
    String? branchName,
    GitDiffHunk? hunk,
  }) => GitMutationPreview(
    type: type,
    title: title,
    summary: reason,
    affectedPaths: paths,
    undoGuidance: undo,
    canApply: false,
    blockedReason: reason,
    commitMessage: commitMessage,
    branchName: branchName,
    hunk: hunk,
  );

  String _successEvidence(GitMutationPreview preview, String output) {
    final suffix = output.trim().isEmpty ? '' : ': ${output.trim()}';
    return switch (preview.type) {
      GitMutationType.stage =>
        'Staged ${preview.affectedPaths.join(', ')}$suffix',
      GitMutationType.unstage =>
        'Unstaged ${preview.affectedPaths.join(', ')}$suffix',
      GitMutationType.discardFile =>
        'Discarded working-copy changes in ${preview.affectedPaths.join(', ')}$suffix',
      GitMutationType.discardHunk =>
        'Discarded the selected hunk in ${preview.affectedPaths.join(', ')}$suffix',
      GitMutationType.commit => 'Created local commit$suffix',
      GitMutationType.createBranch =>
        'Created and switched to ${preview.branchName}$suffix',
      GitMutationType.push => 'Pushed the current branch$suffix',
    };
  }
}

class _GitCommandResult {
  final bool ok;
  final String output;

  const _GitCommandResult(this.ok, this.output);
}

List<GitDiffHunk> _parseHunks(String path, String diff) {
  final lines = diff.split('\n');
  final firstHunk = lines.indexWhere((line) => line.startsWith('@@'));
  if (firstHunk < 0) return const [];
  final preamble = lines.take(firstHunk).join('\n');
  final hunks = <GitDiffHunk>[];
  for (var index = firstHunk; index < lines.length;) {
    if (!lines[index].startsWith('@@')) {
      index++;
      continue;
    }
    final start = index;
    final header = lines[index];
    index++;
    while (index < lines.length && !lines[index].startsWith('@@')) {
      index++;
    }
    hunks.add(
      GitDiffHunk(
        path: path,
        header: header,
        patch: '$preamble\n${lines.sublist(start, index).join('\n')}\n',
      ),
    );
  }
  return hunks;
}
