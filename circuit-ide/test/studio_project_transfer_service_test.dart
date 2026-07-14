import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/services/studio_project_transfer_service.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'project transfer round-trips history with redaction and reference warnings',
    () async {
      final root = await Directory.systemTemp.createTemp('project_transfer_');
      final destination = await Directory.systemTemp.createTemp(
        'project_import_',
      );
      final storage = await Directory.systemTemp.createTemp('project_storage_');
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(destination));
      addTearDown(() => _delete(storage));

      final taskStore = AgentWorkspaceStore(
        baseDir: p.join(storage.path, 'tasks'),
      );
      final threadStore = StudioThreadStore(
        baseDir: p.join(storage.path, 'threads'),
      );
      final service = StudioProjectTransferService(
        taskStore: taskStore,
        threadStore: threadStore,
      );
      await taskStore.save(root.path, [
        AgentTask(
          id: 'task-1',
          mascotAlias: 'Benny',
          profile: AgentTaskProfile.patch,
          goal: 'Implement portable export. API key: super-secret-token-value',
          workspaceRoot: root.path,
          createdAt: DateTime.utc(2026),
        ),
      ]);
      await threadStore.save(root.path, [
        StudioThread(
          id: 'thread-1',
          taskId: 'task-1',
          title: 'Portable history',
          sourceArtifacts: [
            StudioSourceArtifact(
              id: 'artifact-1',
              kind: StudioSourceArtifactKind.toolResult,
              title: 'Raw output',
              subtitle: 'tool',
              value: 'raw forbidden artifact payload',
              filePath: 'missing/source.dart',
              createdAt: DateTime.utc(2026),
            ),
          ],
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ]);

      final packageFile = File(p.join(storage.path, 'portable-project.json'));
      final exported = await service.exportProject(root.path, packageFile.path);
      final raw = await packageFile.readAsString();
      expect(exported.taskCount, 1);
      expect(exported.threadCount, 1);
      expect(raw, isNot(contains('super-secret-token-value')));
      expect(raw, isNot(contains('raw forbidden artifact payload')));
      expect(raw, contains('[REDACTED]'));
      expect(raw, contains('[Exported metadata only]'));
      expect(
        (jsonDecode(raw) as Map<String, dynamic>)['kind'],
        StudioProjectTransferService.packageKind,
      );

      final imported = await service.importProject(
        destination.path,
        packageFile.path,
      );
      expect(imported.taskCount, 1);
      expect(imported.threadCount, 1);
      expect(imported.missingReferences, ['missing/source.dart']);
      final tasks = await taskStore.load(destination.path);
      final threads = await threadStore.load(destination.path);
      expect(tasks.single.goal, contains('Implement portable export'));
      expect(tasks.single.goal, contains('[REDACTED]'));
      expect(threads.single.title, 'Portable history');
      expect(
        threads.single.sourceArtifacts.single.value,
        '[Exported metadata only]',
      );
    },
  );

  test(
    'project transfer refuses accidental overwrite into non-empty project',
    () async {
      final root = await Directory.systemTemp.createTemp('project_transfer_');
      final destination = await Directory.systemTemp.createTemp(
        'project_import_',
      );
      final storage = await Directory.systemTemp.createTemp('project_storage_');
      addTearDown(() => _delete(root));
      addTearDown(() => _delete(destination));
      addTearDown(() => _delete(storage));
      final taskStore = AgentWorkspaceStore(
        baseDir: p.join(storage.path, 'tasks'),
      );
      final threadStore = StudioThreadStore(
        baseDir: p.join(storage.path, 'threads'),
      );
      final service = StudioProjectTransferService(
        taskStore: taskStore,
        threadStore: threadStore,
      );
      await taskStore.save(root.path, [
        AgentTask(
          id: 'task-source',
          mascotAlias: 'Benny',
          profile: AgentTaskProfile.plan,
          goal: 'Source',
          createdAt: DateTime.utc(2026),
        ),
      ]);
      await taskStore.save(destination.path, [
        AgentTask(
          id: 'task-destination',
          mascotAlias: 'Clark',
          profile: AgentTaskProfile.plan,
          goal: 'Destination',
          createdAt: DateTime.utc(2026),
        ),
      ]);
      final packageFile = File(p.join(storage.path, 'portable-project.json'));
      await service.exportProject(root.path, packageFile.path);

      await expectLater(
        service.importProject(destination.path, packageFile.path),
        throwsA(isA<StateError>()),
      );
    },
  );
}

Future<void> _delete(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } catch (_) {}
}
