import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/models/context_attachment.dart';
import 'package:circuit_ide/services/provider_image_input_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const capable = ProviderCapabilities(
    supportsImageInput: true,
    supportedImageMimeTypes: {'image/png'},
    maxImageBytes: 64 * 1024,
  );

  test(
    'builds request-local base64 pixels with a conservative token estimate',
    () async {
      final root = await Directory.systemTemp.createTemp('provider-image-');
      addTearDown(() => root.delete(recursive: true));
      final image = File('${root.path}/screen.png');
      final bytes = await _pngBytes(width: 1440, height: 900);
      await image.writeAsBytes(bytes);

      final result = await const ProviderImageInputBuilder().build(
        attachments: [
          ContextAttachment(
            id: 'image:screen',
            type: ContextAttachmentType.image,
            label: 'screen.png',
            path: image.path,
            metadata: const {
              'mimeType': 'image/png',
              'width': 1440,
              'height': 900,
            },
            createdAt: DateTime(2026),
          ),
        ],
        capabilities: capable,
      );

      expect(result.errors, isEmpty);
      expect(result.images, hasLength(1));
      final payload = result.images.single;
      expect(payload.mimeType, 'image/png');
      expect(payload.byteLength, bytes.length);
      expect(payload.estimatedTokens, greaterThan(85));
      expect(payload.wasResized, isFalse);
      expect(
        payload.toOpenAiContentPart()['image_url']['url'],
        startsWith('data:image/png;base64,'),
      );
    },
  );

  test('fails closed for an unsupported model or oversized image', () async {
    final root = await Directory.systemTemp.createTemp('provider-image-');
    addTearDown(() => root.delete(recursive: true));
    final image = File('${root.path}/screen.png');
    await image.writeAsBytes(await _pngBytes(width: 32, height: 32));
    final attachment = ContextAttachment(
      id: 'image:screen',
      type: ContextAttachmentType.image,
      label: 'screen.png',
      path: image.path,
      metadata: const {'mimeType': 'image/png'},
      createdAt: DateTime(2026),
    );

    final unsupported = await const ProviderImageInputBuilder().build(
      attachments: [attachment],
      capabilities: const ProviderCapabilities(),
    );
    final oversized = await const ProviderImageInputBuilder().build(
      attachments: [attachment],
      capabilities: const ProviderCapabilities(
        supportsImageInput: true,
        supportedImageMimeTypes: {'image/png'},
        maxImageBytes: 1,
        maxImageDimension: 8,
      ),
    );

    expect(unsupported.images, isEmpty);
    expect(unsupported.errors.single, contains('does not accept image input'));
    expect(oversized.images, isEmpty);
    expect(oversized.errors.single, contains('exceeds'));
  });

  test('resizes oversized dimensions before sending pixels', () async {
    final root = await Directory.systemTemp.createTemp('provider-image-');
    addTearDown(() => root.delete(recursive: true));
    final image = File('${root.path}/large.png');
    await image.writeAsBytes(await _pngBytes(width: 360, height: 240));

    final result = await const ProviderImageInputBuilder().build(
      attachments: [
        ContextAttachment(
          id: 'image:large',
          type: ContextAttachmentType.image,
          label: 'large.png',
          path: image.path,
          metadata: const {'mimeType': 'image/png'},
          createdAt: DateTime(2026),
        ),
      ],
      capabilities: const ProviderCapabilities(
        supportsImageInput: true,
        supportedImageMimeTypes: {'image/png'},
        maxImageBytes: 1024 * 1024,
        maxImageDimension: 120,
      ),
    );

    expect(result.errors, isEmpty);
    final payload = result.images.single;
    expect(payload.wasResized, isTrue);
    expect(payload.mimeType, 'image/png');
    expect(payload.width, 120);
    expect(payload.height, 80);
  });

  test('capability matrix is negotiated for the selected model', () {
    const provider = ProviderCapabilities(
      supportsNativeToolCalls: true,
      supportsImageInput: true,
      supportsJsonSchema: true,
      supportsReasoning: true,
      supportedImageMimeTypes: {'image/png'},
      maxImageBytes: 1024,
      maxImageDimension: 128,
    );
    const textOnly = ModelInfo(
      id: 'text-only',
      displayName: 'Text only',
      contextWindow: 1000,
      supportsTools: false,
    );
    const vision = ModelInfo(
      id: 'vision',
      displayName: 'Vision',
      contextWindow: 1000,
      supportsTools: true,
      supportsImageInput: true,
      supportsJsonSchema: true,
      supportsReasoning: true,
      tokenSemantics: ProviderTokenSemantics.inputCachedOutputReasoningTool,
    );
    final textCapabilities = capabilitiesForSelectedModel(provider, textOnly);
    final visionCapabilities = capabilitiesForSelectedModel(provider, vision);

    expect(textCapabilities.supportsNativeToolCalls, isFalse);
    expect(textCapabilities.supportsImageInput, isFalse);
    expect(textCapabilities.supportsJsonSchema, isFalse);
    expect(textCapabilities.supportsReasoning, isFalse);
    expect(
      textCapabilities.tokenSemantics,
      ProviderTokenSemantics.inputAndOutput,
    );
    expect(visionCapabilities.supportsNativeToolCalls, isTrue);
    expect(visionCapabilities.supportsImageInput, isTrue);
    expect(visionCapabilities.supportsJsonSchema, isTrue);
    expect(visionCapabilities.supportsReasoning, isTrue);
    expect(
      visionCapabilities.tokenSemantics,
      ProviderTokenSemantics.inputCachedOutputReasoningTool,
    );
    expect(
      ConnectorModelInfo.fromJson(const {
        'id': 'vision',
        'displayName': 'Vision',
        'supportsImageInput': true,
        'supportsJsonSchema': true,
        'supportsReasoning': true,
        'tokenSemantics': 'inputCachedOutputReasoningTool',
      })?.toJson(),
      containsPair('tokenSemantics', 'inputCachedOutputReasoningTool'),
    );
  });
}

Future<Uint8List> _pngBytes({required int width, required int height}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xff1a73e8),
  );
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
