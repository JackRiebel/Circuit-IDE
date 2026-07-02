import 'dart:io';
import 'dart:typed_data';

import 'package:circuit_ide/models/context_attachment.dart';
import 'package:circuit_ide/ui/studio/studio_message_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Studio image directives become visual evidence attachments', () async {
    final root = await Directory.systemTemp.createTemp('studio_image_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final screenshot = File(p.join(root.path, 'dashboard.png'))
      ..writeAsBytesSync(_pngBytes(width: 1440, height: 900));

    final message = await debugStudioImageDirectiveMessage(
      '/screenshot dashboard.png\nCreate a UX findings report.',
      rootPath: root.path,
    );
    final attachments = await debugStudioImageDirectiveAttachments(
      '/screenshot dashboard.png\nCreate a UX findings report.',
      rootPath: root.path,
    );

    expect(message, 'Create a UX findings report.');
    expect(attachments, hasLength(1));
    final attachment = attachments.single;
    expect(attachment.type, ContextAttachmentType.image);
    expect(attachment.path, screenshot.path);
    expect(attachment.content, contains('Dimensions: 1440 x 900px'));
    expect(
      attachment.content,
      contains('Safe use: cite the screenshot as provided evidence'),
    );
    expect(attachment.metadata['artifactRole'], 'visual_evidence');
    expect(attachment.metadata['ocrStatus'], 'not_extracted');
    expect(attachment.metadata['providerPixelInputSupported'], isFalse);
    expect(attachment.metadata['analysisReliability'], 'metadata_only');
    expect(
      attachment.metadata['recommendedFollowUp'],
      contains('OCR/vision integration'),
    );
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
