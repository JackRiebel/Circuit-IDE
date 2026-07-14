import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/agent/mcp/mcp_config_storage.dart';
import 'package:circuit_ide/agent/memory/agent_config_storage.dart';
import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/models/agent_config_model.dart';
import 'package:circuit_ide/models/checkpoint.dart';
import 'package:circuit_ide/models/notebook.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/services/notebook_storage.dart';
import 'package:circuit_ide/services/versioned_json_document.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/settings_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/work_item_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'versioned documents reject unknown future schemas without mutation',
    () {
      expect(
        () => VersionedJsonDocument.decode(
          const {'schemaVersion': 99, 'kind': 'circuit.test', 'payload': {}},
          expectedKind: 'circuit.test',
          currentSchemaVersion: 2,
        ),
        throwsA(isA<UnsupportedRuntimeSchemaVersion>()),
      );
    },
  );

  test('versioned document checksums reject payload corruption', () {
    final document = const VersionedJsonDocument(
      kind: 'circuit.test',
      schemaVersion: 1,
      payload: {'value': 'original'},
    ).toJson();

    expect(
      VersionedJsonDocument.decode(
        document,
        expectedKind: 'circuit.test',
        currentSchemaVersion: 1,
      ).payload,
      const {'value': 'original'},
    );

    document['payload'] = const {'value': 'modified'};
    expect(
      () => VersionedJsonDocument.decode(
        document,
        expectedKind: 'circuit.test',
        currentSchemaVersion: 1,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'StudioThreadStore migrates legacy history with a recoverable backup',
    () async {
      final root = await Directory.systemTemp.createTemp('schema_threads_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final now = DateTime(2026, 7, 10);
      final legacyThreads = [
        StudioThread(
          id: 'legacy-thread',
          title: 'Legacy thread',
          createdAt: now,
          updatedAt: now,
        ).toJson(),
      ];
      final original = const JsonEncoder.withIndent(
        '  ',
      ).convert(legacyThreads);
      final history = File(store.historyPath(project.path));
      await history.parent.create(recursive: true);
      await history.writeAsString(original);

      final loaded = await store.load(project.path);

      expect(loaded.single.id, 'legacy-thread');
      expect(
        await File('${history.path}.schema-v1.backup').readAsString(),
        original,
      );
      final migrated =
          jsonDecode(await history.readAsString()) as Map<String, dynamic>;
      expect(migrated['schemaVersion'], 3);
      expect(migrated['kind'], 'circuit.studio-thread-history');
      expect((migrated['payload'] as List<dynamic>).single, isA<Map>());
    },
  );

  test(
    'StudioThreadStore preserves an unsupported future history verbatim',
    () async {
      final root = await Directory.systemTemp.createTemp('schema_future_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final history = File(store.historyPath(project.path));
      await history.parent.create(recursive: true);
      const future =
          '{"schemaVersion":99,"kind":"circuit.studio-thread-history","payload":[]}';
      await history.writeAsString(future);

      await expectLater(
        store.load(project.path),
        throwsA(isA<UnsupportedRuntimeSchemaVersion>()),
      );
      expect(await history.readAsString(), future);
    },
  );

  test(
    'StudioThreadStore repairs corrupt snapshots from checksummed journal and backup',
    () async {
      final root = await Directory.systemTemp.createTemp('thread_recovery_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final first = StudioThread(
        id: 'recoverable-thread',
        title: 'Keep this task',
        createdAt: DateTime(2026, 7, 11),
        updatedAt: DateTime(2026, 7, 11),
      );
      await store.save(project.path, [first]);
      await store.save(project.path, [
        first.copyWith(updatedAt: DateTime(2026, 7, 11, 0, 1)),
      ]);

      final journal = File(store.journalPath(project.path));
      final journalRecord =
          jsonDecode((await journal.readAsLines()).first)
              as Map<String, dynamic>;
      expect(journalRecord['envelopeKind'], isNotNull);
      expect(journalRecord['checksum'], isA<String>());
      expect(
        await File(store.recoveryBackupPath(project.path)).exists(),
        isTrue,
      );

      await File(store.historyPath(project.path)).writeAsString('{truncated');
      final recoveredFromJournal = await store.load(project.path);
      expect(recoveredFromJournal.single.title, 'Keep this task');
      expect(store.lastRecoveryMessage, contains('crash journal'));

      await File(store.historyPath(project.path)).writeAsString('{corrupt');
      await journal.writeAsString('{partial journal record');
      final recoveredFromBackup = await store.load(project.path);
      expect(recoveredFromBackup.single.id, 'recoverable-thread');
      expect(store.lastRecoveryMessage, contains('known-good backup'));

      final export = File('${root.path}/recovery-export.json');
      await store.exportRecoveryBundle(project.path, export.path);
      final exported =
          jsonDecode(await export.readAsString()) as Map<String, dynamic>;
      final files = exported['files'] as Map<String, dynamic>;
      expect(
        files.keys.any((name) => name.endsWith('.recovery.backup')),
        isTrue,
      );
    },
  );

  test('StudioThreadStore compacts an oversized append-only journal', () async {
    final root = await Directory.systemTemp.createTemp('thread_compaction_');
    addTearDown(() => root.delete(recursive: true));
    final project = await Directory('${root.path}/project').create();
    final store = StudioThreadStore(baseDir: '${root.path}/history');
    final createdAt = DateTime(2026, 7, 11);

    for (var index = 0; index < 602; index++) {
      await store.save(project.path, [
        StudioThread(
          id: 'thread',
          title: 'Compaction',
          createdAt: createdAt,
          updatedAt: createdAt.add(Duration(seconds: index)),
        ),
      ]);
    }

    final journalLines = await File(
      store.journalPath(project.path),
    ).readAsLines();
    expect(journalLines.length, lessThan(10));
    expect(await File(store.journalBackupPath(project.path)).exists(), isTrue);
    expect((await store.load(project.path)).single.title, 'Compaction');
  });

  test(
    'PatchProposalStore migrates legacy state and preserves future state',
    () async {
      final root = await Directory.systemTemp.createTemp('schema_patches_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = PatchProposalStore(baseDir: '${root.path}/patches');
      final history = File(store.historyPath(project.path));
      await history.parent.create(recursive: true);
      const legacy =
          '{"active":null,"history":[],"checkpoints":{},"message":"legacy"}';
      await history.writeAsString(legacy);

      final migrated = await store.load(project.path);

      expect(migrated.message, 'legacy');
      expect(
        await File('${history.path}.schema-v1.backup').readAsString(),
        legacy,
      );
      final current =
          jsonDecode(await history.readAsString()) as Map<String, dynamic>;
      expect(current['schemaVersion'], 2);
      expect(current['kind'], 'circuit.patch-proposals');

      const future =
          '{"schemaVersion":99,"kind":"circuit.patch-proposals","payload":{}}';
      await history.writeAsString(future);
      await expectLater(
        store.load(project.path),
        throwsA(isA<UnsupportedRuntimeSchemaVersion>()),
      );
      expect(await history.readAsString(), future);
    },
  );

  test(
    'patch apply journals migrate before recovery and protect future schemas',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'schema_patch_journal_',
      );
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final target = File('${project.path}/lib/example.dart');
      await target.parent.create(recursive: true);
      await target.writeAsString('mutated');
      final store = PatchProposalStore(baseDir: '${root.path}/patches');
      final journal = PatchApplyJournal(
        transactionId: 'legacy-transaction',
        workspaceRoot: project.path,
        patchSetId: 'patch',
        checkpointId: 'checkpoint',
        preparedAt: DateTime(2026, 7, 10),
        snapshots: const [
          FileSnapshot(path: 'lib/example.dart', originalContent: 'original'),
        ],
      );
      final file = File(store.applyJournalPath(project.path));
      await file.parent.create(recursive: true);
      final legacy = jsonEncode(journal.toJson());
      await file.writeAsString(legacy);

      final recovered = await store.recoverPendingApply(project.path);

      expect(recovered?.patchSetId, 'patch');
      expect(await target.readAsString(), 'original');
      expect(
        await File('${file.path}.schema-v1.backup').readAsString(),
        legacy,
      );
      expect(await file.exists(), isFalse);

      const future =
          '{"schemaVersion":99,"kind":"circuit.patch-apply-journal","payload":{}}';
      await file.writeAsString(future);
      await expectLater(
        store.recoverPendingApply(project.path),
        throwsA(isA<UnsupportedRuntimeSchemaVersion>()),
      );
      expect(await file.readAsString(), future);
    },
  );

  test(
    'project work and agent-workspace histories migrate independently',
    () async {
      final root = await Directory.systemTemp.createTemp('schema_workspace_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final workItems = WorkItemStore(baseDir: '${root.path}/work-items');
      final agentWorkspace = AgentWorkspaceStore(
        baseDir: '${root.path}/agent-workspace',
      );
      final entries = [
        (
          file: File(workItems.historyPath(project.path)),
          kind: 'circuit.work-item-history',
          schemaVersion: 2,
          load: () => workItems.load(project.path),
        ),
        (
          file: File(agentWorkspace.historyPath(project.path)),
          kind: 'circuit.agent-workspace',
          schemaVersion: 4,
          load: () => agentWorkspace.load(project.path),
        ),
      ];

      for (final entry in entries) {
        await entry.file.parent.create(recursive: true);
        await entry.file.writeAsString('[]');
        expect(await entry.load(), isEmpty);
        expect(
          await File('${entry.file.path}.schema-v1.backup').readAsString(),
          '[]',
        );
        final migrated =
            jsonDecode(await entry.file.readAsString()) as Map<String, dynamic>;
        expect(migrated['schemaVersion'], entry.schemaVersion);
        expect(migrated['kind'], entry.kind);
      }
    },
  );

  test(
    'agent definitions migrate independently and protect future records',
    () async {
      final root = await Directory.systemTemp.createTemp('schema_agents_');
      addTearDown(() => root.delete(recursive: true));
      final storage = AgentConfigStorage(agentsDir: root.path);
      final config = AgentConfigModel(
        id: 'legacy-agent',
        name: 'Legacy agent',
        createdAt: DateTime(2026, 7, 10),
      );
      final file = File('${root.path}/legacy-agent.json');
      final legacy = jsonEncode(config.toJson());
      await file.writeAsString(legacy);

      final loaded = await storage.loadAll();

      expect(loaded.single.id, 'legacy-agent');
      expect(
        await File('${file.path}.schema-v1.backup').readAsString(),
        legacy,
      );
      final migrated =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(migrated['schemaVersion'], 4);
      expect(migrated['kind'], 'circuit.agent-definition');
      expect((migrated['payload'] as Map<String, dynamic>)['enabled'], isFalse);

      const future =
          '{"schemaVersion":99,"kind":"circuit.agent-definition","payload":{}}';
      await file.writeAsString(future);
      await expectLater(
        storage.loadAll(),
        throwsA(isA<UnsupportedRuntimeSchemaVersion>()),
      );
      expect(await file.readAsString(), future);
    },
  );

  test(
    'notebook artifacts migrate and preserve future-version files',
    () async {
      final root = await Directory.systemTemp.createTemp('schema_notebook_');
      addTearDown(() => root.delete(recursive: true));
      final storage = NotebookStorage();
      final notebook = Notebook(
        id: 'legacy-notebook',
        name: 'Legacy notebook',
        cells: [NotebookCell(id: 'cell')],
        createdAt: DateTime(2026, 7, 10),
        modifiedAt: DateTime(2026, 7, 10),
      );
      final file = File('${root.path}/.circuit/notebooks/${notebook.id}.json');
      await file.parent.create(recursive: true);
      final legacy = jsonEncode(notebook.toJson());
      await file.writeAsString(legacy);

      final loaded = await storage.loadAll(root.path);

      expect(loaded.single.id, notebook.id);
      expect(
        await File('${file.path}.schema-v1.backup').readAsString(),
        legacy,
      );
      final migrated =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(migrated['kind'], 'circuit.notebook');

      const future =
          '{"schemaVersion":99,"kind":"circuit.notebook","payload":{}}';
      await file.writeAsString(future);
      await expectLater(
        storage.loadAll(root.path),
        throwsA(isA<UnsupportedRuntimeSchemaVersion>()),
      );
      expect(await file.readAsString(), future);
    },
  );

  test(
    'settings migrate with backup and never overwrite a future schema',
    () async {
      final root = await Directory.systemTemp.createTemp('schema_settings_');
      addTearDown(() => root.delete(recursive: true));
      final previousOverride = SettingsNotifier.debugSettingsFileOverride;
      final file = File('${root.path}/ui_settings.json');
      SettingsNotifier.debugSettingsFileOverride = file.path;
      addTearDown(() {
        SettingsNotifier.debugSettingsFileOverride = previousOverride;
      });
      const legacy =
          '{"cisco_model":"gpt-5-nano","theme":"light","recent_projects":["/tmp/project"]}';
      await file.writeAsString(legacy);
      final legacyContainer = ProviderContainer();
      legacyContainer.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(legacyContainer.read(settingsProvider).themeName, 'light');
      expect(
        legacyContainer.read(settingsProvider).diagnosticRetentionDays,
        14,
      );
      expect(legacyContainer.read(settingsProvider).sendOnEnter, isTrue);
      expect(
        await File('${file.path}.schema-v1.backup').readAsString(),
        legacy,
      );
      final migrated =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(migrated['kind'], 'circuit.ui-settings');
      expect(migrated['schemaVersion'], 5);
      expect(
        (migrated['payload']
            as Map<String, dynamic>)['diagnostic_retention_days'],
        14,
      );
      expect(
        (migrated['payload']
            as Map<String, dynamic>)['crash_reporting_enabled'],
        isFalse,
      );

      legacyContainer.read(settingsProvider.notifier).setSendOnEnter(false);
      legacyContainer
          .read(settingsProvider.notifier)
          .setCrashReportingEnabled(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final savedSettings =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(
        (savedSettings['payload'] as Map<String, dynamic>)['send_on_enter'],
        isFalse,
      );
      expect(
        (savedSettings['payload']
            as Map<String, dynamic>)['crash_reporting_enabled'],
        isTrue,
      );

      legacyContainer
          .read(settingsProvider.notifier)
          .setConnectorHealth(
            ConnectorHealth(
              status: ConnectorHealthStatus.degraded,
              message: 'Circuit service is temporarily unavailable.',
              checkedAt: DateTime(2026, 7, 11),
              endpoint: 'https://circuit.example.test',
              protocolVersion: 1,
              latency: const Duration(milliseconds: 37),
              errorCategory: ConnectorHealthErrorCategory.server,
              retryAdvice: 'Retry later.',
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      legacyContainer.dispose();
      final reloadedContainer = ProviderContainer();
      reloadedContainer.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final reloadedSettings = reloadedContainer.read(settingsProvider);
      expect(
        reloadedSettings.connectorHealthEndpoint,
        'https://circuit.example.test',
      );
      expect(reloadedSettings.connectorHealthProtocolVersion, 1);
      expect(reloadedSettings.connectorHealthLatencyMs, 37);
      expect(
        reloadedSettings.connectorHealthErrorCategory,
        ConnectorHealthErrorCategory.server,
      );
      expect(reloadedSettings.connectorHealthRetryAdvice, 'Retry later.');
      expect(reloadedSettings.crashReportingEnabled, isTrue);
      reloadedContainer.dispose();

      const future =
          '{"schemaVersion":99,"kind":"circuit.ui-settings","payload":{}}';
      await file.writeAsString(future);
      final futureContainer = ProviderContainer();
      addTearDown(futureContainer.dispose);
      futureContainer.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        futureContainer.read(settingsProvider).connectorHealthMessage,
        contains('uses schema 99'),
      );

      futureContainer.read(settingsProvider.notifier).setTheme('light');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await file.readAsString(), future);
    },
  );

  test(
    'MCP configurations migrate with backup and preserve future schemas',
    () async {
      final root = await Directory.systemTemp.createTemp('schema_mcp_');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/mcp_servers.json');
      const legacy =
          '{"servers":[{"name":"local","url":"http://127.0.0.1:3000"}]}';
      await file.writeAsString(legacy);
      final storage = McpConfigStorage(filePath: file.path);

      final loaded = await storage.load();

      expect(loaded.single.name, 'local');
      expect(
        await File('${file.path}.schema-v1.backup').readAsString(),
        legacy,
      );
      final migrated =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(migrated['kind'], 'circuit.mcp-server-configurations');

      const future =
          '{"schemaVersion":99,"kind":"circuit.mcp-server-configurations","payload":{"servers":[]}}';
      await file.writeAsString(future);
      await expectLater(
        storage.load(),
        throwsA(isA<UnsupportedRuntimeSchemaVersion>()),
      );
      expect(await file.readAsString(), future);
    },
  );
}
