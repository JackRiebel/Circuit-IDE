import 'dart:convert';

class ChartArtifactInspection {
  final bool hasSvgRoot;
  final bool hasClosingSvg;
  final bool hasViewBox;
  final bool hasTitle;
  final bool hasDescription;
  final bool hasCircuitMetadata;
  final bool hasChartPackGroup;
  final bool hasChartSummaryPanel;
  final bool hasRiskLegend;
  final bool hasExecutiveInsights;
  final bool hasValidationGates;
  final bool hasRecommendedActions;
  final bool hasDecisionMatrix;
  final bool hasDataQualityPanel;
  final bool hasThresholdGuidance;
  final int chartCount;
  final int pointCount;
  final int noteCount;
  final int insightCount;
  final int validationGateCount;
  final int recommendedActionCount;
  final int decisionActionCount;
  final int criticalDecisionCount;
  final int dataQualityItemCount;
  final int thresholdGuidanceCount;
  final int highRiskCount;
  final int mediumRiskCount;
  final int lowRiskCount;
  final int sourceTableCount;
  final int citationCount;
  final int assumptionCount;
  final bool hasPoeSignal;
  final bool hasWanSignal;
  final bool hasLifecycleSignal;
  final bool hasComparisonSignal;
  final bool hasCostSignal;
  final bool hasRoadmapSignal;
  final bool hasSourceEvidence;
  final bool hasAssumptions;
  final String? title;
  final List<String> chartKinds;
  final List<String> chartTitles;

  const ChartArtifactInspection({
    required this.hasSvgRoot,
    required this.hasClosingSvg,
    required this.hasViewBox,
    required this.hasTitle,
    required this.hasDescription,
    required this.hasCircuitMetadata,
    required this.hasChartPackGroup,
    required this.hasChartSummaryPanel,
    required this.hasRiskLegend,
    required this.hasExecutiveInsights,
    required this.hasValidationGates,
    required this.hasRecommendedActions,
    required this.hasDecisionMatrix,
    required this.hasDataQualityPanel,
    required this.hasThresholdGuidance,
    required this.chartCount,
    required this.pointCount,
    required this.noteCount,
    required this.insightCount,
    required this.validationGateCount,
    required this.recommendedActionCount,
    required this.decisionActionCount,
    required this.criticalDecisionCount,
    required this.dataQualityItemCount,
    required this.thresholdGuidanceCount,
    required this.highRiskCount,
    required this.mediumRiskCount,
    required this.lowRiskCount,
    required this.sourceTableCount,
    required this.citationCount,
    required this.assumptionCount,
    required this.hasPoeSignal,
    required this.hasWanSignal,
    required this.hasLifecycleSignal,
    required this.hasComparisonSignal,
    required this.hasCostSignal,
    required this.hasRoadmapSignal,
    required this.hasSourceEvidence,
    required this.hasAssumptions,
    required this.title,
    required this.chartKinds,
    required this.chartTitles,
  });

  bool get isStructurallyValid =>
      hasSvgRoot &&
      hasClosingSvg &&
      hasViewBox &&
      hasTitle &&
      hasDescription &&
      hasCircuitMetadata &&
      hasChartPackGroup &&
      hasChartSummaryPanel &&
      hasExecutiveInsights &&
      hasValidationGates &&
      hasRecommendedActions &&
      hasDecisionMatrix &&
      hasDataQualityPanel &&
      hasThresholdGuidance &&
      chartCount > 0 &&
      pointCount > 0;

  bool get hasEnterpriseChartPackStructure =>
      isStructurallyValid &&
      hasRiskLegend &&
      hasExecutiveInsights &&
      hasValidationGates &&
      hasRecommendedActions &&
      hasDecisionMatrix &&
      hasDataQualityPanel &&
      hasThresholdGuidance &&
      chartKinds.toSet().length >= 2 &&
      noteCount > 0;

  bool containsKind(String value) =>
      chartKinds.any((kind) => kind.toLowerCase() == value.toLowerCase());
}

class ChartArtifactInspector {
  const ChartArtifactInspector();

