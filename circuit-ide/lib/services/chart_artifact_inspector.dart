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
  final int chartCount;
  final int pointCount;
  final int noteCount;
  final int highRiskCount;
  final int mediumRiskCount;
  final int lowRiskCount;
  final bool hasPoeSignal;
  final bool hasWanSignal;
  final bool hasLifecycleSignal;
  final bool hasComparisonSignal;
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
    required this.chartCount,
    required this.pointCount,
    required this.noteCount,
    required this.highRiskCount,
    required this.mediumRiskCount,
    required this.lowRiskCount,
    required this.hasPoeSignal,
    required this.hasWanSignal,
    required this.hasLifecycleSignal,
    required this.hasComparisonSignal,
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
      chartCount > 0 &&
      pointCount > 0;

  bool get hasEnterpriseChartPackStructure =>
      isStructurallyValid &&
      hasRiskLegend &&
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
      chartCount: chartCount,
      pointCount: pointCount,
      noteCount: RegExp(r'class="chart-note"').allMatches(svg).length,
      highRiskCount: highRiskCount,
      mediumRiskCount: mediumRiskCount,
      lowRiskCount: lowRiskCount,
      hasPoeSignal: metadata['hasPoe'] == true,
      hasWanSignal: metadata['hasWan'] == true,
      hasLifecycleSignal: metadata['hasLifecycle'] == true,
      hasComparisonSignal: metadata['hasComparison'] == true,
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
