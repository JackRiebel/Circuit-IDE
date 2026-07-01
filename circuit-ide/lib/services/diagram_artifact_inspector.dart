import 'dart:convert';

class DiagramArtifactInspection {
  final bool hasSvgRoot;
  final bool hasClosingSvg;
  final bool hasViewBox;
  final bool hasTitle;
  final bool hasDescription;
  final bool hasCircuitMetadata;
  final bool hasLogicalTopologyGuidance;
  final bool hasAssumptionsPanel;
  final int nodeCount;
  final int edgeCount;
  final int tierCount;
  final int assumptionCount;
  final String? title;
  final List<String> tierLabels;
  final List<String> deviceTokens;

  const DiagramArtifactInspection({
    required this.hasSvgRoot,
    required this.hasClosingSvg,
    required this.hasViewBox,
    required this.hasTitle,
    required this.hasDescription,
    required this.hasCircuitMetadata,
    required this.hasLogicalTopologyGuidance,
    required this.hasAssumptionsPanel,
    required this.nodeCount,
    required this.edgeCount,
    required this.tierCount,
    required this.assumptionCount,
    required this.title,
    required this.tierLabels,
    required this.deviceTokens,
  });

  bool get isStructurallyValid =>
      hasSvgRoot &&
      hasClosingSvg &&
      hasViewBox &&
      hasTitle &&
      hasDescription &&
      hasCircuitMetadata &&
      nodeCount > 0;

  bool get hasEnterpriseTopologyStructure =>
      isStructurallyValid &&
      edgeCount > 0 &&
      tierCount >= 3 &&
      hasLogicalTopologyGuidance &&
      hasAssumptionsPanel;

  bool containsDeviceToken(String value) => deviceTokens.any((token) {
    final normalizedToken = token.toLowerCase();
    final normalizedValue = value.toLowerCase();
    return normalizedToken == normalizedValue ||
        normalizedToken.startsWith('$normalizedValue-');
  });
}

class DiagramArtifactInspector {
  const DiagramArtifactInspector();

  DiagramArtifactInspection inspect(List<int> bytes) {
    final svg = utf8.decode(bytes, allowMalformed: true);
    final metadata = _metadata(svg);
    final title = _firstElementText(svg, 'title');
    final tierLabels = RegExp(r'data-tier-label="([^"]+)"')
        .allMatches(svg)
        .map((match) => _xmlDecode(match.group(1) ?? ''))
        .toSet()
        .toList(growable: false);
    final deviceTokens =
        RegExp(
              r'\b(?:MX\d+[A-Z-]*|C9[235]\d{2}[A-Z0-9-]*|CW9\d{3}[A-Z0-9-]*)\b',
              caseSensitive: false,
            )
            .allMatches(svg)
            .map((match) => (match.group(0) ?? '').toUpperCase())
            .toSet()
            .toList(growable: false);

    final nodeCount =
        _metadataInt(metadata, 'nodeCount') ??
        RegExp(r'class="topology-node"').allMatches(svg).length;
    final edgeCount =
        _metadataInt(metadata, 'edgeCount') ??
        RegExp(r'class="topology-edge"').allMatches(svg).length;
    final tierCount =
        _metadataInt(metadata, 'tierCount') ??
        RegExp(r'class="topology-tier-band"').allMatches(svg).length;
    final assumptionCount =
        _metadataInt(metadata, 'assumptionCount') ??
        _dataInt(svg, 'data-assumption-count') ??
        0;

    return DiagramArtifactInspection(
      hasSvgRoot: RegExp(r'^<svg\b').hasMatch(svg.trimLeft()),
      hasClosingSvg: svg.trimRight().endsWith('</svg>'),
      hasViewBox: RegExp(r'\bviewBox="[^"]+"').hasMatch(svg),
      hasTitle: title != null && title.trim().isNotEmpty,
      hasDescription: _firstElementText(svg, 'desc')?.trim().isNotEmpty == true,
      hasCircuitMetadata:
          metadata['generator'] == 'CircuitCode' &&
          metadata['artifact'] == 'network_topology_diagram',
      hasLogicalTopologyGuidance: svg.contains('Logical topology'),
      hasAssumptionsPanel:
          svg.contains('id="topology-assumptions"') ||
          svg.contains('Assumptions'),
      nodeCount: nodeCount,
      edgeCount: edgeCount,
      tierCount: tierCount,
      assumptionCount: assumptionCount,
      title: title,
      tierLabels: tierLabels,
      deviceTokens: deviceTokens,
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

  static String? _firstElementText(String svg, String element) {
    final match = RegExp(
      '<$element[^>]*>([\\s\\S]*?)</$element>',
      caseSensitive: false,
    ).firstMatch(svg);
    final value = match?.group(1);
    return value == null ? null : _xmlDecode(value);
  }

  static int? _metadataInt(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    return value is int ? value : int.tryParse(value?.toString() ?? '');
  }

  static int? _dataInt(String svg, String attribute) {
    final value = RegExp('$attribute="(\\d+)"').firstMatch(svg)?.group(1);
    return int.tryParse(value ?? '');
  }

  static String _xmlDecode(String value) => value
      .replaceAll('&quot;', '"')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&');
}
