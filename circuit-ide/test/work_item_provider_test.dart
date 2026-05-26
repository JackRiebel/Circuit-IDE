import 'dart:io';

import 'package:circuit_ide/models/work_item.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/project_profile_provider.dart';
import 'package:circuit_ide/state/work_item_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('WorkItemController starts guided work with project checks', () async {
    final root = await Directory.systemTemp.createTemp('work_item_flutter_');
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

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(fileTreeProvider.notifier).openDirectory(root.path);
    await container.read(projectProfileProvider.notifier).refresh();

    container.read(workItemProvider.notifier).start('Improve startup flow');
    final item = container.read(workItemProvider);

    expect(item, isNotNull);
    expect(item!.status, WorkItemStatus.ready);
    expect(item.steps.map((step) => step.title), contains('Understand scope'));
    expect(
      item.verificationCommands.map((command) => command.command),
      contains('flutter analyze'),
    );
  });

  test('WorkItemController serializes a handoff summary', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(workItemProvider.notifier).start('Audit the project');
    final summary = container.read(workItemProvider.notifier).handoffSummary();

    expect(summary, contains('CircuitCode work item handoff'));
    expect(summary, contains('Goal: Audit the project'));
    expect(summary, contains('Status: ready'));
  });
}

Future<void> _delete(Directory directory) async {
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
