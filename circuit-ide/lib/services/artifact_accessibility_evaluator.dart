import '../models/artifact_document.dart';
import '../models/generated_artifact.dart';

/// Format-specific accessibility signals that can be evaluated before a human
/// completes a screen-reader review of a generated artifact.
class ArtifactAccessibilityEvaluator {
  const ArtifactAccessibilityEvaluator();

  Map<String, Object?> metadataFor({
    required GeneratedArtifactKind kind,
    required ArtifactDocument document,
    required List<List<String>> previewRows,
    required Map<String, Object?> metadata,
  }) {
    final checks = _checksFor(kind, document, previewRows, metadata);
    final gaps = checks.entries
        .where((entry) => !entry.value)
        .map((entry) => 'Accessibility: ${entry.key}')
        .toList(growable: false);
    return {
      'accessibilityStatus': gaps.isEmpty ? 'Checks passed' : 'Needs review',
      'accessibilityChecks': checks.entries
          .map((entry) => {'check': entry.key, 'passed': entry.value})
          .toList(growable: false),
      'accessibilityCheckCount': checks.length,
      'accessibilityGaps': gaps,
      'accessibilityGapCount': gaps.length,
      'hasAccessibleArtifact': gaps.isEmpty,
      'accessibilityManualReview':
          'Review the generated output with the target format\'s screen reader before external handoff.',
    };
  }

  Map<String, bool> _checksFor(
    GeneratedArtifactKind kind,
    ArtifactDocument document,
    List<List<String>> previewRows,
    Map<String, Object?> metadata,
  ) {
    final hasTableHeaders = document.tables.every(
      (table) => table.rows.isEmpty || table.rows.first.isNotEmpty,
    );
    return switch (kind) {
      GeneratedArtifactKind.docx => {
        'Word heading and reading-order manifest': _bool(
          metadata,
          'docxHasAccessibilityManifest',
        ),
        'Repeating table headers': _bool(
          metadata,
          'docxHasRepeatingTableHeaders',
        ),
      },
      GeneratedArtifactKind.pdf => {
        'PDF tagged reading order': _bool(metadata, 'pdfHasTaggedStructure'),
        'PDF accessibility policy metadata': _bool(
          metadata,
          'pdfHasAccessibilityPolicy',
        ),
        'Bookmark outline': _bool(metadata, 'pdfHasOutlineTree'),
        'Explicit table geometry': _bool(
          metadata,
          'pdfHasExplicitTableGeometry',
        ),
      },
      GeneratedArtifactKind.powerPoint => {
        'Slide titles': _bool(metadata, 'hasAccessibleSlideTitles'),
        'Logical slide reading order': _bool(
          metadata,
          'hasLogicalSlideReadingOrder',
        ),
      },
      GeneratedArtifactKind.excel || GeneratedArtifactKind.csv => {
        'Table headers': hasTableHeaders,
        'Previewable data rows': previewRows.length >= 2,
      },
      GeneratedArtifactKind.diagram || GeneratedArtifactKind.chart => {
        'SVG title': _bool(metadata, 'hasAccessibleSvgTitle'),
        'SVG description': _bool(metadata, 'hasAccessibleSvgDescription'),
      },
      GeneratedArtifactKind.html => {
        'HTML document title': _bool(metadata, 'htmlHasDocumentTitle'),
        'HTML document language': _bool(metadata, 'htmlHasDocumentLanguage'),
        'Main content landmark': _bool(metadata, 'htmlHasMainLandmark'),
        'Semantic HTML sections': _bool(metadata, 'htmlHasSemanticSections'),
        'HTML table headers':
            !_hasRenderedTables(document) ||
            _bool(metadata, 'htmlHasTableHeaders'),
        'HTML table captions':
            !_hasRenderedTables(document) ||
            _bool(metadata, 'htmlHasTableCaptions'),
        'Accessible text contrast': _bool(
          metadata,
          'htmlHasAccessibleColorContrast',
        ),
      },
      GeneratedArtifactKind.markdown ||
      GeneratedArtifactKind.json ||
      GeneratedArtifactKind.report => {
        'Document title': document.title.trim().isNotEmpty,
        'Structured content':
            document.sections.isNotEmpty || document.summary.trim().isNotEmpty,
      },
    };
  }

  bool _bool(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is bool) return value;
    return value?.toString().trim().toLowerCase() == 'true';
  }

  bool _hasRenderedTables(ArtifactDocument document) =>
      document.tables.any((table) => table.rows.isNotEmpty) ||
      document.sourceData.any((table) => table.rows.isNotEmpty);
}
