import 'dart:io';
import 'dart:typed_data';

import 'package:circuit_ide/models/context_attachment.dart';
import 'package:circuit_ide/services/screenshot_context_attachment_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ContextAttachment serializes visible context into prompt blocks', () {
    final attachment = ContextAttachment(
      id: 'a1',
      type: ContextAttachmentType.file,
      label: 'main.dart',
      path: '/tmp/project/main.dart',
      content: 'class App {}',
      createdAt: DateTime(2026, 5, 25),
    );

    expect(attachment.promptHeader, contains('main.dart'));
    expect(attachment.promptHeader, contains('/tmp/project/main.dart'));
    expect(attachment.toPromptBlock(), contains('class App {}'));
  });

  test('ContextAttachment preserves preview metadata through JSON', () {
    final attachment = ContextAttachment(
      id: 'a2',
      type: ContextAttachmentType.file,
      label: 'big.dart',
      path: '/tmp/project/big.dart',
      content: 'void main() {}',
      resolutionStatus: ContextAttachmentResolutionStatus.tooLarge,
      estimatedTokens: 42,
      truncationMessage: '[Context truncated.]',
      createdAt: DateTime(2026, 5, 25),
    );

    final restored = ContextAttachment.fromJson(attachment.toJson());

    expect(restored, isNotNull);
    expect(
      restored!.resolutionStatus,
      ContextAttachmentResolutionStatus.tooLarge,
    );
    expect(restored.estimatedTokens, 42);
    expect(restored.toPromptBlock(), contains('[Context truncated.]'));
  });

  test(
    'image attachments serialize screenshot metadata into prompt blocks',
    () {
      final attachment = ContextAttachment(
        id: 'image:/tmp/screen.png',
        type: ContextAttachmentType.image,
        label: 'screen.png',
        path: '/tmp/screen.png',
        content:
            'Image attachment for visual review.\nDimensions: 1440 x 900px',
        createdAt: DateTime(2026, 7, 1),
      );

      final restored = ContextAttachment.fromJson(attachment.toJson());

      expect(restored, isNotNull);
      expect(restored!.type, ContextAttachmentType.image);
      expect(restored.promptHeader, contains('[Context image: screen.png'));
      expect(restored.toPromptBlock(), contains('Dimensions: 1440 x 900px'));
    },
  );

  test('ScreenshotContextAttachmentBuilder reads PNG dimensions', () async {
    final root = await Directory.systemTemp.createTemp('circuit-shot-');
    addTearDown(() => root.delete(recursive: true));
    final image = File('${root.path}/screen.png')
      ..writeAsBytesSync(_pngBytes(width: 1440, height: 900));

    final attachment = await const ScreenshotContextAttachmentBuilder().build(
      image.path,
    );

    expect(attachment, isNotNull);
    expect(attachment!.type, ContextAttachmentType.image);
    expect(
      attachment.resolutionStatus,
      ContextAttachmentResolutionStatus.resolved,
    );
    expect(attachment.content, contains('Format: PNG'));
    expect(attachment.content, contains('Dimensions: 1440 x 900px'));
    expect(
      attachment.content,
      contains('OCR and visual reasoning are not yet completed'),
    );
  });

  test('ScreenshotContextAttachmentBuilder skips unsupported files', () async {
    final attachment = await const ScreenshotContextAttachmentBuilder().build(
      '/tmp/readme.md',
    );

    expect(attachment, isNull);
  });
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
