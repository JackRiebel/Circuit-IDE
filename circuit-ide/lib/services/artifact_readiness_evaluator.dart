import '../models/artifact_document.dart';
import '../models/generated_artifact.dart';

class ArtifactReadinessEvaluator {
  const ArtifactReadinessEvaluator();

  Map<String, Object?> metadataFor({
    required GeneratedArtifactKind kind,
    required GeneratedArtifactStatus status,
    required ArtifactDocument document,
    required List<List<String>> previewRows,
    required int count,
    required int byteSize,
    required Map<String, Object?> metadata,
  }) {
    final gaps = <String>{
      ..._metadataStringList(metadata, 'validationGaps'),
      ..._metadataStringList(metadata, 'evidenceGaps'),
    };
    final gates = <String>{};

    if (byteSize > 0) {
      gates.add('File generated');
    } else {
      gaps.add('Generated file is empty or missing');
    }

    if (status == GeneratedArtifactStatus.ready) {
      gates.add('Native format ready');
    } else if (status == GeneratedArtifactStatus.fallback) {
      gaps.add('Generated with fallback format');
    } else {
      gaps.add('Artifact generation failed');
    }

    if (previewRows.isNotEmpty) {
      gates.add('Preview available');
    } else if (_needsPreview(kind)) {
      gaps.add('Preview data is missing');
    }

    switch (kind) {
      case GeneratedArtifactKind.excel:
      case GeneratedArtifactKind.csv:
        if (count > 0) {
          gates.add(
            kind == GeneratedArtifactKind.excel
                ? 'Workbook sheets packaged'
                : 'Dataset rows packaged',
          );
        } else {
          gaps.add('No tabular output was packaged');
        }
        if (previewRows.length >= 2) {
          gates.add('Header and data rows detected');
        } else {
          gaps.add('Tabular output needs at least one data row');
        }
      case GeneratedArtifactKind.powerPoint:
        if (count >= 3) {
          gates.add('Deck structure present');
        } else {
          gaps.add('Deck needs title, agenda, and content slides');
        }
        if (_metadataStringList(metadata, 'slideFamilies').isNotEmpty) {
          gates.add('Slide families classified');
        }
        if (_metadataBool(metadata, 'hasCustomerReadyDeck')) {
          gates.add('Stakeholder review deck flow');
        }
      case GeneratedArtifactKind.docx:
      case GeneratedArtifactKind.pdf:
        final sectionCount =
            _metadataInt(metadata, 'reportSectionCount') ??
            _metadataInt(metadata, 'sectionCount') ??
            document.sections.length;
        if (sectionCount >= 3) {
          gates.add('Report structure present');
        } else {
          gaps.add('Report needs more structured sections');
        }
        if (document.assumptions.isNotEmpty ||
            (_metadataInt(metadata, 'assumptionCount') ?? 0) > 0) {
          gates.add('Assumptions captured');
        } else {
          gaps.add('Assumptions are missing');
        }
        if (document.citations.isNotEmpty ||
            (_metadataInt(metadata, 'citationCount') ?? 0) > 0) {
          gates.add('Evidence captured');
        } else {
          gaps.add('Evidence or sources are missing');
        }
        if (_metadataBool(metadata, 'hasCustomerReadyReport') ||
            _metadataBool(metadata, 'hasCustomerReadyPdf')) {
          gates.add('Customer handoff package');
        }
      case GeneratedArtifactKind.diagram:
        if ((_metadataInt(metadata, 'nodeCount') ?? 0) > 0 &&
            (_metadataInt(metadata, 'edgeCount') ?? 0) > 0) {
          gates.add('Topology graph generated');
        } else {
          gaps.add('Topology needs nodes and links');
        }
        if ((_metadataInt(metadata, 'assumptionCount') ?? 0) > 0) {
          gates.add('Topology assumptions captured');
        } else {
          gaps.add('Topology assumptions are missing');
        }
        if (_metadataBool(metadata, 'hasCustomerReadyTopology')) {
          gates.add('Architecture review topology');
        }
      case GeneratedArtifactKind.chart:
        if ((_metadataInt(metadata, 'chartCount') ?? count) > 0) {
          gates.add('Chart panels generated');
        } else {
          gaps.add('Chart pack needs at least one chart');
        }
        if ((_metadataInt(metadata, 'pointCount') ?? 0) > 0) {
          gates.add('Data points detected');
        } else {
          gaps.add('Chart pack needs numeric data points');
        }
        if (_metadataBool(metadata, 'hasCustomerReadyChartPack')) {
          gates.add('Stakeholder chart pack');
        }
      case GeneratedArtifactKind.json:
        gates.add('Structured data artifact');
        if (byteSize < 2) gaps.add('JSON payload is empty');
      case GeneratedArtifactKind.markdown:
      case GeneratedArtifactKind.report:
        if (document.summary.trim().isNotEmpty) {
          gates.add('Document summary present');
        } else {
          gaps.add('Document summary is missing');
        }
    }

    final score = _scoreFor(
      status: status,
      gateCount: gates.length,
      gapCount: gaps.length,
    );
    final customerReady =
        status == GeneratedArtifactStatus.ready &&
        gaps.isEmpty &&
        _hasRendererReadySignal(metadata, kind);
    final qualityStatus = customerReady
        ? 'Customer ready'
        : status == GeneratedArtifactStatus.failed
        ? 'Failed'
        : status == GeneratedArtifactStatus.fallback
        ? 'Fallback'
        : gaps.any(
            (gap) =>
                gap.toLowerCase().contains('evidence') ||
                gap.toLowerCase().contains('source'),
          )
        ? 'Needs evidence'
        : gaps.isNotEmpty
        ? 'Needs input'
        : 'Ready for review';

    return {
      'qualityStatus': qualityStatus,
      'qualityScore': score,
      'qualityGates': gates.toList(growable: false),
      'qualityGateCount': gates.length,
      'qualityGaps': gaps.toList(growable: false),
      'qualityGapCount': gaps.length,
      'qualityNextAction': _nextActionFor(qualityStatus, gaps),
      'hasCustomerReadyArtifact': customerReady,
    };
  }

