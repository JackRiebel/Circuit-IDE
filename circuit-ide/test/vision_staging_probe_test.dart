import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:circuit_ide/services/vision_staging_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a decodable red-left blue-right PNG fixture', () async {
    final fixture = VisionStagingProbeFixture.create();
    expect(fixture.pngBytes.length, greaterThan(128));
    expect(fixture.sha256, hasLength(64));
    final codec = await ui.instantiateImageCodec(fixture.pngBytes);
    final frame = await codec.getNextFrame();
    try {
      expect(frame.image.width, VisionStagingProbeFixture.width);
      expect(frame.image.height, VisionStagingProbeFixture.height);
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final pixels = data!.buffer.asUint8List();
      _expectPixel(pixels, 10, 10, 0xe5, 0x39, 0x35);
      _expectPixel(pixels, 150, 10, 0x1e, 0x88, 0xe5);
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  });

  test(
    'requires the expected pixel-derived visual detail without persisting it',
    () {
      expect(matchesVisionProbeResponse('RED'), isTrue);
      expect(matchesVisionProbeResponse('The left half is red.'), isTrue);
      expect(matchesVisionProbeResponse('BLUE'), isFalse);
    },
  );
}

void _expectPixel(
  Uint8List pixels,
  int x,
  int y,
  int red,
  int green,
  int blue,
) {
  final offset = ((y * VisionStagingProbeFixture.width) + x) * 4;
  expect(pixels[offset], red);
  expect(pixels[offset + 1], green);
  expect(pixels[offset + 2], blue);
  expect(pixels[offset + 3], 0xff);
}
