import 'dart:io';

import 'package:circuit_ide/models/project_profile.dart';
import 'package:circuit_ide/services/project_detector.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/project_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ProjectProfileController detects Flutter projects', () async {
    final root = await Directory.systemTemp.createTemp('profile_flutter_');
    addTearDown(() => _delete(root));

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
    await Directory(p.join(root.path, 'test')).create();
    await File(
      p.join(root.path, 'test', 'app_test.dart'),
    ).writeAsString('void main() {}\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    await container.read(projectProfileProvider.notifier).refresh();

    final profile = container.read(projectProfileProvider);
    expect(profile.primaryType, ProjectType.flutter);
    expect(profile.entrypoints, contains('lib/main.dart'));
    expect(
      profile.commands.map((command) => command.command),
      contains('flutter analyze'),
    );
    expect(
      profile.recommendations.map((item) => item.kind),
      contains(ProjectRecommendationKind.runChecks),
    );
  });

  test(
    'ProjectProfileController extracts Node and TypeScript scripts',
    () async {
      final root = await Directory.systemTemp.createTemp('profile_node_');
      addTearDown(() => _delete(root));

      await File(p.join(root.path, 'package.json')).writeAsString('''
{
  "scripts": {
    "test": "vitest",
    "build": "tsc -p tsconfig.json"
  }
}
''');
      await File(p.join(root.path, 'tsconfig.json')).writeAsString('{}');
      await Directory(p.join(root.path, 'src')).create();
      await File(
        p.join(root.path, 'src', 'index.ts'),
      ).writeAsString('export const ok = true;\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      await container.read(projectProfileProvider.notifier).refresh();

      final profile = container.read(projectProfileProvider);
      expect(profile.projectTypes, contains(ProjectType.node));
      expect(profile.projectTypes, contains(ProjectType.typescript));
      expect(profile.entrypoints, contains('src/index.ts'));
      expect(
        profile.commands.map((command) => command.command),
        contains('npm test'),
      );
      expect(
        profile.commands.map((command) => command.command),
        contains('npm run build'),
      );
    },
  );

  test(
    'ProjectProfileController detects Python checks and unknown projects',
    () async {
      final python = await Directory.systemTemp.createTemp('profile_python_');
      final unknown = await Directory.systemTemp.createTemp('profile_unknown_');
      addTearDown(() => _delete(python));
      addTearDown(() => _delete(unknown));

      await File(
        p.join(python.path, 'pyproject.toml'),
      ).writeAsString('[tool.ruff]\n');
      await Directory(p.join(python.path, 'tests')).create();
      await File(p.join(python.path, 'app.py')).writeAsString('print("ok")\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(fileTreeProvider.notifier)
          .openDirectory(python.path);
      await container.read(projectProfileProvider.notifier).refresh();
      var profile = container.read(projectProfileProvider);

      expect(profile.primaryType, ProjectType.python);
      expect(profile.entrypoints, contains('app.py'));
      expect(
        profile.commands.map((command) => command.command),
        contains('python -m pytest'),
      );

      await container
          .read(fileTreeProvider.notifier)
          .openDirectory(unknown.path);
      await container.read(projectProfileProvider.notifier).refresh();
      profile = container.read(projectProfileProvider);

      expect(profile.primaryType, ProjectType.unknown);
      expect(profile.commands, isEmpty);
      expect(
        profile.recommendations.map((item) => item.kind),
        contains(ProjectRecommendationKind.explainProject),
      );
    },
  );

  test(
    'ProjectProfileController detects Rust and mixed-project checks',
    () async {
      final rust = await Directory.systemTemp.createTemp('profile_rust_');
      final mixed = await Directory.systemTemp.createTemp('profile_mixed_');
      addTearDown(() => _delete(rust));
      addTearDown(() => _delete(mixed));
      await File(
        p.join(rust.path, 'Cargo.toml'),
      ).writeAsString('[package]\nname = "sample"\nversion = "0.1.0"\n');
      await File(p.join(mixed.path, 'pubspec.yaml')).writeAsString(
        'name: mixed\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      await File(
        p.join(mixed.path, 'package.json'),
      ).writeAsString('{"scripts":{"test":"vitest","lint":"eslint ."}}');
      await File(
        p.join(mixed.path, 'pyproject.toml'),
      ).writeAsString('[project]\nname="mixed"\n');
      await Directory(p.join(mixed.path, 'tests')).create();
      await File(
        p.join(mixed.path, 'tests', 'test_sample.py'),
      ).writeAsString('def test_sample():\n    assert True\n');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(rust.path);
      await container.read(projectProfileProvider.notifier).refresh();
      var profile = container.read(projectProfileProvider);
      expect(profile.primaryType, ProjectType.rust);
      expect(
        profile.commands.map((command) => command.command),
        contains('cargo test'),
      );

      await container.read(fileTreeProvider.notifier).openDirectory(mixed.path);
      await container.read(projectProfileProvider.notifier).refresh();
      profile = container.read(projectProfileProvider);
      expect(
        profile.projectTypes,
        containsAll([
          ProjectType.flutter,
          ProjectType.node,
          ProjectType.python,
        ]),
      );
      expect(
        profile.commands.map((command) => command.command),
        containsAll(['flutter analyze', 'npm test', 'python -m pytest']),
      );
    },
  );

  test(
    'ProjectProfileController requires an explicit check approval',
    () async {
      final root = await Directory.systemTemp.createTemp('profile_check_');
      addTearDown(() => _delete(root));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      await container.read(projectProfileProvider.notifier).refresh();
      const check = ProjectCommand(
        id: 'safe-print',
        name: 'Safe print',
        command: 'printf "%s" "profile-ok"',
        source: 'test',
      );

      final blocked = await container
          .read(projectProfileProvider.notifier)
          .runCommand(check);
      expect(blocked.passed, isFalse);
      expect(blocked.exitCode, -1);
      expect(blocked.output, contains('requires review'));

      final allowed = await container
          .read(projectProfileProvider.notifier)
          .runCommand(check, userApproved: true);
      expect(allowed.passed, isTrue);
      expect(allowed.output, 'profile-ok');
    },
  );
}

Future<void> _delete(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
