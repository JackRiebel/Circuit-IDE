import 'dart:io';

import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/context_pack.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/context_pack_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/project_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Mascot aliases rotate deterministically and add suffixes', () {
    expect(AgentMascotNamePool.aliasForIndex(0), 'Benny');
    expect(AgentMascotNamePool.aliasForIndex(1), 'Clark');
    expect(AgentMascotNamePool.aliasForIndex(6), 'Skye');
    expect(AgentMascotNamePool.aliasForIndex(7), 'Benny 2');
  });

  test('Default agent tool policy is review-first for mutation', () {
    const policy = AgentToolPermissionPolicy();

    expect(
      policy.verdictFor(AgentToolPermissionTarget.readTool),
      AgentToolPermissionVerdict.allow,
    );
    expect(
      policy.verdictFor(AgentToolPermissionTarget.writeTool),
      AgentToolPermissionVerdict.review,
    );
    expect(
      policy.verdictFor(AgentToolPermissionTarget.command),
      AgentToolPermissionVerdict.review,
    );
    expect(
      policy.verdictFor(AgentToolPermissionTarget.externalNetwork),
      AgentToolPermissionVerdict.block,
    );
  });

  test('AgentWorkspaceStore persists project-scoped task history', () async {
    final root = await Directory.systemTemp.createTemp('agent_ws_project_');
    final storeRoot = await Directory.systemTemp.createTemp('agent_ws_config_');
    addTearDown(() => _delete(root));
    addTearDown(() => _delete(storeRoot));

    final store = AgentWorkspaceStore(baseDir: storeRoot.path);
    final task = AgentTask(
      id: 'task-1',
      mascotAlias: 'Benny',
      profile: AgentTaskProfile.investigate,
      status: AgentTaskStatus.waitingForApproval,
      goal: 'Investigate startup',
      artifacts: [
        AgentTaskArtifact(
          id: 'ctx',
          type: AgentTaskArtifactType.contextPack,
          title: 'Context pack',
          detail: '3 items',
          createdAt: DateTime(2026),
        ),
      ],
      createdAt: DateTime(2026),
    );

    await store.save(root.path, [task]);
    final loaded = await store.load(root.path);

    expect(loaded.single.mascotAlias, 'Benny');
    expect(loaded.single.profile, AgentTaskProfile.investigate);
    expect(
      loaded.single.artifacts.single.type,
      AgentTaskArtifactType.contextPack,
    );
  });

  test(
    'AgentWorkspaceStore marks interrupted active tasks failed on load',
    () async {
      final root = await Directory.systemTemp.createTemp('agent_ws_project_');
      final storeRoot = await Directory.systemTemp.createTemp(
        'agent_ws_config_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(storeRoot));

      final store = AgentWorkspaceStore(baseDir: storeRoot.path);
      final task = AgentTask(
        id: 'task-interrupted',
        mascotAlias: 'Benny',
        profile: AgentTaskProfile.investigate,
        status: AgentTaskStatus.running,
        goal: 'Investigate startup',
        activeRunId: 'run-interrupted',
        createdAt: DateTime(2026),
      );

      await store.save(root.path, [task]);

      final loaded = await store.load(root.path);

      expect(loaded.single.status, AgentTaskStatus.failed);
      expect(loaded.single.activeRunId, isNull);
      expect(loaded.single.completedAt, isNotNull);
      expect(
        loaded.single.error,
        contains('Interrupted while CircuitCode was closed'),
      );
    },
  );

  test(
    'AgentWorkspaceStore treats stale active tasks with results as completed',
    () async {
      final root = await Directory.systemTemp.createTemp('agent_ws_project_');
      final storeRoot = await Directory.systemTemp.createTemp(
        'agent_ws_config_',
      );
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(storeRoot));

      final store = AgentWorkspaceStore(baseDir: storeRoot.path);
      final completedAt = DateTime(2026, 1, 2);
      final task = AgentTask(
        id: 'task-stale-complete',
        mascotAlias: 'Benny',
        profile: AgentTaskProfile.patch,
        status: AgentTaskStatus.running,
        goal: 'Update readme',
        activeRunId: 'run-stale',
        result: 'Finished.',
        createdAt: DateTime(2026),
        completedAt: completedAt,
      );

      await store.save(root.path, [task]);

      final loaded = await store.load(root.path);

      expect(loaded.single.status, AgentTaskStatus.completed);
      expect(loaded.single.activeRunId, isNull);
      expect(loaded.single.completedAt, completedAt);
      expect(loaded.single.result, 'Finished.');
      expect(loaded.single.error, isNull);
    },
  );

  test(
    'ContextPackController discovers approved project instruction files',
    () async {
      final root = await _sampleProject();
      addTearDown(() => _delete(root));
      await File(
        p.join(root.path, 'AGENTS.md'),
      ).writeAsString('Use review first.');
      await Directory(p.join(root.path, '.github')).create();
      await File(
        p.join(root.path, '.github', 'copilot-instructions.md'),
      ).writeAsString('Prefer small patches.');
      await Directory(
        p.join(root.path, '.circuit', 'rules'),
      ).create(recursive: true);
      await File(
        p.join(root.path, '.circuit', 'rules', 'security.md'),
      ).writeAsString('Do not auto-run mutation commands.');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      await container.read(projectProfileProvider.notifier).refresh();

      final pack = container
          .read(contextPackProvider.notifier)
          .buildForCodingTask();

      expect(
        pack.instructionItems.map((item) => item.source),
        containsAll([
          'AGENTS.md',
          '.github/copilot-instructions.md',
          '.circuit/rules/security.md',
        ]),
      );
      expect(
        pack.visibleItems.any(
          (item) => item.type == ContextPackItemType.instruction,
        ),
        isTrue,
      );
    },
  );

  test('Patch proposals attach to supervised agent tasks', () async {
    final root = await _sampleProject();
    addTearDown(() => _delete(root));
    final file = File(p.join(root.path, 'README.md'));
    await file.writeAsString('old\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    await container.read(projectProfileProvider.notifier).refresh();
    await Future<void>.delayed(Duration.zero);

    final task = container
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: 'Update readme', profile: AgentTaskProfile.patch);
    final patch = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Update readme',
          agentTaskId: task.id,
          comparisonSummary: 'Small documentation update.',
          edits: const [
            ProposedFileEdit(
              path: 'README.md',
              type: ProposedFileEditType.modify,
              before: 'old\n',
              after: 'new\n',
            ),
          ],
        );

    final updatedTask = container.read(agentWorkspaceProvider).selectedTask;

    expect(patch.agentTaskId, task.id);
    expect(updatedTask?.mascotAlias, 'Benny');
    expect(updatedTask?.status, AgentTaskStatus.waitingForApproval);
    expect(updatedTask?.patchSetIds, contains(patch.id));
    expect(
      container.read(agentWorkspaceProvider.notifier).compareProposals(),
      contains('Small documentation update.'),
    );
  });
}

Future<Directory> _sampleProject() async {
  final root = await Directory.systemTemp.createTemp('agent_ws_v4_');
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
