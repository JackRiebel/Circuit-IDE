import 'dart:io';

import 'package:circuit_ide/state/ai_context_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ensureLsdfIndex is a no-op while L-SDF is disabled', () async {
    final root = await Directory.systemTemp.createTemp('ai_context_lsdf_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    await File(
      p.join(root.path, 'main.dart'),
    ).writeAsString('class AppShell {}\nString greet() => "hello";\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiContextProvider.notifier).ensureLsdfIndex(root.path);
    final state = container.read(aiContextProvider);

    expect(state.includeLsdfIndex, isFalse);
    expect(state.lsdfStatus, LsdfIndexStatus.idle);
    expect(state.lsdfMessage, contains('temporarily disabled'));
    expect(state.lsdfFilesIndexed, 0);
    expect(await File(p.join(root.path, 'project.lsdf')).exists(), isFalse);
    expect(await File(p.join(root.path, 'INDEX.lsdf')).exists(), isFalse);
  });

  test('rebuildLsdfIndex stays disabled and does not write indexes', () async {
    final root = await Directory.systemTemp.createTemp('ai_context_lsdf_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final file = File(p.join(root.path, 'main.dart'));
    await file.writeAsString('class Before {}\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiContextProvider.notifier).ensureLsdfIndex(root.path);
    await file.writeAsString('class After {}\n');
    await container
        .read(aiContextProvider.notifier)
        .rebuildLsdfIndex(root.path);

    expect(container.read(aiContextProvider).lsdfStatus, LsdfIndexStatus.idle);
    expect(container.read(aiContextProvider).lsdfFilesIndexed, 0);
    expect(await File(p.join(root.path, 'INDEX.lsdf')).exists(), isFalse);
  });
}
