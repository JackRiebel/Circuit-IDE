import 'dart:convert';

import '../models/artifact_document.dart';
import '../models/generated_artifact.dart';
import 'zip_package_integrity.dart';

/// One durable, format-neutral quality report for every generated artifact.
///
/// Native package inspectors remain the source of truth for Office/PDF
/// structure. This evaluator brings their result together with the persisted
/// visual review surface, source provenance, and format-specific
/// accessibility checks so a release gate can assert the same four dimensions
/// for every output kind.
class ArtifactQualityMatrixEvaluator {
  const ArtifactQualityMatrixEvaluator();

  Map<String, Object?> metadataFor({
    required GeneratedArtifactKind kind,
    required ArtifactDocument document,
    required List<int> bytes,
    required String extension,
    required List<List<String>> previewRows,
    required Map<String, Object?> metadata,
    required bool visualPreviewPersisted,
  }) {
    final structural = _structuralCheck(
      kind: kind,
      bytes: bytes,
      extension: extension,
      previewRows: previewRows,
      metadata: metadata,
    );
    final visual = _visualCheck(
      kind: kind,
      metadata: metadata,
      visualPreviewPersisted: visualPreviewPersisted,
    );
    final content = _contentCheck(kind, document, previewRows, metadata);
    final source = _sourceCheck(document, metadata);
    final accessibility = _metadataBool(metadata, 'hasAccessibleArtifact');
    final rows = <Map<String, Object?>>[
      {
        'dimension': 'Structural validity',
        'passed': structural,
        'evidence': _structuralEvidence(kind),
      },
      {
        'dimension': 'Visual review',
        'passed': visual,
        'evidence': _visualEvidence(kind),
      },
      {
        'dimension': 'Content completeness',
        'passed': content,
        'evidence': _contentEvidence(kind),
      },
      {
        'dimension': 'Source and citation provenance',
        'passed': source,
        'evidence': 'Composed source list is retained with the artifact recipe',
      },
      {
        'dimension': 'Accessibility',
        'passed': accessibility,
        'evidence': 'Format-specific automated accessibility checks',
      },
    ];
    final gaps = rows
        .where((row) => row['passed'] != true)
        .map((row) => row['dimension'] as String)
        .toList(growable: false);
    return {
      'artifactQualityMatrixVersion': '1.0',
      'artifactQualityMatrixKind': kind.name,
      'artifactQualityMatrix': rows,
      'artifactQualityMatrixGateCount': rows.length,
      'artifactQualityMatrixGapCount': gaps.length,
      'artifactQualityMatrixGaps': gaps,
      'artifactQualityMatrixStatus': gaps.isEmpty ? 'Passed' : 'Needs review',
      'artifactQualityMatrixPassed': gaps.isEmpty,
    };
  }

