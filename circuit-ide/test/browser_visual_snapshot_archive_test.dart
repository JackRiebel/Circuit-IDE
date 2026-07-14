import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:circuit_ide/models/studio_browser.dart';
import 'package:circuit_ide/services/browser_visual_snapshot_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late BrowserVisualSnapshotArchive archive;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('circuit-browser-snapshot-');
    archive = BrowserVisualSnapshotArchive(rootResolver: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('writes a bounded PNG atomically with local provenance', () async {
    final record = await archive.save(
      taskId: 'task/private-customer-review',
      url:
          'https://portal.example.test/records/7?access_token=private-token#view',
      capturedAt: DateTime.utc(2026, 7, 13, 12),
      pngBytes: _pngBytes,
    );

    expect(await File(record.filePath).readAsBytes(), _pngBytes);
    expect(record.filePath, contains('browser-'));
    expect(record.filePath, isNot(contains('private-customer-review')));
    expect(record.sha256, hasLength(64));
    expect(record.byteSize, _pngBytes.lengthInBytes);
    expect(record.url, 'https://portal.example.test/records/7');
    expect(record.url, isNot(contains('private-token')));
  });

  test(
    'rejects malformed or over-limit images before they reach disk',
    () async {
      await expectLater(
        archive.save(
          taskId: 'task-1',
          url: 'https://example.test',
          capturedAt: DateTime.utc(2026, 7, 13),
          pngBytes: Uint8List.fromList(const [1, 2, 3]),
        ),
        throwsArgumentError,
      );
      await expectLater(
        archive.save(
          taskId: 'task-1',
          url: 'https://example.test',
          capturedAt: DateTime.utc(2026, 7, 13),
          pngBytes: Uint8List(BrowserPageSnapshot.maxVisualSnapshotBytes + 1),
        ),
        throwsArgumentError,
      );
      expect(
        await Directory(root.path).list(recursive: true).toList(),
        isEmpty,
      );
    },
  );

  test('deletes only regular files contained by its private archive', () async {
    final record = await archive.save(
      taskId: 'task-1',
      url: 'https://example.test',
      capturedAt: DateTime.utc(2026, 7, 13),
      pngBytes: _pngBytes,
    );
    final outside = File('${root.path}/outside.png')
      ..writeAsBytesSync(_pngBytes);

    expect(await archive.delete(outside.path), isFalse);
    expect(await outside.exists(), isTrue);
    expect(await archive.delete(record.filePath), isTrue);
    expect(await File(record.filePath).exists(), isFalse);
    expect(await archive.delete(record.filePath), isTrue);
  });

  test(
    'refuses a symlinked archive directory before writing outside storage',
    () async {
      final outside = await Directory.systemTemp.createTemp(
        'circuit-browser-snapshot-outside-',
      );
      addTearDown(() async {
        if (await outside.exists()) await outside.delete(recursive: true);
      });
      final link = Link('${root.path}/browser-visual-snapshots');
      await link.create(outside.path);

      await expectLater(
        archive.save(
          taskId: 'task-symlinked-archive',
          url: 'https://example.test',
          capturedAt: DateTime.utc(2026, 7, 13),
          pngBytes: _pngBytes,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await outside.list().toList(), isEmpty);
    },
  );

  test('refuses a symlinked or tampered existing snapshot target', () async {
    final capturedAt = DateTime.utc(2026, 7, 13, 12);
    final record = await archive.save(
      taskId: 'task-existing-target',
      url: 'https://example.test',
      capturedAt: capturedAt,
      pngBytes: _pngBytes,
    );
    final outside = await File(
      '${root.path}/outside-snapshot.png',
    ).writeAsBytes(_pngBytes);
    await File(record.filePath).delete();
    await Link(record.filePath).create(outside.path);

    await expectLater(
      archive.save(
        taskId: 'task-existing-target',
        url: 'https://example.test',
        capturedAt: capturedAt,
        pngBytes: _pngBytes,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await outside.readAsBytes(), _pngBytes);

    await Link(record.filePath).delete();
    await File(record.filePath).writeAsBytes(const [1, 2, 3]);
    await expectLater(
      archive.save(
        taskId: 'task-existing-target',
        url: 'https://example.test',
        capturedAt: capturedAt,
        pngBytes: _pngBytes,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'rejects credential-bearing browser URLs before persisting a snapshot',
    () async {
      await expectLater(
        archive.save(
          taskId: 'task-1',
          url: 'https://user:private-password@example.test/records',
          capturedAt: DateTime.utc(2026, 7, 13),
          pngBytes: _pngBytes,
        ),
        throwsArgumentError,
      );
    },
  );
}

final _pngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9J5l8AAAAASUVORK5CYII=',
  ),
);
