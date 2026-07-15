import 'dart:io';

import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'skipping a stale file preserves and applies non-overlapping edits',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'patch_skip_conflict_',
      );
      addTearDown(() => root.delete(recursive: true));
      await File(p.join(root.path, 'safe.txt')).writeAsString('safe old\n');
      await File(
        p.join(root.path, 'stale.txt'),
      ).writeAsString('current drift\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      final controller = container.read(patchProposalProvider.notifier);
      final patch = controller.propose(
        title: 'Mixed patch',
        edits: const [
          ProposedFileEdit(
            path: 'safe.txt',
            type: ProposedFileEditType.modify,
            before: 'safe old\n',
            after: 'safe new\n',
          ),
          ProposedFileEdit(
            path: 'stale.txt',
            type: ProposedFileEditType.modify,
            before: 'stale old\n',
            after: 'stale new\n',
          ),
        ],
      );

      final conflict = await controller.apply(patch.id);
      expect(conflict.status, PatchApplyStatus.conflict);
      expect(conflict.conflictMessage, contains('stale.txt'));
      expect(controller.skipConflictedFile(patch.id, 'stale.txt'), isTrue);

      final remaining = container.read(patchProposalProvider).active!;
      expect(remaining.edits.map((edit) => edit.path), ['safe.txt']);
      expect(remaining.applyStatus, isNull);
      final applied = await controller.apply(remaining.id);
      expect(applied.status, PatchApplyStatus.applied);
      expect(
        await File(p.join(root.path, 'safe.txt')).readAsString(),
        'safe new\n',
      );
      expect(
        await File(p.join(root.path, 'stale.txt')).readAsString(),
        'current drift\n',
      );
      expect(
        controller.skipConflictedFile(patch.id, 'stale.txt'),
        isFalse,
        reason: 'A second skip cannot create a duplicate recovery transition.',
      );
    },
  );
}
