import 'dart:io';

import 'package:circuit_ide/state/ai_context_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'ensureLsdfIndex builds missing L-SDF files for an opened project',
    () async {
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

      await container
          .read(aiContextProvider.notifier)
          .ensureLsdfIndex(root.path);
      final state = container.read(aiContextProvider);

      expect(state.lsdfStatus, LsdfIndexStatus.ready);
      expect(state.lsdfMessage, contains('L-SDF map ready'));
      expect(state.lsdfFilesIndexed, 1);
      expect(await File(p.join(root.path, 'project.lsdf')).exists(), isTrue);
      expect(await File(p.join(root.path, 'INDEX.lsdf')).exists(), isTrue);
      expect(
        await File(p.join(root.path, 'INDEX.detail.lsdf')).exists(),
        isTrue,
      );
    },
  );

  test(
    'rebuildLsdfIndex refreshes existing index files without chat',
    () async {
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

      await container
          .read(aiContextProvider.notifier)
          .ensureLsdfIndex(root.path);
      await file.writeAsString('class After {}\n');
      await container
          .read(aiContextProvider.notifier)
          .rebuildLsdfIndex(root.path);

      final index = await File(p.join(root.path, 'INDEX.lsdf')).readAsString();
      expect(index, contains('@After'));
      expect(index, isNot(contains('@Before')));
      expect(
        container.read(aiContextProvider).lsdfStatus,
        LsdfIndexStatus.ready,
      );
      expect(container.read(aiContextProvider).lsdfFilesIndexed, 1);
    },
  );
}
