import 'dart:convert';
import 'dart:typed_data';

import 'package:circuit_ide/models/studio_browser.dart';
import 'package:circuit_ide/services/browser_visual_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final validPng = Uint8List.fromList(base64Decode(_validPngBase64));

  test('returns a bounded PNG snapshot from the local native bridge', () async {
    String? requestedUrl;
    final source = Uint8List.fromList(validPng);
    final service = BrowserVisualSnapshotService(
      supported: true,
      invoke: (url) async {
        requestedUrl = url;
        return source;
      },
    );

    final snapshot = await service.capture('https://example.test/report');

    expect(requestedUrl, 'https://example.test/report');
    expect(snapshot, isNotNull);
    expect(snapshot, isNot(same(source)));
    expect(snapshot, orderedEquals(source));
  });

  test(
    'refuses unsupported, malformed, and oversized visual captures',
    () async {
      var invoked = false;
      final unsupported = BrowserVisualSnapshotService(
        supported: false,
        invoke: (_) async {
          invoked = true;
          return Uint8List.fromList(validPng);
        },
      );
      final malformed = BrowserVisualSnapshotService(
        supported: true,
        invoke: (_) async =>
            Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]),
      );
      final oversized = BrowserVisualSnapshotService(
        supported: true,
        invoke: (_) async =>
            Uint8List(BrowserPageSnapshot.maxVisualSnapshotBytes + 1),
      );

      expect(await unsupported.capture('https://example.test'), isNull);
      expect(invoked, isFalse);
      expect(await malformed.capture('https://example.test'), isNull);
      expect(await oversized.capture('https://example.test'), isNull);
    },
  );
}

const _validPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9J5l8AAAAASUVORK5CYII=';
