import 'dart:io';

import 'package:circuit_ide/services/lsdf_index_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'refreshForPath updates changed directory and ancestor indexes',
    () async {
      final root = await Directory.systemTemp.createTemp('lsdf_service_test_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final file = File(p.join(root.path, 'lib', 'feature', 'thing.dart'));
      await file.parent.create(recursive: true);
      await file.writeAsString('class Thing {}\nString label() => "ok";\n');

      final service = LsdfIndexService(rootPath: root.path);
      await service.refreshForPath('lib/feature/thing.dart');

      final rootIndex = await File(
        p.join(root.path, 'INDEX.lsdf'),
      ).readAsString();
      final libIndex = await File(
        p.join(root.path, 'lib', 'INDEX.lsdf'),
      ).readAsString();
      final featureIndex = await File(
        p.join(root.path, 'lib', 'feature', 'INDEX.lsdf'),
      ).readAsString();

      expect(rootIndex, contains('@INDEX:lib'));
      expect(libIndex, contains('@INDEX:feature'));
      expect(featureIndex, contains('@thing.dart'));
      expect(featureIndex, contains(' @Thing'));
    },
  );

  test('readIndex falls back to the nearest ancestor index', () async {
    final root = await Directory.systemTemp.createTemp('lsdf_service_test_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    await File(p.join(root.path, 'INDEX.lsdf')).writeAsString('@root.dart\n');

    final service = LsdfIndexService(rootPath: root.path);
    final result = await service.readIndex(directory: 'missing/deep/file.dart');

    expect(result, contains('INDEX.lsdf'));
    expect(result, contains('@root.dart'));
  });
}
