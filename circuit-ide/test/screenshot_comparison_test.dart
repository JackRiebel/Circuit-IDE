import 'dart:io';
import 'dart:typed_data';

import 'package:circuit_ide/models/context_attachment.dart';
import 'package:circuit_ide/services/screenshot_comparison.dart';
import 'package:circuit_ide/ui/studio/studio_message_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('comparison directives retain named normalized regions', () {
    final directive = ScreenshotComparisonDirective.tryParse(
      'reference.png | current.png | current: Save button overlaps footer @ 0.10, 0.72, 0.32, 0.12 | reference: Baseline control @ 0.10,0.72,0.32,0.12',
    );

    expect(directive, isNotNull);
    expect(directive!.referencePath, 'reference.png');
    expect(directive.currentPath, 'current.png');
    expect(directive.findings, hasLength(2));
    expect(directive.findings.first.side, ScreenshotComparisonSide.current);
    expect(directive.findings.first.region.label, '10%, 72%, 32%, 12%');
    expect(directive.findings.last.side, ScreenshotComparisonSide.reference);
    expect(
      ScreenshotComparisonDirective.tryParse(
        'reference.png | current.png | malformed annotation',
      ),
      isNull,
    );
  });

  test(
    'comparison attachments preserve roles, region citations, and pixels',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-comparison-');
      addTearDown(() => root.delete(recursive: true));
      final reference = File(p.join(root.path, 'reference.png'))
        ..writeAsBytesSync(_pngBytes(width: 1440, height: 900));
      final current = File(p.join(root.path, 'current.png'))
        ..writeAsBytesSync(_pngBytes(width: 1280, height: 720));
      const finding = ScreenshotComparisonFinding(
        side: ScreenshotComparisonSide.current,
        text: 'Save button overlaps the footer.',
        region: ScreenshotComparisonRegion(
          x: 0.1,
          y: 0.72,
          width: 0.32,
          height: 0.12,
        ),
      );

      final comparison = await const ScreenshotComparisonAttachmentBuilder()
          .build(
            referencePath: reference.path,
            currentPath: current.path,
            findings: const [finding],
          );

      expect(comparison.attachments, hasLength(3));
      final referenceAttachment = comparison.attachments[0];
      final currentAttachment = comparison.attachments[1];
      final note = comparison.attachments[2];
      expect(referenceAttachment.type, ContextAttachmentType.image);
      expect(currentAttachment.type, ContextAttachmentType.image);
      expect(referenceAttachment.metadata['comparisonRole'], 'reference');
      expect(currentAttachment.metadata['comparisonRole'], 'current');
      expect(
        referenceAttachment.metadata['comparisonId'],
        comparison.comparisonId,
      );
      expect(currentAttachment.content, contains('Comparison role: Current.'));
      expect(note.type, ContextAttachmentType.note);
      expect(note.metadata['artifactRole'], 'visual_comparison');
      final restored = ContextAttachment.fromJson(note.toJson());
      expect(restored, isNotNull);
      expect(restored!.metadata['comparisonId'], comparison.comparisonId);
      expect(restored.metadata['comparisonFindings'], hasLength(1));
      expect(
        note.toPromptBlock(),
        contains('[Reference|Current region x,y,width,height]'),
      );
      expect(
        note.toPromptBlock(),
        contains('Save button overlaps the footer.'),
      );
      expect(note.toPromptBlock(), contains('10%, 72%, 32%, 12%'));
    },
  );

  test(
    'Studio compare directive removes command text and keeps comparison note',
    () async {
      final root = await Directory.systemTemp.createTemp('studio-compare-');
      addTearDown(() => root.delete(recursive: true));
      final before = File(p.join(root.path, 'before.png'));
      before.writeAsBytesSync(_pngBytes(width: 1440, height: 900));
      final after = File(p.join(root.path, 'after.png'));
      after.writeAsBytesSync(_pngBytes(width: 1280, height: 720));
      const request =
          '/compare before.png | after.png | current: Footer collision @ 0.10,0.72,0.32,0.12\nPlan the repair and cite the region.';

      final message = await debugStudioImageDirectiveMessage(
        request,
        rootPath: root.path,
      );
      final attachments = await debugStudioImageDirectiveAttachments(
        request,
        rootPath: root.path,
      );

      expect(message, 'Plan the repair and cite the region.');
      expect(attachments, hasLength(3));
      expect(
        attachments.where(
          (attachment) => attachment.type == ContextAttachmentType.image,
        ),
        hasLength(2),
      );
      final note = attachments.singleWhere(
        (attachment) => attachment.type == ContextAttachmentType.note,
      );
      expect(note.metadata['comparisonFindings'], hasLength(1));
      expect(note.content, contains('Footer collision'));
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
