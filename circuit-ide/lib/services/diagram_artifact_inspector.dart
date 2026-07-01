import 'dart:convert';

class DiagramArtifactInspection {
  final bool hasSvgRoot;
  final bool hasClosingSvg;
  final bool hasViewBox;
  final bool hasTitle;
  final bool hasDescription;
  final bool hasCircuitMetadata;
  final bool hasLogicalTopologyGuidance;
  final bool hasTopologySummaryPanel;
  final bool hasInventoryPanel;
  final bool hasDesignZones;
  final bool hasLinkSchedule;
  final bool hasReadinessScorecard;
  final bool hasCapacityPanel;
  final bool hasValidationChecklist;
  final bool hasAssumptionsPanel;
  final int nodeCount;
  final int edgeCount;
  final int tierCount;
  final int assumptionCount;
  final int designZoneCount;
  final int linkScheduleCount;
  final int readinessItemCount;
  final int capacityItemCount;
  final int siteCount;
  final int mdfCount;
  final int idfCount;
  final int firewallCount;
  final int coreSwitchCount;
  final int accessSwitchCount;
  final int switchCount;
  final int apCount;
  final int accessPortCount;
  final int estimatedApPowerWatts;
  final int apPortLoadPercent;
  final bool hasDualWan;
  final bool hasWarmSpare;
  final bool hasPoe;
  final bool hasUpoe;
  final bool hasMultigig;
  final bool hasWifi7;
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
    required this.hasTopologySummaryPanel,
    required this.hasInventoryPanel,
    required this.hasDesignZones,
    required this.hasLinkSchedule,
    required this.hasReadinessScorecard,
    required this.hasCapacityPanel,
    required this.hasValidationChecklist,
    required this.hasAssumptionsPanel,
    required this.nodeCount,
    required this.edgeCount,
    required this.tierCount,
    required this.assumptionCount,
    required this.designZoneCount,
    required this.linkScheduleCount,
    required this.readinessItemCount,
    required this.capacityItemCount,
    required this.siteCount,
    required this.mdfCount,
    required this.idfCount,
    required this.firewallCount,
    required this.coreSwitchCount,
    required this.accessSwitchCount,
    required this.switchCount,
    required this.apCount,
    required this.accessPortCount,
    required this.estimatedApPowerWatts,
    required this.apPortLoadPercent,
    required this.hasDualWan,
    required this.hasWarmSpare,
    required this.hasPoe,
    required this.hasUpoe,
    required this.hasMultigig,
    required this.hasWifi7,
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
      hasTopologySummaryPanel &&
      hasInventoryPanel &&
      hasDesignZones &&
      hasLinkSchedule &&
      hasReadinessScorecard &&
      hasCapacityPanel &&
      hasValidationChecklist &&
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
    final designZoneCount =
        _metadataInt(metadata, 'designZoneCount') ??
        _dataInt(svg, 'data-zone-count') ??
        0;
    final linkScheduleCount =
        _metadataInt(metadata, 'linkScheduleCount') ??
        _dataInt(svg, 'data-link-schedule-count') ??
        0;
    final readinessItemCount =
        _metadataInt(metadata, 'readinessItemCount') ??
        _dataInt(svg, 'data-readiness-item-count') ??
        0;
    final capacityItemCount =
        _metadataInt(metadata, 'capacityItemCount') ??
        _dataInt(svg, 'data-capacity-item-count') ??
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
      hasTopologySummaryPanel: svg.contains('id="topology-summary"'),
      hasInventoryPanel: svg.contains('id="topology-inventory"'),
      hasDesignZones: svg.contains('id="topology-design-zones"'),
      hasLinkSchedule: svg.contains('id="topology-link-schedule"'),
      hasReadinessScorecard: svg.contains('id="topology-readiness"'),
      hasCapacityPanel: svg.contains('id="topology-capacity"'),
      hasValidationChecklist: svg.contains('id="topology-validation"'),
      hasAssumptionsPanel:
          svg.contains('id="topology-assumptions"') ||
          svg.contains('Assumptions'),
      nodeCount: nodeCount,
      edgeCount: edgeCount,
      tierCount: tierCount,
      assumptionCount: assumptionCount,
      designZoneCount: designZoneCount,
      linkScheduleCount: linkScheduleCount,
      readinessItemCount: readinessItemCount,
      capacityItemCount: capacityItemCount,
      siteCount: _metadataInt(metadata, 'siteCount') ?? 0,
      mdfCount: _metadataInt(metadata, 'mdfCount') ?? 0,
      idfCount: _metadataInt(metadata, 'idfCount') ?? 0,
      firewallCount: _metadataInt(metadata, 'firewallCount') ?? 0,
      coreSwitchCount: _metadataInt(metadata, 'coreSwitchCount') ?? 0,
      accessSwitchCount: _metadataInt(metadata, 'accessSwitchCount') ?? 0,
      switchCount: _metadataInt(metadata, 'switchCount') ?? 0,
      apCount: _metadataInt(metadata, 'apCount') ?? 0,
      accessPortCount:
          _metadataInt(metadata, 'accessPortCount') ??
          _dataInt(svg, 'data-access-port-count') ??
          0,
      estimatedApPowerWatts:
          _metadataInt(metadata, 'estimatedApPowerWatts') ??
          _dataInt(svg, 'data-estimated-ap-power-watts') ??
          0,
      apPortLoadPercent:
          _metadataInt(metadata, 'apPortLoadPercent') ??
          _dataInt(svg, 'data-ap-port-load-percent') ??
          0,
      hasDualWan: metadata['hasDualWan'] == true,
      hasWarmSpare: metadata['hasWarmSpare'] == true,
      hasPoe: metadata['hasPoe'] == true,
      hasUpoe: metadata['hasUpoe'] == true,
      hasMultigig: metadata['hasMultigig'] == true,
      hasWifi7: metadata['hasWifi7'] == true,
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
