import 'dart:io';

import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/suggested_learning.dart';
import 'package:circuit_ide/models/work_item.dart';
import 'package:circuit_ide/state/context_pack_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/project_profile_provider.dart';
import 'package:circuit_ide/state/suggested_learning_provider.dart';
import 'package:circuit_ide/state/work_item_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ContextPack serializes visible context only', () {
    final pack = ContextPack(
      id: 'ctx',
      projectKey: 'project',
      createdAt: DateTime(2026),
      removedItemIds: const ['terminal'],
      items: const [
        ContextPackItem(
          id: 'profile',
          type: ContextPackItemType.projectProfile,
          title: 'Project',
          detail: 'Flutter app',
          estimatedTokens: 10,
        ),
        ContextPackItem(
          id: 'terminal',
          type: ContextPackItemType.terminal,
          title: 'Terminal',
          detail: 'secret output',
          estimatedTokens: 20,
        ),
      ],
    );

    expect(pack.visibleItems.map((item) => item.id), ['profile']);
    expect(pack.estimatedTokens, 10);
    expect(pack.serializePrompt(), contains('Flutter app'));
    expect(pack.serializePrompt(), isNot(contains('secret output')));
  });

  test('ContextPackController builds project profile context', () async {
    final root = await _sampleFlutterProject();
    addTearDown(() => _delete(root));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    await container.read(projectProfileProvider.notifier).refresh();

    final pack = container
        .read(contextPackProvider.notifier)
        .buildForCodingTask(prompt: 'Improve startup');

    expect(pack.visibleItems.first.type, ContextPackItemType.projectProfile);
    expect(pack.serializePrompt(), contains('Improve startup'));
    expect(pack.estimatedTokens, greaterThan(0));
  });

  test(
    'PatchProposalController applies and restores reviewed patches',
    () async {
      final root = await Directory.systemTemp.createTemp('patch_v3_');
      addTearDown(() => _delete(root));
      final file = File(p.join(root.path, 'README.md'));
      await file.writeAsString('old\n');
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      final patchSet = container
          .read(patchProposalProvider.notifier)
          .propose(
            title: 'Update readme',
            edits: const [
              ProposedFileEdit(
                path: 'README.md',
                type: ProposedFileEditType.modify,
                before: 'old\n',
                after: 'new\n',
              ),
            ],
          );

      expect(container.read(patchProposalProvider).active?.id, patchSet.id);

      final result = await container
          .read(patchProposalProvider.notifier)
          .applyActive();

      expect(result.status, PatchApplyStatus.applied);
      expect(await file.readAsString(), 'new\n');
      expect(result.checkpointId, isNotNull);

      final restore = await container
          .read(patchProposalProvider.notifier)
          .restoreCheckpoint(result.checkpointId!);

      expect(restore.status, PatchApplyStatus.applied);
      expect(await file.readAsString(), 'old\n');
    },
  );

  test('WorkItemStore persists project-scoped history', () async {
    final root = await Directory.systemTemp.createTemp('work_store_v3_');
    final storeRoot = await Directory.systemTemp.createTemp('work_config_v3_');
    addTearDown(() => _delete(root));
    addTearDown(() => _delete(storeRoot));
    final store = WorkItemStore(baseDir: storeRoot.path);
    final item = WorkItem(
      id: 'work-1',
      prompt: 'Improve vibe coding',
      status: WorkItemStatus.ready,
      contextPreview: const ['Flutter app'],
      artifacts: [
        WorkItemArtifact(
          id: 'ctx',
          type: WorkItemArtifactType.context,
          title: 'Context pack',
          detail: '1 item',
          createdAt: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
    );

    await store.save(root.path, [item]);
    final loaded = await store.load(root.path);

    expect(loaded.single.prompt, 'Improve vibe coding');
    expect(loaded.single.contextPreview, ['Flutter app']);
    expect(loaded.single.artifacts.single.type, WorkItemArtifactType.context);
  });

  test('SuggestedLearningController reviews memories before saving', () async {
    final root = await _sampleFlutterProject();
    addTearDown(() => _delete(root));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    final suggestion = container
        .read(suggestedLearningProvider.notifier)
        .suggestMemory(name: 'review-first', content: 'Always review writes.');

    expect(suggestion.type, SuggestedLearningType.memory);
    expect(container.read(suggestedLearningProvider).pending, hasLength(1));

    container.read(suggestedLearningProvider.notifier).reject(suggestion.id);

    expect(container.read(suggestedLearningProvider).pending, isEmpty);
  });
}

Future<Directory> _sampleFlutterProject() async {
  final root = await Directory.systemTemp.createTemp('context_pack_v3_');
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: sample
dependencies:
  flutter:
    sdk: flutter
''');
  await Directory(p.join(root.path, 'lib')).create();
  await File(
    p.join(root.path, 'lib', 'main.dart'),
  ).writeAsString('void main() {}\n');
  return root;
}

Future<void> _delete(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
