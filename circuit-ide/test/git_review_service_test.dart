import 'dart:io';

import 'package:circuit_ide/models/git_models.dart';
import 'package:circuit_ide/services/git_review_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Git review service previews, confirms, and evidences local mutations',
    () async {
      final root = await Directory.systemTemp.createTemp('git_review_service_');
      addTearDown(() => root.delete(recursive: true));
      await _git(root.path, ['init']);
      await _git(root.path, ['config', 'user.email', 'circuit@example.test']);
      await _git(root.path, ['config', 'user.name', 'Circuit Test']);
      final file = File('${root.path}/notes.txt');
      await file.writeAsString(_baseContents());
      await _git(root.path, ['add', '--', 'notes.txt']);
      await _git(root.path, ['commit', '-m', 'Initial notes']);

      await file.writeAsString(_editedContents());
      final review = GitReviewService(workingDirectory: root.path);

      final stagePreview = await review.previewStage('notes.txt');
      expect(stagePreview.type, GitMutationType.stage);
      expect(stagePreview.requiresConfirmation, isTrue);
      expect(stagePreview.diffPreview, contains('-line 02'));
      final cancelled = await review.apply(stagePreview, confirmed: false);
      expect(cancelled.applied, isFalse);
      expect(await _gitOutput(root.path, ['diff', '--cached']), isEmpty);

      final staged = await review.apply(stagePreview, confirmed: true);
      expect(staged.applied, isTrue);
      expect(staged.evidence, contains('Staged notes.txt'));
      expect(
        await _gitOutput(root.path, ['diff', '--cached']),
        contains('+line two changed'),
      );

      final unstage = await review.previewUnstage('notes.txt');
      expect((await review.apply(unstage, confirmed: true)).applied, isTrue);
      expect(await _gitOutput(root.path, ['diff', '--cached']), isEmpty);

      final hunks = await review.unstagedHunks('notes.txt');
      expect(hunks, hasLength(2));
      final discardHunk = await review.previewDiscardHunk(hunks.first);
      expect(discardHunk.title, contains('Discard selected hunk'));
      final discarded = await review.apply(discardHunk, confirmed: true);
      expect(discarded.applied, isTrue, reason: discarded.evidence);
      final remaining = await file.readAsString();
      expect(remaining, contains('line 02'));
      expect(remaining, contains('line twenty changed'));

      final restage = await review.previewStage('notes.txt');
      expect((await review.apply(restage, confirmed: true)).applied, isTrue);
      final commit = await review.previewCommit('Keep second hunk');
      expect(commit.canApply, isTrue);
      final committed = await review.apply(commit, confirmed: true);
      expect(committed.applied, isTrue, reason: committed.evidence);
      expect(
        await _gitOutput(root.path, ['log', '-1', '--format=%s']),
        'Keep second hunk',
      );

      final branch = await review.previewCreateBranch('review/safe-git');
      expect(branch.canApply, isTrue);
      expect((await review.apply(branch, confirmed: true)).applied, isTrue);
      expect(
        await _gitOutput(root.path, ['branch', '--show-current']),
        'review/safe-git',
      );

      final push = await review.previewPush();
      expect(push.canApply, isFalse);
      expect(push.blockedReason, contains('upstream'));
      expect((await review.apply(push, confirmed: true)).applied, isFalse);

      final remote = await Directory('${root.path}/remote.git').create();
      await _git(remote.path, ['init', '--bare']);
      await _git(root.path, ['remote', 'add', 'origin', remote.path]);
      await _git(root.path, [
        'push',
        '--set-upstream',
        'origin',
        'review/safe-git',
      ]);
      await file.writeAsString(
        '${await file.readAsString()}local push change\n',
      );
      expect(
        (await review.apply(
          await review.previewStage('notes.txt'),
          confirmed: true,
        )).applied,
        isTrue,
      );
      expect(
        (await review.apply(
          await review.previewCommit('Prepare reviewed push'),
          confirmed: true,
        )).applied,
        isTrue,
      );
      final safePush = await review.previewPush();
      expect(safePush.canApply, isTrue);
      final pushed = await review.apply(safePush, confirmed: true);
      expect(pushed.applied, isTrue, reason: pushed.evidence);
      expect(
        await _gitOutput(remote.path, [
          'log',
          '-1',
          '--format=%s',
          'review/safe-git',
        ]),
        'Prepare reviewed push',
      );
    },
  );

  test(
    'discard file refuses untracked content and reports safe undo guidance',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'git_review_untracked_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _git(root.path, ['init']);
      final untracked = File('${root.path}/customer-notes.txt');
      await untracked.writeAsString('Do not delete this implicitly.');
      final review = GitReviewService(workingDirectory: root.path);

      final preview = await review.previewDiscardFile('customer-notes.txt');
      expect(preview.canApply, isFalse);
      expect(preview.undoGuidance, 'No files were changed.');
      expect((await review.apply(preview, confirmed: true)).applied, isFalse);
      expect(await untracked.exists(), isTrue);
    },
  );
}

Future<void> _git(String workingDirectory, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw StateError('${result.stderr}\n${result.stdout}');
  }
}

Future<String> _gitOutput(String workingDirectory, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw StateError('${result.stderr}\n${result.stdout}');
  }
  return (result.stdout as String).trim();
}

String _baseContents() =>
    '${List.generate(24, (index) => 'line ${(index + 1).toString().padLeft(2, '0')}').join('\n')}\n';

String _editedContents() => _baseContents()
    .replaceFirst('line 02', 'line two changed')
    .replaceFirst('line 20', 'line twenty changed');
