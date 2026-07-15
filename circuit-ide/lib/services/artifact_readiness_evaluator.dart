import '../models/artifact_document.dart';
import '../models/generated_artifact.dart';
import 'artifact_contract.dart';

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
    List<ArtifactContractField> contractFields = const [],
  }) {
    final gaps = <String>{
      ..._metadataStringList(metadata, 'validationGaps'),
      ..._metadataStringList(metadata, 'evidenceGaps'),
    };
    final gates = <String>{};
    for (final field in contractFields) {
      final present = _hasContractField(field, document, metadata);
      if (present) {
        gates.add('Contract: ${field.label}');
      } else {
        gaps.add(_unknownContractField(field));
      }
    }

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

    _applyVisualPreviewQuality(
      kind: kind,
      metadata: metadata,
      gates: gates,
      gaps: gaps,
    );

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
        if (kind == GeneratedArtifactKind.excel &&
            _metadataBool(metadata, 'workbookSheetsTruncated')) {
          gaps.add('Workbook input exceeds the generated sheet limit');
        }
        if (kind == GeneratedArtifactKind.excel &&
            _metadataBool(metadata, 'workbookRowHeightsAdjusted')) {
          gates.add('Wrapped workbook rows have explicit height capacity');
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
      case GeneratedArtifactKind.html:
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

  void _applyVisualPreviewQuality({
    required GeneratedArtifactKind kind,
    required Map<String, Object?> metadata,
    required Set<String> gates,
    required Set<String> gaps,
  }) {
    if (kind == GeneratedArtifactKind.powerPoint) {
      _applyPowerPointVisualPreviewQuality(
        metadata: metadata,
        gates: gates,
        gaps: gaps,
      );
      return;
    }
    if (kind == GeneratedArtifactKind.docx ||
        kind == GeneratedArtifactKind.pdf ||
        kind == GeneratedArtifactKind.excel) {
      _applyStructuralVisualPreviewQuality(
        kind: kind,
        metadata: metadata,
        gates: gates,
        gaps: gaps,
      );
    }
  }

  void _applyPowerPointVisualPreviewQuality({
    required Map<String, Object?> metadata,
    required Set<String> gates,
    required Set<String> gaps,
  }) {
    if (_metadataString(metadata, 'pptxVisualPreviewRenderer').isEmpty) {
      gaps.add('PowerPoint visual preview is missing');
      return;
    }
    final titleOverflow = _metadataBool(
      metadata,
      'pptxVisualPreviewHasTitleOverflow',
    );
    final contentOverflow = _metadataBool(
      metadata,
      'pptxVisualPreviewHasContentOverflow',
    );
    if (titleOverflow) {
      gaps.add('PowerPoint visual preview title overflows its review frame');
    }
    if (contentOverflow) {
      gaps.add('PowerPoint visual preview content overflows its review frame');
    }
    if (!titleOverflow && !contentOverflow) {
      gates.add('PowerPoint visual preview geometry passed');
    }
  }

  void _applyStructuralVisualPreviewQuality({
    required GeneratedArtifactKind kind,
    required Map<String, Object?> metadata,
    required Set<String> gates,
    required Set<String> gaps,
  }) {
    final label = switch (kind) {
      GeneratedArtifactKind.docx => 'Word report',
      GeneratedArtifactKind.pdf => 'PDF report',
      GeneratedArtifactKind.excel => 'Excel workbook',
      _ => 'Artifact',
    };
    if (_metadataString(metadata, 'artifactVisualPreviewRenderer').isEmpty) {
      gaps.add('$label structural visual preview is missing');
      return;
    }
    final titleOverflow = _metadataBool(
      metadata,
      'artifactVisualPreviewHasTitleOverflow',
    );
    final contentOverflow = _metadataBool(
      metadata,
      'artifactVisualPreviewHasContentOverflow',
    );
    final tableOverflow = _metadataBool(
      metadata,
      'artifactVisualPreviewHasTableOverflow',
    );
    final rowHeightOverflow = _metadataBool(
      metadata,
      'artifactVisualPreviewHasRowHeightOverflow',
    );
    if (titleOverflow) {
      gaps.add('$label structural preview title overflows its review frame');
    }
    if (contentOverflow) {
      gaps.add('$label structural preview content overflows its review frame');
    }
    if (tableOverflow) {
      gaps.add(
        rowHeightOverflow
            ? '$label structural preview has a row beyond the supported Excel height'
            : '$label structural preview table may clip generated values',
      );
    }
    if (!titleOverflow && !contentOverflow && !tableOverflow) {
      gates.add('$label structural preview geometry passed');
    }
    // The sidecar is intentionally a deterministic structural view. Keep the
    // native macOS/Office render as a separately recorded CI/release proof
    // instead of mislabelling the SVG as a platform render.
    gates.add('$label structural review sidecar available');
  }

  bool _hasContractField(
    ArtifactContractField field,
    ArtifactDocument document,
    Map<String, Object?> metadata,
  ) {
    return switch (field) {
      ArtifactContractField.assumptions =>
        document.assumptions.isNotEmpty ||
            (_metadataInt(metadata, 'assumptionCount') ?? 0) > 0,
      ArtifactContractField.sources =>
        document.citations.isNotEmpty ||
            (_metadataInt(metadata, 'citationCount') ?? 0) > 0 ||
            (_metadataInt(metadata, 'sourceCount') ?? 0) > 0 ||
            (_metadataInt(metadata, 'sourceSheetCount') ?? 0) > 0 ||
            _metadataBool(metadata, 'hasSourceEvidence'),
      ArtifactContractField.checkedDate => _hasCheckedDate(document, metadata),
      ArtifactContractField.confidence => _hasExplicitConfidence(
        document,
        metadata,
      ),
      ArtifactContractField.topologyGraph =>
        (_metadataInt(metadata, 'nodeCount') ?? 0) > 0 &&
            (_metadataInt(metadata, 'edgeCount') ?? 0) > 0,
      ArtifactContractField.topologyCapacity =>
        _metadataBool(metadata, 'hasCapacityChecks') &&
            _metadataBool(metadata, 'hasTopologyValidationGate'),
      ArtifactContractField.reviewFindings =>
        (_metadataInt(metadata, 'architectureFindingCount') ?? 0) > 0,
      ArtifactContractField.reviewRisks =>
        (_metadataInt(metadata, 'architectureRiskCount') ?? 0) > 0,
      ArtifactContractField.reviewValidation =>
        (_metadataInt(metadata, 'architectureValidationCount') ?? 0) > 0,
      ArtifactContractField.poeBudget => _metadataBool(
        metadata,
        'hasPoeBudget',
      ),
      ArtifactContractField.wanThroughput => _metadataBool(
        metadata,
        'hasWanThroughput',
      ),
      ArtifactContractField.candidateValidation => _metadataBool(
        metadata,
        'hasCandidateValidation',
      ),
      ArtifactContractField.lifecycleDateAuthority =>
        _metadataBool(metadata, 'hasOfficialLifecycleSource') &&
            _metadataBool(metadata, 'hasCheckedDateEvidence') &&
            (_metadataInt(metadata, 'unknownLifecycleDateCount') ?? 0) == 0,
      ArtifactContractField.replacementSuitability => _metadataBool(
        metadata,
        'hasValidatedReplacementSuitability',
      ),
      ArtifactContractField.comparisonCandidates =>
        (_metadataInt(metadata, 'candidateCount') ?? 0) >= 2,
      ArtifactContractField.fitScoring =>
        (_metadataInt(metadata, 'shortlistCount') ?? 0) > 0,
      ArtifactContractField.hardGateValidation =>
        (_metadataInt(metadata, 'hardGateEvaluationCount') ?? 0) > 0 &&
            (_metadataInt(metadata, 'mustHaveComplianceCount') ?? 0) > 0,
      ArtifactContractField.businessUseCases =>
        (_metadataInt(metadata, 'businessUseCaseCount') ?? 0) > 0,
      ArtifactContractField.businessValueMetrics =>
        (_metadataInt(metadata, 'businessValueMetricCount') ?? 0) > 0,
      ArtifactContractField.chartData =>
        (_metadataInt(metadata, 'pointCount') ?? 0) > 0,
      ArtifactContractField.chartDecisionThresholds =>
        _metadataBool(metadata, 'hasThresholdGuidance') &&
            _metadataBool(metadata, 'hasDecisionMatrix'),
      ArtifactContractField.evidenceClaims =>
        (_metadataInt(metadata, 'claimCount') ?? 0) > 0,
      ArtifactContractField.claimDisposition =>
        (_metadataInt(metadata, 'claimDispositionCount') ?? 0) > 0,
    };
  }

  bool _hasCheckedDate(
    ArtifactDocument document,
    Map<String, Object?> metadata,
  ) {
    final metadataDates = [
      ..._metadataStringList(metadata, 'checkedDates'),
      metadata['checkedDate']?.toString() ?? '',
      metadata['checkedDateStatus']?.toString() ?? '',
    ];
    if (metadataDates.any(_containsConcreteDate)) return true;
    return _documentText(document).split('\n').any(_containsConcreteDate);
  }

  bool _hasExplicitConfidence(
    ArtifactDocument document,
    Map<String, Object?> metadata,
  ) {
    final metadataValue = metadata['confidence'] ?? metadata['confidenceScore'];
    if (metadataValue != null &&
        metadataValue.toString().trim().isNotEmpty &&
        metadataValue.toString().trim().toLowerCase() != 'unknown') {
      return true;
    }
    return RegExp(
      r'\bconfidence\s*(?:level\s*)?(?:is|:|-)?\s*(?:high|medium|low|validated|confirmed)\b',
      caseSensitive: false,
    ).hasMatch(_documentText(document));
  }

  bool _containsConcreteDate(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized.contains('not provided') ||
        normalized.contains('tbd') ||
        normalized.contains('needs lookup')) {
      return false;
    }
    return RegExp(
      r'\b20\d{2}[-/]\d{1,2}[-/]\d{1,2}\b|\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s+20\d{2}\b|\b\d{1,2}[-/](?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[-/]20\d{2}\b',
      caseSensitive: false,
    ).hasMatch(value);
  }

  String _documentText(ArtifactDocument document) {
    return [
      document.title,
      document.summary,
      ...document.assumptions,
      ...document.citations,
      for (final section in document.sections) ...[
        section.title,
        section.body,
        ...section.bullets,
      ],
      for (final table in document.tables) ...[
        table.title,
        for (final row in table.rows) ...row,
      ],
    ].join('\n');
  }

  String _unknownContractField(ArtifactContractField field) {
    if (field == ArtifactContractField.replacementSuitability) {
      return 'Unknown ${field.label} — EoX migration hints are not final recommendations';
    }
    return 'Unknown ${field.label}';
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

  String _metadataString(Map<String, Object?> metadata, String key) =>
      metadata[key]?.toString().trim() ?? '';

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
