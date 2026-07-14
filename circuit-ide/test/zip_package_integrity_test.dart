import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/docx_artifact_renderer.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:circuit_ide/services/office_package_relationship_inspector.dart';
import 'package:circuit_ide/services/powerpoint_artifact_renderer.dart';
import 'package:circuit_ide/services/zip_package_integrity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const document = ArtifactDocument(
    title: 'ZIP integrity customer readiness',
    summary: 'A package-integrity regression fixture.',
    sections: [
      ArtifactSection(
        title: 'Decision',
        bullets: ['Approve only verified customer-ready artifacts.'],
      ),
    ],
    citations: ['Customer workshop notes.'],
  );

  test('validates generated DOCX PPTX and XLSX package containers', () async {
    final docx = const DocxArtifactRenderer().render(document);
    final pptx = const PowerPointArtifactRenderer().render(document);
    final root = await Directory.systemTemp.createTemp(
      'circuit-zip-integrity-',
    );
    addTearDown(() => root.delete(recursive: true));
    final workbook = await const GeneratedArtifactWriter()
        .writeStructuredArtifact(
          rootPath: root.path,
          prompt: 'Create an Excel customer readiness workbook',
          content: '''
# Customer Readiness

| Gate | Status |
| --- | --- |
| Package integrity | Verified |
''',
          targetKind: GeneratedArtifactKind.excel,
          turnId: 'zip-integrity',
          threadId: 'thread-zip-integrity',
          requestId: 'request-zip-integrity',
        );
    expect(workbook, isNotNull);
    final workbookBytes = await File(workbook!.filePath).readAsBytes();

    for (final package in [docx, pptx, workbookBytes]) {
      final inspection = const ZipPackageInspector().inspect(package);
      expect(inspection.isStructurallyValid, isTrue);
      expect(inspection.entryCount, greaterThan(1));
      expect(inspection.failures, isEmpty);
      final relationships = const OfficePackageRelationshipInspector().inspect(
        inspection,
      );
      expect(relationships.hasResolvableInternalTargets, isTrue);
      expect(relationships.internalRelationshipCount, greaterThan(0));
    }
  });

  test('rejects truncated and payload-tampered Office packages', () {
    final source = const DocxArtifactRenderer().render(document);
    final truncated = source.sublist(0, source.length ~/ 2);
    final truncatedInspection = const ZipPackageInspector().inspect(truncated);
    expect(truncatedInspection.isStructurallyValid, isFalse);
    expect(truncatedInspection.hasEndOfCentralDirectory, isFalse);

    final tampered = Uint8List.fromList(source);
    final payloadOffset = latin1
        .decode(tampered, allowInvalid: true)
        .indexOf('ZIP integrity customer readiness');
    expect(payloadOffset, greaterThan(0));
    tampered[payloadOffset] ^= 0x01;
    final tamperedInspection = const ZipPackageInspector().inspect(tampered);
    expect(tamperedInspection.isStructurallyValid, isFalse);
    expect(tamperedInspection.failures, isNotEmpty);
  });

  test('reports an Office relationship that points to a missing asset', () {
    final package = ZipPackageInspection(
      hasZipHeader: true,
      hasEndOfCentralDirectory: true,
      hasConsistentCentralDirectory: true,
      hasValidatedEntries: true,
      entryCount: 2,
      entryNames: const ['word/document.xml', 'word/_rels/document.xml.rels'],
      storedEntries: {
        'word/document.xml': Uint8List(0),
        'word/_rels/document.xml.rels': Uint8List.fromList(
          utf8.encode(
            '<Relationships><Relationship Id="rId1" Target="media/image1.png" /></Relationships>',
          ),
        ),
      },
      failures: const [],
    );

    final inspection = const OfficePackageRelationshipInspector().inspect(
      package,
    );
    expect(inspection.hasResolvableInternalTargets, isFalse);
    expect(
      inspection.missingTargets,
      contains('word/_rels/document.xml.rels -> media/image1.png'),
    );
  });
}
