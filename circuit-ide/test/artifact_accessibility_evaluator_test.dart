import 'package:circuit_ide/models/artifact_document.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/artifact_accessibility_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const evaluator = ArtifactAccessibilityEvaluator();
  const document = ArtifactDocument(
    title: 'Accessible artifact',
    summary: 'A structured artifact for review.',
    sections: [ArtifactSection(title: 'Summary', body: 'Details')],
    tables: [
      ArtifactTable(
        title: 'Inventory',
        rows: [
          ['Model', 'Count'],
          ['C9300', '2'],
        ],
      ),
    ],
  );

  test('format fixtures pass their selected accessibility checks', () {
    final fixtures = <GeneratedArtifactKind, Map<String, Object?>>{
      GeneratedArtifactKind.docx: {
        'docxHasAccessibilityManifest': true,
        'docxHasRepeatingTableHeaders': true,
      },
      GeneratedArtifactKind.pdf: {
        'pdfHasTaggedStructure': true,
        'pdfHasAccessibilityPolicy': true,
        'pdfHasOutlineTree': true,
        'pdfHasExplicitTableGeometry': true,
      },
      GeneratedArtifactKind.powerPoint: {
        'hasAccessibleSlideTitles': true,
        'hasLogicalSlideReadingOrder': true,
      },
      GeneratedArtifactKind.diagram: {
        'hasAccessibleSvgTitle': true,
        'hasAccessibleSvgDescription': true,
      },
      GeneratedArtifactKind.chart: {
        'hasAccessibleSvgTitle': true,
        'hasAccessibleSvgDescription': true,
      },
      GeneratedArtifactKind.html: {
        'htmlHasDocumentTitle': true,
        'htmlHasDocumentLanguage': true,
        'htmlHasMainLandmark': true,
        'htmlHasSemanticSections': true,
        'htmlHasTableHeaders': true,
        'htmlHasTableCaptions': true,
        'htmlHasAccessibleColorContrast': true,
      },
    };
    for (final fixture in fixtures.entries) {
      final result = evaluator.metadataFor(
        kind: fixture.key,
        document: document,
        previewRows: const [
          ['Model', 'Count'],
          ['C9300', '2'],
        ],
        metadata: fixture.value,
      );
      expect(result['hasAccessibleArtifact'], isTrue, reason: fixture.key.name);
      expect(result['accessibilityGaps'], isEmpty, reason: fixture.key.name);
    }
  });

  test(
    'missing DOCX reading-order data is an actionable accessibility gap',
    () {
      final result = evaluator.metadataFor(
        kind: GeneratedArtifactKind.docx,
        document: document,
        previewRows: const [],
        metadata: const {},
      );
      expect(
        result['accessibilityGaps'],
        containsAll([
          'Accessibility: Word heading and reading-order manifest',
          'Accessibility: Repeating table headers',
        ]),
      );
      expect(result['hasAccessibleArtifact'], isFalse);
    },
  );

  test('HTML requires renderer-backed semantic accessibility signals', () {
    final result = evaluator.metadataFor(
      kind: GeneratedArtifactKind.html,
      document: document,
      previewRows: const [
        ['Model', 'Count'],
        ['C9300', '2'],
      ],
      metadata: const {
        'htmlHasDocumentTitle': true,
        'htmlHasDocumentLanguage': true,
        'htmlHasMainLandmark': true,
        'htmlHasSemanticSections': false,
        'htmlHasTableHeaders': false,
        'htmlHasTableCaptions': false,
        'htmlHasAccessibleColorContrast': true,
      },
    );

    expect(result['hasAccessibleArtifact'], isFalse);
    expect(
      result['accessibilityGaps'],
      containsAll([
        'Accessibility: Semantic HTML sections',
        'Accessibility: HTML table headers',
        'Accessibility: HTML table captions',
      ]),
    );
  });
}