  bool _needsPreview(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.csv ||
      GeneratedArtifactKind.powerPoint ||
      GeneratedArtifactKind.docx ||
      GeneratedArtifactKind.pdf ||
      GeneratedArtifactKind.diagram ||
      GeneratedArtifactKind.chart => true,
      _ => false,
    };
  }

  int _scoreFor({
    required GeneratedArtifactStatus status,
    required int gateCount,
    required int gapCount,
  }) {
    if (status == GeneratedArtifactStatus.failed) return 0;
    final base = status == GeneratedArtifactStatus.fallback ? 65 : 72;
    final score = base + (gateCount * 4) - (gapCount * 12);
    return score.clamp(0, 100);
  }

  bool _hasRendererReadySignal(
    Map<String, Object?> metadata,
    GeneratedArtifactKind kind,
  ) {
    final keys = switch (kind) {
      GeneratedArtifactKind.powerPoint => const [
        'hasCustomerReadyDeck',
        'hasCustomerReadyStructure',
      ],
      GeneratedArtifactKind.docx => const [
        'hasCustomerReadyReport',
        'hasCustomerReadyPackage',
      ],
      GeneratedArtifactKind.pdf => const [
        'hasCustomerReadyPdf',
        'hasCustomerReadyPackage',
      ],
      GeneratedArtifactKind.diagram => const ['hasCustomerReadyTopology'],
      GeneratedArtifactKind.chart => const ['hasCustomerReadyChartPack'],
      GeneratedArtifactKind.excel => const [
        'hasPoeBudget',
        'hasWanThroughput',
        'hasCandidateValidation',
      ],
      _ => const <String>[],
    };
    if (keys.isEmpty) return true;
    return keys.any((key) => _metadataBool(metadata, key));
  }

  String _nextActionFor(String status, Set<String> gaps) {
    if (status == 'Customer ready') return 'Ready for customer handoff.';
    if (status == 'Fallback') return 'Review fallback format before sharing.';
    if (status == 'Failed') return 'Regenerate or choose another format.';
    if (gaps.isEmpty) return 'Review artifact before customer handoff.';
    final first = gaps.first;
    return 'Resolve: $first';
  }

  int? _metadataInt(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  bool _metadataBool(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == 'yes' || text == '1';
  }

  List<String> _metadataStringList(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const [];
    return text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