  ChartArtifactInspection inspect(List<int> bytes) {
    final svg = utf8.decode(bytes, allowMalformed: true);
    final metadata = _metadata(svg);
    final chartKinds = RegExp(r'data-chart-kind="([^"]+)"')
        .allMatches(svg)
        .map((match) => _xmlDecode(match.group(1) ?? ''))
        .toList(growable: false);
    final chartTitles = RegExp(r'data-chart-title="([^"]+)"')
        .allMatches(svg)
        .map((match) => _xmlDecode(match.group(1) ?? ''))
        .toList(growable: false);
    final chartCount =
        _metadataInt(metadata, 'chartCount') ??
        RegExp(r'class="chart-panel"').allMatches(svg).length;
    final pointCount =
        _metadataInt(metadata, 'pointCount') ??
        RegExp(r'class="chart-point"').allMatches(svg).length;
    final highRiskCount = _metadataInt(metadata, 'highRiskCount') ?? 0;
    final mediumRiskCount = _metadataInt(metadata, 'mediumRiskCount') ?? 0;
    final lowRiskCount = _metadataInt(metadata, 'lowRiskCount') ?? 0;
    final insightCount =
        _metadataInt(metadata, 'insightCount') ??
        RegExp(r'class="chart-insight"').allMatches(svg).length;
    final validationGateCount =
        _metadataInt(metadata, 'validationGateCount') ??
        _dataInt(svg, 'data-validation-gate-count') ??
        0;
    final recommendedActionCount =
        _metadataInt(metadata, 'recommendedActionCount') ??
        _dataInt(svg, 'data-recommended-action-count') ??
        0;
    final decisionActionCount =
        _metadataInt(metadata, 'decisionActionCount') ??
        _dataInt(svg, 'data-decision-action-count') ??
        0;
    final criticalDecisionCount =
        _metadataInt(metadata, 'criticalDecisionCount') ??
        _dataInt(svg, 'data-critical-decision-count') ??
        0;
    final dataQualityItemCount =
        _metadataInt(metadata, 'dataQualityItemCount') ??
        _dataInt(svg, 'data-data-quality-item-count') ??
        0;
    final thresholdGuidanceCount =
        _metadataInt(metadata, 'thresholdGuidanceCount') ??
        _dataInt(svg, 'data-threshold-guidance-count') ??
        0;

    return ChartArtifactInspection(
      hasSvgRoot: RegExp(r'^<svg\b').hasMatch(svg.trimLeft()),
      hasClosingSvg: svg.trimRight().endsWith('</svg>'),
      hasViewBox: RegExp(r'\bviewBox="[^"]+"').hasMatch(svg),
      hasTitle: _firstElementText(svg, 'title')?.trim().isNotEmpty == true,
      hasDescription: _firstElementText(svg, 'desc')?.trim().isNotEmpty == true,
      hasCircuitMetadata:
          metadata['generator'] == 'CircuitCode' &&
          metadata['artifact'] == 'chart_pack',
      hasChartPackGroup: svg.contains('id="chart-pack"'),
      hasChartSummaryPanel: svg.contains('id="chart-summary"'),
      hasRiskLegend: svg.contains('id="chart-risk-legend"'),
      hasExecutiveInsights: svg.contains('id="chart-executive-insights"'),
      hasValidationGates: svg.contains('id="chart-validation-gates"'),
      hasRecommendedActions: svg.contains('id="chart-recommended-actions"'),
      hasDecisionMatrix: svg.contains('id="chart-decision-matrix"'),
      hasDataQualityPanel: svg.contains('id="chart-data-quality"'),
      hasThresholdGuidance: svg.contains('id="chart-threshold-guidance"'),
      chartCount: chartCount,
      pointCount: pointCount,
      noteCount: RegExp(r'class="chart-note"').allMatches(svg).length,
      insightCount: insightCount,
      validationGateCount: validationGateCount,
      recommendedActionCount: recommendedActionCount,
      decisionActionCount: decisionActionCount,
      criticalDecisionCount: criticalDecisionCount,
      dataQualityItemCount: dataQualityItemCount,
      thresholdGuidanceCount: thresholdGuidanceCount,
      highRiskCount: highRiskCount,
      mediumRiskCount: mediumRiskCount,
      lowRiskCount: lowRiskCount,
      sourceTableCount: _metadataInt(metadata, 'sourceTableCount') ?? 0,
      citationCount: _metadataInt(metadata, 'citationCount') ?? 0,
      assumptionCount: _metadataInt(metadata, 'assumptionCount') ?? 0,
      hasPoeSignal: metadata['hasPoe'] == true,
      hasWanSignal: metadata['hasWan'] == true,
      hasLifecycleSignal: metadata['hasLifecycle'] == true,
      hasComparisonSignal: metadata['hasComparison'] == true,
      hasCostSignal: metadata['hasCost'] == true,
      hasRoadmapSignal: metadata['hasRoadmap'] == true,
      hasSourceEvidence: metadata['hasSourceEvidence'] == true,
      hasAssumptions: metadata['hasAssumptions'] == true,
      title: _firstElementText(svg, 'title'),
      chartKinds: chartKinds,
      chartTitles: chartTitles,
    );
  }

  static Map<String, Object?> _metadata(String svg) {
    final raw = _firstElementText(svg, 'metadata');
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(_xmlDecode(raw));
      return decoded is Map<String, Object?> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  static int? _metadataInt(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    return value is int ? value : int.tryParse(value?.toString() ?? '');
  }

  static int? _dataInt(String svg, String attribute) {
    final match = RegExp('$attribute="(\\d+)"').firstMatch(svg);
    return int.tryParse(match?.group(1) ?? '');
  }

  static String? _firstElementText(String svg, String element) {
    final match = RegExp(
      '<$element[^>]*>([\\s\\S]*?)</$element>',
      caseSensitive: false,
    ).firstMatch(svg);
    final value = match?.group(1);
    return value == null ? null : _xmlDecode(value);
  }

  static String _xmlDecode(String value) => value
      .replaceAll('&quot;', '"')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&');
}
