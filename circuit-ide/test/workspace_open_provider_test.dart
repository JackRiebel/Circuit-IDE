import 'dart:io';

import 'package:circuit_ide/core/utils/platform_utils.dart';
import 'package:circuit_ide/models/workspace_open_result.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory configRoot;

  setUp(() async {
    configRoot = await Directory.systemTemp.createTemp('circuit_config_');
    PlatformUtils.configDirOverride = configRoot.path;
  });

  tearDown(() async {
    PlatformUtils.configDirOverride = null;
    await _delete(configRoot);
  });

  test(
    'openDirectory does not mutate rootPath for a missing project',
    () async {
      final root = await Directory.systemTemp.createTemp('workspace_open_');
      final existing = Directory(p.join(root.path, 'existing'));
      await existing.create();
      final missing = p.join(root.path, 'missing');
      addTearDown(() => _delete(root));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = await container
          .read(fileTreeProvider.notifier)
          .openDirectory(existing.path);
      final second = await container
          .read(fileTreeProvider.notifier)
          .openDirectory(missing);

      expect(first.success, isTrue);
      expect(second.success, isFalse);
      expect(second.failureReason, WorkspaceOpenFailureReason.missing);
      expect(container.read(fileTreeProvider).rootPath, existing.path);
      expect(
        container.read(fileTreeProvider).error,
        'Project no longer exists.',
      );
    },
  );

  test('openDirectory rejects a file path', () async {
    final root = await Directory.systemTemp.createTemp('workspace_open_');
    final file = File(p.join(root.path, 'not_a_folder.txt'));
    await file.writeAsString('hello');
    addTearDown(() => _delete(root));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final result = await container
        .read(fileTreeProvider.notifier)
        .openDirectory(file.path);

    expect(result.success, isFalse);
    expect(result.failureReason, WorkspaceOpenFailureReason.notDirectory);
    expect(container.read(fileTreeProvider).rootPath, isNull);
  });

  test('SettingsNotifier removes and prunes stale recent projects', () async {
    final root = await Directory.systemTemp.createTemp('workspace_recent_');
    final existing = Directory(p.join(root.path, 'existing'));
    await existing.create();
    final missing = p.join(root.path, 'missing');
    addTearDown(() => _delete(root));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);

    settings.addRecentProject(existing.path);
    settings.addRecentProject(missing);
    settings.removeRecentProject(missing);

    expect(container.read(settingsProvider).recentProjects, [existing.path]);

    settings.addRecentProject(missing);
    await settings.pruneRecentProjects();

    expect(container.read(settingsProvider).recentProjects, [existing.path]);
  });

  test(
    'SettingsNotifier keeps all recent projects instead of capping at ten',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final settings = container.read(settingsProvider.notifier);

      final paths = [
        for (var index = 0; index < 12; index++) '/tmp/circuit-project-$index',
      ];
      for (final path in paths) {
        settings.addRecentProject(path);
      }

      final recent = container.read(settingsProvider).recentProjects;

      expect(recent, hasLength(12));
      expect(recent.first, paths.last);
      expect(recent.last, paths.first);
    },
  );
}

Future<void> _delete(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
