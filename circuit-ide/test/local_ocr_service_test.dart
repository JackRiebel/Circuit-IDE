import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/models/context_attachment.dart';
import 'package:circuit_ide/services/provider_image_input_builder.dart';
import 'package:circuit_ide/services/screenshot_context_attachment_builder.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'structured OCR sidecar requires image hash and preserves regions',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-ocr-');
      addTearDown(() => root.delete(recursive: true));
      final bytes = _pngBytes(width: 1440, height: 900);
      final image = File(p.join(root.path, 'screen.png'))
        ..writeAsBytesSync(bytes);
      File(p.join(root.path, 'screen.ocr.json')).writeAsStringSync(
        jsonEncode({
          'engine': 'approved_fixture_ocr',
          'sourceImageSha256': sha256.convert(bytes).toString(),
          'blocks': [
            {
              'text': 'Save changes',
              'confidence': 0.96,
              'x': 0.61,
              'y': 0.82,
              'width': 0.2,
              'height': 0.08,
            },
          ],
        }),
      );

      final attachment = await const ScreenshotContextAttachmentBuilder().build(
        image.path,
      );

      expect(attachment, isNotNull);
      expect(attachment!.metadata['ocrStatus'], 'local_or_approved_extracted');
      expect(attachment.metadata['ocrEngine'], 'approved_fixture_ocr');
      expect(attachment.metadata['ocrBoundingBoxCount'], 1);
      expect(attachment.metadata['hasOcrFallback'], isTrue);
      expect(
        attachment.metadata['ocrSourceImageSha256'],
        sha256.convert(bytes).toString(),
      );
      expect(attachment.content, contains('Save changes'));
      expect(attachment.content, contains('normalized regions'));
    },
  );

  test('wrong-hash OCR sidecar is not trusted as a fallback', () async {
    final root = await Directory.systemTemp.createTemp('circuit-ocr-hash-');
    addTearDown(() => root.delete(recursive: true));
    final image = File(p.join(root.path, 'screen.png'))
      ..writeAsBytesSync(_pngBytes(width: 1440, height: 900));
    File(p.join(root.path, 'screen.ocr.json')).writeAsStringSync(
      jsonEncode({
        'engine': 'approved_fixture_ocr',
        'sourceImageSha256': 'wrong-hash',
        'blocks': [
          {
            'text': 'Stale text',
            'confidence': 0.99,
            'x': 0.1,
            'y': 0.1,
            'width': 0.2,
            'height': 0.1,
          },
        ],
      }),
    );

    final attachment = await const ScreenshotContextAttachmentBuilder().build(
      image.path,
    );

    expect(attachment, isNotNull);
    expect(attachment!.metadata['hasOcrFallback'], isNot(true));
    expect(attachment.metadata['ocrStatus'], 'not_extracted');
  });

  test(
    'verified OCR fallback sends text without pixels to a text-only model',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-ocr-send-');
      addTearDown(() => root.delete(recursive: true));
      final bytes = _pngBytes(width: 1440, height: 900);
      final image = File(p.join(root.path, 'screen.png'))
        ..writeAsBytesSync(bytes);
      final result = await const ProviderImageInputBuilder().build(
        attachments: [
          ContextAttachment(
            id: 'ocr-image',
            type: ContextAttachmentType.image,
            label: 'screen.png',
            path: image.path,
            metadata: {
              'mimeType': 'image/png',
              'hasOcrFallback': true,
              'ocrText': 'Save changes',
              'ocrSourceImageSha256': sha256.convert(bytes).toString(),
            },
            createdAt: DateTime(2026),
          ),
        ],
        capabilities: const ProviderCapabilities(),
      );

      expect(result.errors, isEmpty);
      expect(result.images, isEmpty);
    },
  );

  test(
    'stale or malformed OCR provenance cannot bypass vision capability',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-ocr-stale-');
      addTearDown(() => root.delete(recursive: true));
      final image = File(p.join(root.path, 'screen.png'))
        ..writeAsBytesSync(_pngBytes(width: 1440, height: 900));
      final stale = ContextAttachment(
        id: 'stale-ocr-image',
        type: ContextAttachmentType.image,
        label: 'screen.png',
        path: image.path,
        metadata: const {
          'mimeType': 'image/png',
          'hasOcrFallback': true,
          'ocrText': 'Old text',
          'ocrSourceImageSha256':
              '0000000000000000000000000000000000000000000000000000000000000000',
        },
        createdAt: DateTime(2026),
      );
      final malformed = ContextAttachment(
        id: 'malformed-ocr-image',
        type: ContextAttachmentType.image,
        label: 'missing-provenance.png',
        path: image.path,
        metadata: const {
          'mimeType': 'image/png',
          'hasOcrFallback': true,
          'ocrText': 'Unbound text',
        },
        createdAt: DateTime(2026),
      );

      final staleResult = await const ProviderImageInputBuilder().build(
        attachments: [stale],
        capabilities: const ProviderCapabilities(),
      );
      final malformedResult = await const ProviderImageInputBuilder().build(
        attachments: [malformed],
        capabilities: const ProviderCapabilities(),
      );
      final visionStaleResult = await const ProviderImageInputBuilder().build(
        attachments: [stale],
        capabilities: const ProviderCapabilities(
          supportsImageInput: true,
          supportedImageMimeTypes: {'image/png'},
          maxImageBytes: 64 * 1024,
        ),
      );

      expect(staleResult.images, isEmpty);
      expect(staleResult.errors.single, contains('no longer matches'));
      expect(malformedResult.images, isEmpty);
      expect(malformedResult.errors.single, contains('missing hash-bound'));
      expect(visionStaleResult.images, isEmpty);
      expect(visionStaleResult.errors.single, contains('no longer matches'));
      expect(
        ProviderImageInputBuilder.hasHashBoundOcrProvenance(stale),
        isTrue,
      );
      expect(
        ProviderImageInputBuilder.hasHashBoundOcrProvenance(malformed),
        isFalse,
      );
    },
  );
}

Uint8List _pngBytes({required int width, required int height}) {
  final bytes = Uint8List(24);
  bytes.setAll(0, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  bytes.setAll(12, const [0x49, 0x48, 0x44, 0x52]);
  final data = ByteData.sublistView(bytes);
  data.setUint32(16, width);
  data.setUint32(20, height);
  return bytes;
}