  bool _structuralCheck({
    required GeneratedArtifactKind kind,
    required List<int> bytes,
    required String extension,
    required List<List<String>> previewRows,
    required Map<String, Object?> metadata,
  }) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return switch (kind) {
      GeneratedArtifactKind.docx =>
        _metadataBool(metadata, 'docxStructuralValid') && _isZip(bytes),
      GeneratedArtifactKind.pdf =>
        _metadataBool(metadata, 'pdfStructuralValid') &&
            latin1.decode(bytes, allowInvalid: true).contains('%PDF-'),
      GeneratedArtifactKind.powerPoint =>
        _metadataBool(metadata, 'pptxStructuralValid') && _isZip(bytes),
      GeneratedArtifactKind.excel =>
        _metadataBool(metadata, 'workbookStructuralValid') && _isZip(bytes),
      GeneratedArtifactKind.csv =>
        extension == 'csv' && _hasConsistentCsvRows(text),
      GeneratedArtifactKind.json => extension == 'json' && _isJson(text),
      GeneratedArtifactKind.html =>
        extension == 'html' &&
            text.contains('<!doctype html>') &&
            text.contains('<main>') &&
            text.contains('</html>'),
      GeneratedArtifactKind.markdown || GeneratedArtifactKind.report =>
        extension == 'md' && text.trim().isNotEmpty,
      GeneratedArtifactKind.diagram || GeneratedArtifactKind.chart =>
        extension == 'svg' &&
            text.contains('<svg') &&
            text.contains('<title') &&
            text.contains('<desc'),
    };
  }

  bool _visualCheck({
    required GeneratedArtifactKind kind,
    required Map<String, Object?> metadata,
    required bool visualPreviewPersisted,
  }) {
    if (!visualPreviewPersisted) return false;
    if (_metadataString(metadata, 'visualPreviewPersistence') !=
            'atomic-sidecar-v1' ||
        !_hasSha256(metadata, 'visualPreviewSha256') ||
        _metadataInt(metadata, 'visualPreviewByteSize') <= 0) {
      return false;
    }
    if (kind == GeneratedArtifactKind.powerPoint) {
      return _metadataString(
            metadata,
            'pptxVisualPreviewRenderer',
          ).isNotEmpty &&
          !_metadataBool(metadata, 'pptxVisualPreviewHasTitleOverflow') &&
          !_metadataBool(metadata, 'pptxVisualPreviewHasContentOverflow');
    }
    return _metadataString(
          metadata,
          'artifactVisualPreviewRenderer',
        ).isNotEmpty &&
        !_metadataBool(metadata, 'artifactVisualPreviewHasOverflow');
  }

  bool _sourceCheck(ArtifactDocument document, Map<String, Object?> metadata) {
    return document.citations.isNotEmpty &&
        _metadataInt(metadata, 'artifactCitationCount') > 0 &&
        _metadataBool(metadata, 'artifactHasSources');
  }

  bool _contentCheck(
    GeneratedArtifactKind kind,
    ArtifactDocument document,
    List<List<String>> previewRows,
    Map<String, Object?> metadata,
  ) {
    final hasNarrative =
        document.title.trim().isNotEmpty &&
        (document.summary.trim().isNotEmpty || document.sections.isNotEmpty);
    return switch (kind) {
      GeneratedArtifactKind.excel || GeneratedArtifactKind.csv =>
        previewRows.length >= 2 && previewRows.first.isNotEmpty,
      GeneratedArtifactKind.diagram =>
        _metadataInt(metadata, 'nodeCount') > 0 &&
            _metadataInt(metadata, 'edgeCount') > 0,
      GeneratedArtifactKind.chart =>
        _metadataInt(metadata, 'chartCount') > 0 &&
            _metadataInt(metadata, 'pointCount') > 0,
      _ => hasNarrative,
    };
  }

  bool _isZip(List<int> bytes) =>
      const ZipPackageInspector().inspect(bytes).isStructurallyValid;

  bool _isJson(String value) {
    try {
      jsonDecode(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _hasConsistentCsvRows(String value) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    for (var index = 0; index < value.length; index++) {
      final char = value[index];
      if (char == '"') {
        if (quoted && index + 1 < value.length && value[index + 1] == '"') {
          cell.write(char);
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        row.add(cell.toString());
        cell = StringBuffer();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        if (char == '\r' &&
            index + 1 < value.length &&
            value[index + 1] == '\n') {
          index++;
        }
        row.add(cell.toString());
        if (row.any((entry) => entry.isNotEmpty)) rows.add(row);
        row = <String>[];
        cell = StringBuffer();
      } else {
        cell.write(char);
      }
    }
    if (quoted) return false;
    row.add(cell.toString());
    if (row.any((entry) => entry.isNotEmpty)) rows.add(row);
    if (rows.length < 2 || rows.first.isEmpty) return false;
    return rows.every((row) => row.length == rows.first.length);
  }

  String _structuralEvidence(GeneratedArtifactKind kind) => switch (kind) {
    GeneratedArtifactKind.docx => 'DOCX package inspection',
    GeneratedArtifactKind.pdf => 'PDF package inspection',
    GeneratedArtifactKind.powerPoint => 'PowerPoint package inspection',
    GeneratedArtifactKind.excel => 'Workbook package inspection',
    GeneratedArtifactKind.csv => 'CSV row and column parser',
    GeneratedArtifactKind.json => 'JSON parser',
    GeneratedArtifactKind.html => 'Semantic HTML document contract',
    GeneratedArtifactKind.markdown ||
    GeneratedArtifactKind.report => 'Markdown document contract',
    GeneratedArtifactKind.diagram ||
    GeneratedArtifactKind.chart => 'SVG title and description contract',
  };

  String _visualEvidence(GeneratedArtifactKind kind) => switch (kind) {
    GeneratedArtifactKind.powerPoint =>
      'Persisted multi-slide structural review sidecar',
    GeneratedArtifactKind.docx ||
    GeneratedArtifactKind.pdf ||
    GeneratedArtifactKind.excel =>
      'Persisted multi-page structural review sidecar',
    _ => 'Persisted structural review sidecar',
  };

  String _contentEvidence(GeneratedArtifactKind kind) => switch (kind) {
    GeneratedArtifactKind.excel ||
    GeneratedArtifactKind.csv => 'Header and data rows',
    GeneratedArtifactKind.diagram => 'Topology nodes and links',
    GeneratedArtifactKind.chart => 'Chart panels and data points',
    _ => 'Artifact title and structured composition',
  };

  bool _metadataBool(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is bool) return value;
    return value?.toString().trim().toLowerCase() == 'true';
  }

  int _metadataInt(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _metadataString(Map<String, Object?> metadata, String key) =>
      metadata[key]?.toString().trim() ?? '';

  bool _hasSha256(Map<String, Object?> metadata, String key) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(_metadataString(metadata, key));
}
