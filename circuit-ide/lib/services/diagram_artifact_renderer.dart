import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/artifact_document.dart';

typedef _FailureDomainRow = ({
  String domain,
  String redundancy,
  String impact,
  String validation,
  bool ready,
});

typedef _SegmentationDomain = ({
  String name,
  String scope,
  String subnet,
  String validation,
  bool ready,
});

typedef _TopologyHandoffGate = ({
  String gate,
  String signal,
  String status,
  String ownerAction,
  bool ready,
});

class DiagramRenderResult {
  final Uint8List bytes;
  final String mermaidSource;
  final int nodeCount;
  final int edgeCount;
  final List<List<String>> previewRows;
  final Map<String, Object?> metadata;

  const DiagramRenderResult({
    required this.bytes,
    required this.mermaidSource,
    required this.nodeCount,
    required this.edgeCount,
    required this.previewRows,
    this.metadata = const {},
  });
}

class DiagramArtifactRenderer {
  const DiagramArtifactRenderer();

  DiagramRenderResult render({
    required ArtifactDocument document,
    required String content,
  }) {
    final resolvedGraph = _resolvedGraphFor(
      document: document,
      content: content,
    );
    final assumptions = document.assumptions.isNotEmpty
        ? document.assumptions
        : _extractAssumptions(content);
    final profile = _profileFrom(content, document);
    final tiers = _layoutTiers(
      resolvedGraph.nodes.values.toList(growable: false),
    );
    final readinessItems = _readinessItems(profile, assumptions);
    final capacityItems = _capacityItems(profile);
    final linkSchedule = _linkSchedule(resolvedGraph, profile);
    final advisories = _designAdvisories(profile, assumptions);
    final failureDomains = _failureDomainRows(profile);
    final metadata = <String, Object?>{
      ..._metadataFor(
        graph: resolvedGraph,
        tiers: tiers,
        assumptions: assumptions,
        citationCount: document.citations.length,
        profile: profile,
        readinessItems: readinessItems,
        capacityItems: capacityItems,
        linkSchedule: linkSchedule,
        advisories: advisories,
        failureDomains: failureDomains,
      ),
      'hasAccessibleSvgTitle': true,
      'hasAccessibleSvgDescription': true,
    };
    final svg = _svgFor(
      resolvedGraph,
      title: document.title,
      assumptions: assumptions,
      citationCount: document.citations.length,
      profile: profile,
    );
    return DiagramRenderResult(
      bytes: Uint8List.fromList(utf8.encode(svg)),
      mermaidSource: _mermaidFor(resolvedGraph),
      nodeCount: resolvedGraph.nodes.length,
      edgeCount: resolvedGraph.edges.length,
      previewRows: _previewRowsFor(
        resolvedGraph,
        profile,
        readinessItems,
        capacityItems,
        advisories,
        failureDomains,
      ),
      metadata: metadata,
    );
  }

  String mermaidSourceFor({
    required ArtifactDocument document,
    required String content,
  }) {
    return _mermaidFor(_resolvedGraphFor(document: document, content: content));
  }

  _DiagramGraph _resolvedGraphFor({
    required ArtifactDocument document,
    required String content,
  }) {
    final graph = _graphFromMermaid(content);
    final proseGraph = graph.nodes.isEmpty || graph.edges.isEmpty
        ? _graphFromNetworkText(content)
        : const _DiagramGraph(nodes: {}, edges: []);
    final networkGraph = proseGraph.nodes.isEmpty ? graph : proseGraph;
    return networkGraph.nodes.isEmpty
        ? _graphFromDocument(document)
        : networkGraph;
  }

  String _mermaidFor(_DiagramGraph graph) {
    final buffer = StringBuffer('flowchart LR\n');
    final nodes = graph.nodes.values.toList(growable: false);
    for (final node in nodes) {
      buffer.writeln('  ${_mermaidId(node.id)}["${_mermaidText(node.label)}"]');
    }
    for (final edge in graph.edges) {
      final label = edge.label.trim();
      final connector = label.isEmpty
          ? '-->'
          : '-->|${_mermaidText(label).replaceAll('|', '/')}|';
      buffer.writeln(
        '  ${_mermaidId(edge.from)} $connector ${_mermaidId(edge.to)}',
      );
    }
    if (nodes.isEmpty) {
      buffer.writeln('  topology["Topology"]');
    }
    return buffer.toString().trimRight();
  }

  String _mermaidId(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final collapsed = sanitized.replaceAll(RegExp(r'_+'), '_');
    final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
    final id = trimmed.isEmpty ? 'node' : trimmed;
    return RegExp(r'^[A-Za-z_]').hasMatch(id) ? id : 'node_$id';
  }

  String _mermaidText(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '#quot;')
        .replaceAll('\n', ' ')
        .trim();
  }

  Map<String, Object?> _metadataFor({
    required _DiagramGraph graph,
    required Map<_DiagramNodeRole, List<_DiagramNode>> tiers,
    required List<String> assumptions,
    required int citationCount,
    required _TopologyProfile profile,
    required List<({String check, String state, bool ready})> readinessItems,
    required List<({String metric, String value, String guidance, bool ready})>
    capacityItems,
    required List<({String from, String to, String link, String validation})>
    linkSchedule,
    required List<({String topic, String guidance, bool critical})> advisories,
    required List<_FailureDomainRow> failureDomains,
  }) {
    final readinessSignalLabels = _readinessSignalLabels(readinessItems);
    final validationGapLabels = _validationGapLabels(
      readinessItems,
      capacityItems,
      assumptions,
      failureDomains,
    );
    final designZoneLabels = _designZoneLabels(tiers);
    final topologyRiskFlags = _topologyRiskFlagsFor(
      profile: profile,
      graph: graph,
      assumptions: assumptions,
      validationGaps: validationGapLabels,
      failureDomains: failureDomains,
    );
    final topologyReviewChecklist = _topologyReviewChecklistFor(
      profile: profile,
      validationGaps: validationGapLabels,
      failureDomains: failureDomains,
    );
    final topologyHandoffActions = _topologyHandoffActionsFor(
      profile: profile,
      validationGaps: validationGapLabels,
      topologyRiskFlags: topologyRiskFlags,
    );
    final topologyReadinessScore = _topologyReadinessScoreFor(
      readinessItems: readinessItems,
      validationGaps: validationGapLabels,
      topologyRiskFlags: topologyRiskFlags,
      failureDomains: failureDomains,
      graph: graph,
      assumptions: assumptions,
    );
    final topologyQualityChecklist = _topologyQualityChecklistFor(
      profile: profile,
      graph: graph,
      tiers: tiers,
      assumptions: assumptions,
      readinessItems: readinessItems,
      capacityItems: capacityItems,
      linkSchedule: linkSchedule,
      advisories: advisories,
      failureDomains: failureDomains,
    );
    final topologyVisualVerificationChecklist =
        _topologyVisualVerificationChecklistFor(profile);
    final topologyEvidencePolicy = _topologyEvidencePolicyFor(profile);
    final readySegmentationCount = profile.segmentationDomains
        .where((domain) => domain.ready)
        .length;
    final topologyPublishingMetadata = _topologyPublishingMetadataFor(
      topologyReadinessScore,
      validationGapLabels,
      topologyRiskFlags,
    );
    final topologyQualityStatus = _topologyQualityStatusFor(
      topologyReadinessScore,
      validationGapLabels,
      topologyRiskFlags,
    );
    final topologyReadinessLevel = _topologyReadinessLevelFor(
      topologyReadinessScore,
      topologyRiskFlags,
    );
    final externalHandoffManifest = _externalHandoffManifestFor(
      profile: profile,
      assumptions: assumptions,
      citationCount: citationCount,
      topologyType: _topologyTypeFor(profile),
      readinessLevel: topologyReadinessLevel,
      qualityStatus: topologyQualityStatus,
      validationGaps: validationGapLabels,
      topologyRiskFlags: topologyRiskFlags,
    );
    final handoffReadinessMatrix = _topologyHandoffReadinessMatrixFor(
      profile: profile,
      assumptions: assumptions,
      citationCount: citationCount,
      topologyReadinessLevel: topologyReadinessLevel,
      validationGaps: validationGapLabels,
      topologyRiskFlags: topologyRiskFlags,
      failureDomains: failureDomains,
    );
    final customerReady =
        validationGapLabels.isEmpty &&
        graph.nodes.isNotEmpty &&
        graph.edges.isNotEmpty &&
        assumptions.isNotEmpty;
    return {
      'generator': 'CircuitCode',
      'artifact': 'network_topology_diagram',
      'topologySpecVersion': '1.0',
      'editableSourceFormat': 'Mermaid',
      'hasEditableDiagramSource': true,
      'topologyType': _topologyTypeFor(profile),
      'handoffStatus': customerReady
          ? 'Ready for architecture review'
          : 'Draft - validate topology inputs',
      'resiliencyModel': profile.resiliencyLabel,
      'nodeCount': graph.nodes.length,
      'edgeCount': graph.edges.length,
      'tierCount': tiers.length,
      'designZones': designZoneLabels,
      'assumptionCount': assumptions.length,
      'citationCount': citationCount,
      'siteCount': profile.siteCount,
      'mdfCount': profile.mdfCount,
      'idfCount': profile.idfCount,
      'firewallCount': profile.firewallCount,
      'coreSwitchCount': profile.coreSwitchCount,
      'accessSwitchCount': profile.accessSwitchCount,
      'switchCount': profile.switchCount,
      'apCount': profile.apCount,
      'accessPortCount': profile.accessPortCount,
      'estimatedApPowerWatts': profile.estimatedApPowerWatts,
      'apPortLoadPercent': profile.apPortLoadPercent,
      'hasDualWan': profile.hasDualWan,
      'hasWarmSpare': profile.hasWarmSpare,
      'hasPoe': profile.hasPoe,
      'hasUpoe': profile.hasUpoe,
      'hasMultigig': profile.hasMultigig,
      'hasWifi7': profile.hasWifi7,
      'hasSegmentationSignal': profile.hasSegmentationSignal,
      'hasSegmentationPlan': profile.segmentationDomains.isNotEmpty,
      'hasSegmentationReview': profile.segmentationDomains.isNotEmpty,
      'segmentationDomainCount': profile.segmentationDomains.length,
      'readySegmentationDomainCount': readySegmentationCount,
      'segmentationDomains': [
        for (final domain in profile.segmentationDomains)
          {
            'name': domain.name,
            'scope': domain.scope,
            'subnet': domain.subnet,
            'validation': domain.validation,
            'ready': domain.ready,
          },
      ],
      'readinessSignals': readinessSignalLabels,
      'readyCheckCount': readinessItems.where((item) => item.ready).length,
      'readinessItemCount': readinessItems.length,
      'validationGaps': validationGapLabels,
      'validationGapCount': validationGapLabels.length,
      'topologyReviewChecklist': topologyReviewChecklist,
      'topologyReviewChecklistCount': topologyReviewChecklist.length,
      'topologyHandoffActions': topologyHandoffActions,
      'topologyHandoffActionCount': topologyHandoffActions.length,
      'topologyRiskFlags': topologyRiskFlags,
      'topologyRiskFlagCount': topologyRiskFlags.length,
      'topologyReadinessScore': topologyReadinessScore,
      'topologyReadinessLevel': topologyReadinessLevel,
      'topologyQualityManifestVersion': '1.0',
      'topologyQualityStatus': topologyQualityStatus,
      'topologyQualityChecklist': topologyQualityChecklist,
      'topologyQualityChecklistCount': topologyQualityChecklist.length,
      'topologyVisualVerificationChecklist':
          topologyVisualVerificationChecklist,
      'topologyVisualVerificationChecklistCount':
          topologyVisualVerificationChecklist.length,
      'topologyEvidencePolicy': topologyEvidencePolicy,
      'topologyEvidencePolicyCount': topologyEvidencePolicy.length,
      'topologyPublishingMetadata': topologyPublishingMetadata,
      'topologyPublishingMetadataCount': topologyPublishingMetadata.length,
      'externalHandoffManifest': externalHandoffManifest,
      'externalHandoffManifestCount': externalHandoffManifest.length,
      'hasExternalHandoffManifest': externalHandoffManifest.isNotEmpty,
      'topologyHandoffReadinessMatrix': [
        for (final gate in handoffReadinessMatrix)
          {
            'gate': gate.gate,
            'signal': gate.signal,
            'status': gate.status,
            'ownerAction': gate.ownerAction,
            'ready': gate.ready,
          },
      ],
      'topologyHandoffReadinessGateCount': handoffReadinessMatrix.length,
      'topologyHandoffReadinessReadyCount': handoffReadinessMatrix
          .where((gate) => gate.ready)
          .length,
      'hasTopologyHandoffReadinessMatrix': handoffReadinessMatrix.isNotEmpty,
      'capacityItemCount': capacityItems.length,
      'linkScheduleCount': linkSchedule.length,
      'advisoryCount': advisories.length,
      'failureDomainCount': failureDomains.length,
      'criticalFailureDomainCount': failureDomains
          .where((item) => !item.ready)
          .length,
      'designZoneCount': tiers.length,
      'hasCustomerReadyTopology': customerReady,
      'hasDeviceInventory': graph.nodes.isNotEmpty,
      'hasLinkSchedule': linkSchedule.isNotEmpty,
      'hasCapacityChecks': capacityItems.isNotEmpty,
      'hasReadinessScorecard': readinessItems.isNotEmpty,
      'hasTopologyQualityManifest': true,
      'hasTopologySvgMetadata': true,
      'hasEmbeddedTopologySpec': true,
      'hasTopologyEvidencePolicy': topologyEvidencePolicy.isNotEmpty,
      'hasTopologyVisualVerificationChecklist':
          topologyVisualVerificationChecklist.isNotEmpty,
      'hasTopologyValidationGate': topologyQualityChecklist.isNotEmpty,
      'hasTopologyPublishingMetadata': topologyPublishingMetadata.isNotEmpty,
      'hasRoleLegend': designZoneLabels.isNotEmpty,
      'hasPortPowerWarnings': topologyRiskFlags.any(
        (flag) =>
            flag.contains('Wi-Fi 7') ||
            flag.contains('PoE') ||
            flag.contains('power'),
      ),
      'hasDesignAdvisoryPanel': advisories.isNotEmpty,
      'hasFailureDomainReview': failureDomains.isNotEmpty,
      'hasLifecycleReplacementCaveat': advisories.any(
        (item) => item.topic == 'Lifecycle',
      ),
      'hasWifi7PowerAdvisory': advisories.any(
        (item) => item.topic == 'Wi-Fi 7 / PoE',
      ),
      'topologySpec': _topologySpecFor(
        graph: graph,
        tiers: tiers,
        assumptions: assumptions,
        citationCount: citationCount,
        profile: profile,
        readinessItems: readinessItems,
        capacityItems: capacityItems,
        linkSchedule: linkSchedule,
        advisories: advisories,
        failureDomains: failureDomains,
        validationGaps: validationGapLabels,
        topologyRiskFlags: topologyRiskFlags,
        topologyReadinessLevel: topologyReadinessLevel,
      ),
    };
  }

  Map<String, Object?> _topologySpecFor({
    required _DiagramGraph graph,
    required Map<_DiagramNodeRole, List<_DiagramNode>> tiers,
    required List<String> assumptions,
    required int citationCount,
    required _TopologyProfile profile,
    required List<({String check, String state, bool ready})> readinessItems,
    required List<({String metric, String value, String guidance, bool ready})>
    capacityItems,
    required List<({String from, String to, String link, String validation})>
    linkSchedule,
    required List<({String topic, String guidance, bool critical})> advisories,
    required List<_FailureDomainRow> failureDomains,
    required List<String> validationGaps,
    required List<String> topologyRiskFlags,
    required String topologyReadinessLevel,
  }) {
    return {
      'schema': 'circuit.networkTopologySpec',
      'version': '1.0',
      'summary': {
        'type': _topologyTypeFor(profile),
        'resiliencyModel': profile.resiliencyLabel,
        'siteCount': profile.siteCount,
        'nodeCount': graph.nodes.length,
        'edgeCount': graph.edges.length,
        'handoffStatus': validationGaps.isEmpty && assumptions.isNotEmpty
            ? 'Ready for architecture review'
            : 'Draft - validate topology inputs',
      },
      'inventory': {
        'mdfCount': profile.mdfCount,
        'idfCount': profile.idfCount,
        'firewallCount': profile.firewallCount,
        'coreSwitchCount': profile.coreSwitchCount,
        'accessSwitchCount': profile.accessSwitchCount,
        'switchCount': profile.switchCount,
        'apCount': profile.apCount,
        'accessPortCount': profile.accessPortCount,
      },
      'capabilities': {
        'dualWan': profile.hasDualWan,
        'warmSpare': profile.hasWarmSpare,
        'poe': profile.hasPoe,
        'upoe': profile.hasUpoe,
        'multigig': profile.hasMultigig,
        'wifi7': profile.hasWifi7,
        'estimatedApPowerWatts': profile.estimatedApPowerWatts,
        'apPortLoadPercent': profile.apPortLoadPercent,
      },
      'segmentation': [
        for (final domain in profile.segmentationDomains)
          {
            'name': domain.name,
            'scope': domain.scope,
            'subnet': domain.subnet,
            'validation': domain.validation,
            'ready': domain.ready,
          },
      ],
      'designZones': [
        for (final entry in tiers.entries)
          {
            'id': entry.key.name,
            'label': _tierLabel(entry.key),
            'nodeIds': [for (final node in entry.value) node.id],
          },
      ],
      'nodes': [
        for (final node in graph.nodes.values)
          {
            'id': node.id,
            'label': node.label,
            'role': node.role.name,
            'roleLabel': _roleLabel(node.role),
            'tierLabel': _tierLabel(node.role),
          },
      ],
      'links': [
        for (final link in linkSchedule)
          {
            'from': link.from,
            'fromLabel': graph.nodes[link.from]?.label ?? link.from,
            'to': link.to,
            'toLabel': graph.nodes[link.to]?.label ?? link.to,
            'label': link.link,
            'validation': link.validation,
          },
      ],
      'linkSchedule': [
        for (final link in linkSchedule)
          {
            'from': link.from,
            'to': link.to,
            'link': link.link,
            'validation': link.validation,
          },
      ],
      'capacityChecks': [
        for (final item in capacityItems)
          {
            'metric': item.metric,
            'value': item.value,
            'guidance': item.guidance,
            'ready': item.ready,
          },
      ],
      'readinessChecks': [
        for (final item in readinessItems)
          {'check': item.check, 'state': item.state, 'ready': item.ready},
      ],
      'failureDomains': [
        for (final domain in failureDomains)
          {
            'domain': domain.domain,
            'redundancy': domain.redundancy,
            'impact': domain.impact,
            'validation': domain.validation,
            'ready': domain.ready,
          },
      ],
      'handoffReadinessMatrix': [
        for (final gate in _topologyHandoffReadinessMatrixFor(
          profile: profile,
          assumptions: assumptions,
          citationCount: citationCount,
          topologyReadinessLevel: topologyReadinessLevel,
          validationGaps: validationGaps,
          topologyRiskFlags: topologyRiskFlags,
          failureDomains: failureDomains,
        ))
          {
            'gate': gate.gate,
            'signal': gate.signal,
            'status': gate.status,
            'ownerAction': gate.ownerAction,
            'ready': gate.ready,
          },
      ],
      'advisories': [
        for (final item in advisories)
          {
            'topic': item.topic,
            'guidance': item.guidance,
            'critical': item.critical,
          },
      ],
      'validationGaps': validationGaps,
      'riskFlags': topologyRiskFlags,
      'assumptions': assumptions,
    };
  }

  List<List<String>> _previewRowsFor(
    _DiagramGraph graph,
    _TopologyProfile profile,
    List<({String check, String state, bool ready})> readinessItems,
    List<({String metric, String value, String guidance, bool ready})>
    capacityItems,
    List<({String topic, String guidance, bool critical})> advisories,
    List<_FailureDomainRow> failureDomains,
  ) {
    return [
      const ['Signal', 'Value', 'Guidance'],
      [
        'Topology',
        '${graph.nodes.length} nodes / ${graph.edges.length} links',
        'Review generated topology before customer handoff.',
      ],
      [
        'Sites',
        '${profile.siteCount} sites • ${profile.mdfCount} MDF • ${profile.idfCount} IDF',
        profile.hasDualWan || profile.hasWarmSpare
            ? profile.resiliencyLabel
            : 'Confirm redundancy model.',
      ],
      for (final domain in profile.segmentationDomains.take(3))
        [
          domain.name,
          domain.subnet.isEmpty ? domain.scope : domain.subnet,
          domain.validation,
        ],
      for (final item in capacityItems.take(4))
        [item.metric, item.value, item.guidance],
      for (final item in advisories.take(2))
        [
          item.topic,
          item.critical ? 'Critical review' : 'Review',
          item.guidance,
        ],
      for (final item in failureDomains.where((item) => !item.ready).take(2))
        [item.domain, item.redundancy, item.validation],
      for (final item in readinessItems.take(2))
        [item.check, item.state, item.ready ? 'Captured' : 'Needs input'],
    ];
  }

  _DiagramGraph _graphFromMermaid(String content) {
    final fenced = RegExp(
      r'```mermaid\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(content);
    final candidate = fenced?.group(1) ?? content;
    final nodes = <String, _DiagramNode>{};
    final edges = <_DiagramEdge>[];
    for (final raw in const LineSplitter().convert(candidate)) {
      final line = raw
          .trim()
          .replaceAll(RegExp(r';$'), '')
          .replaceAll(
            RegExp(r'^\s*(graph|flowchart)\s+\w+\s*$', caseSensitive: false),
            '',
          );
      if (line.isEmpty || line.startsWith('%%')) continue;
      final match = RegExp(
        r'^(.+?)\s*(-->|---|==>|-.->)\s*(?:\|([^|]+)\|\s*)?(.+)$',
      ).firstMatch(line);
      if (match == null) {
        final node = _parseNode(line);
        if (node != null) nodes[node.id] = node;
        continue;
      }
      final from = _parseNode(match.group(1) ?? '');
      final to = _parseNode(match.group(4) ?? '');
      if (from == null || to == null) continue;
      _mergeNode(nodes, from);
      _mergeNode(nodes, to);
      edges.add(
        _DiagramEdge(
          from: from.id,
          to: to.id,
          label: (match.group(3) ?? '').trim(),
        ),
      );
    }
    return _DiagramGraph(nodes: nodes, edges: edges);
  }

  void _mergeNode(Map<String, _DiagramNode> nodes, _DiagramNode candidate) {
    final existing = nodes[candidate.id];
    if (existing == null ||
        (existing.label == existing.id && candidate.label != candidate.id)) {
      nodes[candidate.id] = candidate;
    }
  }

  _DiagramGraph _graphFromNetworkText(String content) {
    final normalized = content.toLowerCase();
    final networkSignal = RegExp(
      r'\b(wan|lan|mdf|idf|firewall|switch(?:es)?|access point|ap\b|wifi|wi-fi|router|core|distribution|internet|cloud|branch|campus|catalyst|meraki|mx\d+|c9[235]\d{2}|cw9\d{3}|poe|upoe)\b',
    ).hasMatch(normalized);
    if (!networkSignal) return const _DiagramGraph(nodes: {}, edges: []);

    final nodes = <String, _DiagramNode>{};
    final edges = <_DiagramEdge>[];

    void add(String id, String label, _DiagramNodeRole role) {
      nodes[id] = _DiagramNode(id: id, label: label, role: role);
    }

    void link(String from, String to, [String label = '']) {
      if (nodes.containsKey(from) && nodes.containsKey(to)) {
        edges.add(_DiagramEdge(from: from, to: to, label: label));
      }
    }

    final hasInternet = RegExp(
      r'\b(internet|isp|wan|sd-wan|mpls)\b',
    ).hasMatch(normalized);
    final hasCloud = RegExp(
      r'\b(cloud|saas|azure|aws|gcp|meraki dashboard)\b',
    ).hasMatch(normalized);
    final hasFirewall = RegExp(
      r'\b(firewall|fw|mx\d+|asa|ftd|secure firewall)\b',
    ).hasMatch(normalized);
    final hasCore = RegExp(
      r'\b(core|mdf|c95\d{2}|catalyst 95|9500)\b',
    ).hasMatch(normalized);
    final hasAccess = RegExp(
      r'\b(access|idf|c93\d{2}|catalyst 93|9300|switch)\b',
    ).hasMatch(normalized);
    final hasAps = RegExp(
      r'\b(ap\b|aps\b|access points?|cw9\d{3}|wifi|wi-fi)\b',
    ).hasMatch(normalized);
    final hasClients = RegExp(
      r'\b(client|clients|users|endpoints|devices)\b',
    ).hasMatch(normalized);
    final branchCount = _countFromText(
      content,
      RegExp(
        r'(\d+)\s+(?:branches|branch sites|remote sites)',
        caseSensitive: false,
      ),
    );
    final idfCount = _countFromText(
      content,
      RegExp(r'(\d+)\s+IDFs?', caseSensitive: false),
    );

    if (hasInternet) add('wan', 'WAN / ISP', _DiagramNodeRole.external);
    if (hasCloud) add('cloud', 'Cloud / SaaS', _DiagramNodeRole.external);
    if (hasFirewall) {
      final firewallCount = _deviceCount(
        content,
        RegExp(r'\bMX[A-Za-z0-9-]*\b', caseSensitive: false),
        warmSpareDefault:
            RegExp(r'\bwarm spare\b', caseSensitive: false).hasMatch(content)
            ? 2
            : 1,
      );
      add(
        'edge',
        _deviceGroupLabel(
          content,
          'MX',
          'Security Edge',
          firewallCount,
          suffix: firewallCount > 1 ? 'HA Pair' : null,
        ),
        _DiagramNodeRole.edge,
      );
    }
    if (hasCore) {
      final coreSwitchCount = _deviceCount(
        content,
        RegExp(r'\bC95\d{2}[A-Z0-9-]*\b', caseSensitive: false),
      );
      add(
        'core',
        _deviceGroupLabel(
          content,
          'C95',
          'MDF Core',
          coreSwitchCount,
          suffix: 'MDF Core',
        ),
        _DiagramNodeRole.core,
      );
    }
    if (hasAccess) {
      final accessSwitchCount = _deviceCount(
        content,
        RegExp(r'\bC93\d{2}[A-Z0-9-]*\b', caseSensitive: false),
      );
      final accessModel = _deviceGroupLabel(
        content,
        'C93',
        'Access / IDF',
        accessSwitchCount,
      );
      final label = idfCount == null || idfCount <= 1
          ? accessModel
          : accessModel == 'Access / IDF'
          ? '$idfCount IDFs / Access'
          : '$idfCount IDFs / $accessModel';
      add('access', label, _DiagramNodeRole.access);
    }
    if (hasAps) {
      final apCount =
          _countFromText(
            content,
            RegExp(
              r'(\d+)\s+(?:CW9\d{3}[A-Z0-9-]*|aps?|access points?)',
              caseSensitive: false,
            ),
          ) ??
          _deviceCount(
            content,
            RegExp(r'\bCW9\d{3}[A-Z0-9-]*\b', caseSensitive: false),
          );
      add(
        'aps',
        _deviceGroupLabel(content, 'CW', 'Wireless APs', apCount),
        _DiagramNodeRole.endpoint,
      );
    }
    if (hasClients) {
      add('clients', 'Users / Clients', _DiagramNodeRole.endpoint);
    }
    if (branchCount != null && branchCount > 0) {
      add('branches', '$branchCount Branch Sites', _DiagramNodeRole.site);
    } else if (RegExp(r'\b(branch|site|campus)\b').hasMatch(normalized)) {
      add('site', 'Site / Campus', _DiagramNodeRole.site);
    }

    if (nodes.length < 2) return const _DiagramGraph(nodes: {}, edges: []);

    link('wan', 'edge', 'primary/secondary');
    link('cloud', 'edge', 'services');
    link('edge', 'core', 'routed');
    link('wan', 'core', 'uplink');
    link('core', 'access', 'distribution');
    link('access', 'aps', 'PoE / mGig');
    link('access', 'clients', 'wired');
    link('branches', 'wan', 'dual WAN');
    link('site', 'core', 'campus LAN');
    if (edges.isEmpty) {
      final ordered = nodes.values.toList(growable: false);
      for (var i = 1; i < ordered.length; i++) {
        edges.add(_DiagramEdge(from: ordered[i - 1].id, to: ordered[i].id));
      }
    }
    return _DiagramGraph(nodes: nodes, edges: edges);
  }

  _DiagramGraph _graphFromDocument(ArtifactDocument document) {
    final nodes = <String, _DiagramNode>{};
    final edges = <_DiagramEdge>[];
    nodes['artifact'] = _DiagramNode(
      id: 'artifact',
      label: document.title,
      role: _DiagramNodeRole.other,
    );
    final sections = document.sections.take(8).toList(growable: false);
    if (sections.isEmpty) {
      nodes['summary'] = const _DiagramNode(
        id: 'summary',
        label: 'Summary',
        role: _DiagramNodeRole.other,
      );
      edges.add(const _DiagramEdge(from: 'artifact', to: 'summary'));
      return _DiagramGraph(nodes: nodes, edges: edges);
    }
    for (var i = 0; i < sections.length; i++) {
      final id = 'section_${i + 1}';
      nodes[id] = _DiagramNode(
        id: id,
        label: sections[i].title,
        role: _roleFor(sections[i].title),
      );
      edges.add(_DiagramEdge(from: i == 0 ? 'artifact' : 'section_$i', to: id));
    }
    return _DiagramGraph(nodes: nodes, edges: edges);
  }

  _DiagramNode? _parseNode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final bracket = RegExp(
      r'^([A-Za-z0-9_:-]+)\s*(?:\[\s*"?(.+?)"?\s*\]|\(\s*"?(.+?)"?\s*\)|\{\s*"?(.+?)"?\s*\})?$',
    ).firstMatch(trimmed);
    if (bracket == null) return null;
    final id = bracket.group(1)?.trim();
    if (id == null || id.isEmpty) return null;
    final label =
        bracket.group(2) ??
        bracket.group(3) ??
        bracket.group(4) ??
        id.replaceAll('_', ' ');
    return _DiagramNode(id: id, label: label.trim(), role: _roleFor(label));
  }

  String _svgFor(
    _DiagramGraph graph, {
    required String title,
    required List<String> assumptions,
    required int citationCount,
    required _TopologyProfile profile,
  }) {
    final nodeEntries = graph.nodes.values.toList(growable: false);
    const width = 1180;
    final tiers = _layoutTiers(nodeEntries);
    final maxTierSize = tiers.values.fold<int>(
      1,
      (max, nodes) => nodes.length > max ? nodes.length : max,
    );
    final height = math.max(1096, 702 + (maxTierSize * 112));
    final positions = _tierPositions(tiers, width: width, height: height);
    final readinessItems = _readinessItems(profile, assumptions);
    final capacityItems = _capacityItems(profile);
    final linkSchedule = _linkSchedule(graph, profile);
    final advisories = _designAdvisories(profile, assumptions);
    final failureDomains = _failureDomainRows(profile);
    final metadata = _metadataFor(
      graph: graph,
      tiers: tiers,
      assumptions: assumptions,
      citationCount: citationCount,
      profile: profile,
      readinessItems: readinessItems,
      capacityItems: capacityItems,
      linkSchedule: linkSchedule,
      advisories: advisories,
      failureDomains: failureDomains,
    );

    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height" role="img">',
      )
      ..writeln('<title>${_xml(title)}</title>')
      ..writeln(
        '<desc>Network topology diagram generated by CircuitCode. Review assumptions before customer handoff.</desc>',
      )
      ..writeln('<metadata>${_xml(jsonEncode(metadata))}</metadata>')
      ..writeln('<rect width="100%" height="100%" rx="20" fill="#101111"/>')
      ..writeln('<rect x="0" y="0" width="8" height="$height" fill="#78aaa5"/>')
      ..writeln(
        '<text x="36" y="54" fill="#f2f2ef" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="24" font-weight="700">${_xml(title)}</text>',
      )
      ..writeln(
        '<text x="36" y="80" fill="#9da6a3" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12">Logical topology • validate quantities, uplinks, PoE budget, and redundancy before final design</text>',
      )
      ..writeln(
        '<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto"><path d="M0,0 L0,6 L9,3 z" fill="#8f9695"/></marker></defs>',
      );

    _drawTopologySummary(buffer, profile, width: width);
    _drawQualityGate(
      buffer,
      status: metadata['topologyQualityStatus']?.toString() ?? 'Draft',
      score: metadata['topologyReadinessScore'] is int
          ? metadata['topologyReadinessScore'] as int
          : 0,
      checklistCount: metadata['topologyQualityChecklistCount'] is int
          ? metadata['topologyQualityChecklistCount'] as int
          : 0,
      width: width,
    );
    _drawDesignLegend(buffer, tiers, width: width);
    _drawTierBands(buffer, tiers, width: width, height: height);

    buffer.writeln(
      '<g id="topology-edges" data-edge-count="${graph.edges.length}">',
    );
    for (final edge in graph.edges) {
      final from = positions[edge.from];
      final to = positions[edge.to];
      if (from == null || to == null) continue;
      buffer.writeln(
        '<line class="topology-edge" data-from="${_xml(edge.from)}" data-to="${_xml(edge.to)}" data-label="${_xml(edge.label)}" x1="${from.x}" y1="${from.y}" x2="${to.x}" y2="${to.y}" stroke="#6f7775" stroke-width="2" marker-end="url(#arrow)"/>',
      );
      if (edge.label.isNotEmpty) {
        buffer.writeln(
          '<text x="${(from.x + to.x) / 2}" y="${(from.y + to.y) / 2 - 8}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12" text-anchor="middle">${_xml(edge.label)}</text>',
        );
      }
    }
    buffer.writeln('</g>');

    buffer.writeln(
      '<g id="topology-nodes" data-node-count="${nodeEntries.length}">',
    );
    for (final node in nodeEntries) {
      final point = positions[node.id] ?? const _Point(460, 300);
      final style = _styleFor(node.role);
      buffer
        ..writeln(
          '<g class="topology-node" data-id="${_xml(node.id)}" data-label="${_xml(node.label)}" data-role="${_roleLabel(node.role)}">',
        )
        ..writeln(
          '<rect x="${point.x - 92}" y="${point.y - 32}" width="184" height="64" rx="13" fill="${style.fill}" stroke="${style.stroke}"/>',
        )
        ..writeln(
          '<text x="${point.x}" y="${point.y - 4}" fill="#f5f4f0" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="14" font-weight="700" text-anchor="middle">${_xml(_shorten(node.label, 28))}</text>',
        )
        ..writeln(
          '<text x="${point.x}" y="${point.y + 16}" fill="${style.accent}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="600" text-anchor="middle">${_xml(_roleLabel(node.role))}</text>',
        )
        ..writeln('</g>');
    }
    buffer.writeln('</g>');

    _drawFailureDomainPanel(
      buffer,
      failureDomains,
      width: width,
      height: height,
    );
    _drawDesignAdvisories(buffer, advisories, width: width, height: height);
    _drawSegmentationPanel(
      buffer,
      profile.segmentationDomains,
      width: width,
      height: height,
    );
    _drawTopologyHandoffReadinessMatrix(
      buffer,
      _handoffReadinessRowsFromMetadata(metadata),
      width: width,
      height: height,
    );
    _drawLinkSchedule(buffer, linkSchedule, width: width, height: height);
    _drawReadinessScorecard(
      buffer,
      readinessItems,
      width: width,
      height: height,
    );
    _drawCapacityPanel(
      buffer,
      capacityItems,
      profile,
      width: width,
      height: height,
    );
    _drawInventoryPanel(buffer, profile, width: width, height: height);
    _drawValidationChecklist(buffer, profile, width: width, height: height);
    _drawAssumptions(buffer, assumptions, width: width, height: height);

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  Map<_DiagramNodeRole, List<_DiagramNode>> _layoutTiers(
    List<_DiagramNode> nodes,
  ) {
    final tiers = <_DiagramNodeRole, List<_DiagramNode>>{
      for (final role in _tierOrder) role: <_DiagramNode>[],
    };
    for (final node in nodes) {
      tiers.putIfAbsent(node.role, () => <_DiagramNode>[]).add(node);
    }
    tiers.removeWhere((_, nodes) => nodes.isEmpty);
    return tiers;
  }

  Map<String, _Point> _tierPositions(
    Map<_DiagramNodeRole, List<_DiagramNode>> tiers, {
    required int width,
    required int height,
  }) {
    final roles = _tierOrder.where((role) => tiers.containsKey(role)).toList();
    final positions = <String, _Point>{};
    if (roles.isEmpty) return positions;
    const left = 130.0;
    final usableWidth = width - 260;
    for (var tierIndex = 0; tierIndex < roles.length; tierIndex++) {
      final role = roles[tierIndex];
      final nodes = tiers[role] ?? const <_DiagramNode>[];
      final x = roles.length == 1
          ? width / 2
          : left + (usableWidth * tierIndex / (roles.length - 1));
      final usableHeight = height - 756;
      for (var i = 0; i < nodes.length; i++) {
        final y = nodes.length == 1
            ? 360.0
            : 230 + (usableHeight * i / (nodes.length - 1));
        positions[nodes[i].id] = _Point(x, y);
      }
    }
    return positions;
  }

  void _drawTierBands(
    StringBuffer buffer,
    Map<_DiagramNodeRole, List<_DiagramNode>> tiers, {
    required int width,
    required int height,
  }) {
    final roles = _tierOrder.where((role) => tiers.containsKey(role)).toList();
    if (roles.isEmpty) return;
    const left = 90.0;
    final bandWidth = (width - 180) / roles.length;
    for (var i = 0; i < roles.length; i++) {
      final x = left + (i * bandWidth);
      buffer
        ..writeln(
          '<rect class="topology-tier-band" data-tier="${_xml(roles[i].name)}" data-tier-label="${_xml(_tierLabel(roles[i]))}" x="$x" y="206" width="${bandWidth - 12}" height="${height - 696}" rx="18" fill="${i.isEven ? '#151716' : '#181a19'}" stroke="#252928"/>',
        )
        ..writeln(
          '<text x="${x + 18}" y="234" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700" letter-spacing="0">${_xml(_tierLabel(roles[i]))}</text>',
        );
    }
  }

  void _drawTopologySummary(
    StringBuffer buffer,
    _TopologyProfile profile, {
    required int width,
  }) {
    const x = 36.0;
    const y = 102.0;
    final cards = [
      ('Sites', '${profile.siteCount}', profile.siteCount > 0),
      ('Edge', '${profile.firewallCount}', profile.firewallCount > 0),
      ('MDF/Core', '${profile.coreSwitchCount}', profile.coreSwitchCount > 0),
      (
        'IDF/Access',
        '${profile.idfCount}/${profile.accessSwitchCount}',
        profile.idfCount > 0 || profile.accessSwitchCount > 0,
      ),
      ('Wireless', '${profile.apCount} APs', profile.apCount > 0),
      (
        'Resiliency',
        profile.resiliencyLabel,
        profile.hasDualWan || profile.hasWarmSpare,
      ),
    ];
    final cardWidth = (width - 72 - ((cards.length - 1) * 10)) / cards.length;
    buffer.writeln(
      '<g id="topology-summary" data-site-count="${profile.siteCount}" data-firewall-count="${profile.firewallCount}" data-switch-count="${profile.switchCount}" data-ap-count="${profile.apCount}">',
    );
    for (var i = 0; i < cards.length; i++) {
      final cardX = x + (i * (cardWidth + 10));
      final accent = cards[i].$3 ? '#78aaa5' : '#4b5351';
      buffer
        ..writeln(
          '<rect x="${cardX.toStringAsFixed(1)}" y="$y" width="${cardWidth.toStringAsFixed(1)}" height="48" rx="12" fill="#171918" stroke="#29302f"/>',
        )
        ..writeln(
          '<text x="${(cardX + 14).toStringAsFixed(1)}" y="${y + 19}" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="700">${_xml(cards[i].$1)}</text>',
        )
        ..writeln(
          '<text x="${(cardX + 14).toStringAsFixed(1)}" y="${y + 37}" fill="$accent" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="13" font-weight="700">${_xml(cards[i].$2)}</text>',
        );
    }
    buffer.writeln('</g>');
  }

  void _drawQualityGate(
    StringBuffer buffer, {
    required String status,
    required int score,
    required int checklistCount,
    required int width,
  }) {
    const cardWidth = 294.0;
    final x = width - cardWidth - 36;
    const y = 36.0;
    buffer
      ..writeln(
        '<g id="topology-quality-gate" data-quality-status="${_xml(status)}" data-readiness-score="$score" data-quality-check-count="$checklistCount">',
      )
      ..writeln(
        '<rect x="${x.toStringAsFixed(1)}" y="$y" width="$cardWidth" height="42" rx="12" fill="#141817" stroke="#2f3a37"/>',
      )
      ..writeln(
        '<text x="${(x + 14).toStringAsFixed(1)}" y="${y + 18}" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="700">Quality gate</text>',
      )
      ..writeln(
        '<text x="${(x + 14).toStringAsFixed(1)}" y="${y + 34}" fill="#8dd3bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="700">${_xml(_shorten('$status • $score/100 • $checklistCount checks', 48))}</text>',
      )
      ..writeln('</g>');
  }

  void _drawDesignLegend(
    StringBuffer buffer,
    Map<_DiagramNodeRole, List<_DiagramNode>> tiers, {
    required int width,
  }) {
    final roles = _tierOrder.where((role) => tiers.containsKey(role)).toList();
    if (roles.isEmpty) return;
    const y = 160.0;
    buffer.writeln(
      '<g id="topology-design-zones" data-zone-count="${roles.length}">',
    );
    buffer.writeln(
      '<text x="36" y="${y + 12}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Design zones</text>',
    );
    var x = 132.0;
    for (final role in roles) {
      final style = _styleFor(role);
      final label = _tierLabel(role);
      final chipWidth = math.min(152.0, 38 + (label.length * 6.1));
      if (x + chipWidth > width - 36) break;
      buffer
        ..writeln(
          '<rect x="${x.toStringAsFixed(1)}" y="$y" width="${chipWidth.toStringAsFixed(1)}" height="22" rx="11" fill="${style.fill}" stroke="${style.stroke}"/>',
        )
        ..writeln(
          '<circle cx="${(x + 13).toStringAsFixed(1)}" cy="${y + 11}" r="4" fill="${style.accent}"/>',
        )
        ..writeln(
          '<text x="${(x + 24).toStringAsFixed(1)}" y="${y + 15}" fill="#c8cecc" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="600">${_xml(label)}</text>',
        );
      x += chipWidth + 8;
    }
    buffer.writeln('</g>');
  }

  List<({String from, String to, String link, String validation})>
  _linkSchedule(_DiagramGraph graph, _TopologyProfile profile) {
    final rows = <({String from, String to, String link, String validation})>[];
    for (final edge in graph.edges.take(5)) {
      final from = graph.nodes[edge.from]?.label ?? edge.from;
      final to = graph.nodes[edge.to]?.label ?? edge.to;
      rows.add((
        from: from,
        to: to,
        link: edge.label.isEmpty ? 'logical dependency' : edge.label,
        validation: _linkValidation(edge.label, profile),
      ));
    }
    if (rows.isEmpty) {
      rows.add((
        from: 'Topology',
        to: 'Customer environment',
        link: 'review',
        validation: 'Confirm source inventory and intended connectivity.',
      ));
    }
    return rows;
  }

  String _linkValidation(String label, _TopologyProfile profile) {
    final normalized = label.toLowerCase();
    if (normalized.contains('poe') || normalized.contains('mgig')) {
      return 'Validate PoE/UPOE budget, mGig need, and AP draw.';
    }
    if (normalized.contains('distribution') || normalized.contains('routed')) {
      return 'Validate uplink speed, L3 boundary, and redundancy pairings.';
    }
    if (normalized.contains('wan') || normalized.contains('primary')) {
      return 'Validate ISP handoffs, routing, failover, and SLA ownership.';
    }
    if (profile.hasWifi7 || profile.hasPoe) {
      return 'Validate PoE/UPOE budget, mGig need, and AP draw.';
    }
    if (profile.hasDualWan) {
      return 'Validate ISP handoffs, routing, failover, and SLA ownership.';
    }
    return 'Confirm cabling, ownership, and operational monitoring.';
  }

  List<({String topic, String guidance, bool critical})> _designAdvisories(
    _TopologyProfile profile,
    List<String> assumptions,
  ) {
    final advisories = <({String topic, String guidance, bool critical})>[];
    if (profile.hasWifi7) {
      advisories.add((
        topic: 'Wi-Fi 7 / PoE',
        guidance:
            'Wi-Fi 7 APs require explicit UPOE, mGig, switch power-supply, and spare-port validation.',
        critical: true,
      ));
    } else if (profile.apCount > 0) {
      advisories.add((
        topic: 'Wireless',
        guidance:
            'Confirm AP generation, PoE class, placement, and access-port headroom before final design.',
        critical: false,
      ));
    }
    advisories.add((
      topic: 'Lifecycle',
      guidance:
          'Treat EoX replacement PIDs as migration hints only; validate against current portfolio and requirements.',
      critical: true,
    ));
    if (profile.hasDualWan || profile.hasWarmSpare) {
      advisories.add((
        topic: 'Resiliency',
        guidance:
            'Document failover ownership, HA behavior, routing preference, and test plan for every redundant path.',
        critical: true,
      ));
    } else {
      advisories.add((
        topic: 'Resiliency',
        guidance:
            'Capture WAN and device redundancy expectations before customer handoff.',
        critical: false,
      ));
    }
    final apPortLoadPercent = profile.apPortLoadPercent;
    if (apPortLoadPercent != null && apPortLoadPercent >= 70) {
      advisories.add((
        topic: 'Port headroom',
        guidance:
            'AP port load is high; validate IDF-level spare ports and growth assumptions.',
        critical: true,
      ));
    }
    if (assumptions.isEmpty) {
      advisories.add((
        topic: 'Assumptions',
        guidance:
            'Add explicit source, sizing, lifecycle, power, and cabling assumptions before external use.',
        critical: true,
      ));
    }
    return advisories.take(5).toList(growable: false);
  }

  void _drawFailureDomainPanel(
    StringBuffer buffer,
    List<_FailureDomainRow> domains, {
    required int width,
    required int height,
  }) {
    if (domains.isEmpty) return;
    final y = height - 492;
    final visible = domains.take(3).toList(growable: false);
    final readyCount = domains.where((domain) => domain.ready).length;
    buffer.writeln(
      '<g id="topology-failure-domains" data-failure-domain-count="${domains.length}" data-critical-failure-domain-count="${domains.length - readyCount}">',
    );
    buffer.writeln(
      '<rect x="36" y="$y" width="${width - 72}" height="50" rx="12" fill="#141615" stroke="#28302e"/>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 18}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Failure-domain review</text>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 37}" fill="#78aaa5" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="700">$readyCount/${domains.length} domains have redundancy signals</text>',
    );
    var x = 286.0;
    final cardWidth =
        (width - x - 54 - ((visible.length - 1) * 8)) /
        math.max(1, visible.length);
    for (var i = 0; i < visible.length; i++) {
      final domain = visible[i];
      final cardX = x + (i * (cardWidth + 8));
      buffer
        ..writeln(
          '<rect x="${cardX.toStringAsFixed(1)}" y="${y + 9}" width="${cardWidth.toStringAsFixed(1)}" height="32" rx="8" fill="${domain.ready ? '#182621' : '#2a241b'}" stroke="${domain.ready ? '#2e5148' : '#59482b'}"/>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 22}" fill="${domain.ready ? '#8dd3bd' : '#e1bb6d'}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9" font-weight="700">${_xml(_shorten('${domain.domain}: ${domain.redundancy}', 38))}</text>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 36}" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="8">${_xml(_shorten(domain.validation, 46))}</text>',
        );
    }
    buffer.writeln('</g>');
  }

  void _drawDesignAdvisories(
    StringBuffer buffer,
    List<({String topic, String guidance, bool critical})> advisories, {
    required int width,
    required int height,
  }) {
    if (advisories.isEmpty) return;
    final y = height - 436;
    final visible = advisories.take(3).toList(growable: false);
    buffer.writeln(
      '<g id="topology-advisories" data-advisory-count="${advisories.length}">',
    );
    buffer.writeln(
      '<rect x="36" y="$y" width="${width - 72}" height="50" rx="12" fill="#141615" stroke="#28302e"/>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 18}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Architecture advisories</text>',
    );
    var x = 198.0;
    final cardWidth =
        (width - x - 54 - ((visible.length - 1) * 8)) /
        math.max(1, visible.length);
    for (var i = 0; i < visible.length; i++) {
      final item = visible[i];
      final cardX = x + (i * (cardWidth + 8));
      buffer
        ..writeln(
          '<rect x="${cardX.toStringAsFixed(1)}" y="${y + 9}" width="${cardWidth.toStringAsFixed(1)}" height="32" rx="8" fill="${item.critical ? '#2a241b' : '#182621'}" stroke="${item.critical ? '#59482b' : '#2e5148'}"/>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 22}" fill="${item.critical ? '#e1bb6d' : '#8dd3bd'}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9" font-weight="700">${_xml(_shorten(item.topic, 28))}</text>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 36}" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="8">${_xml(_shorten(item.guidance, 48))}</text>',
        );
    }
    buffer.writeln('</g>');
  }

  List<_TopologyHandoffGate> _handoffReadinessRowsFromMetadata(
    Map<String, Object?> metadata,
  ) {
    final raw = metadata['topologyHandoffReadinessMatrix'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          (
            gate: item['gate']?.toString() ?? '',
            signal: item['signal']?.toString() ?? '',
            status: item['status']?.toString() ?? '',
            ownerAction: item['ownerAction']?.toString() ?? '',
            ready: item['ready'] == true,
          ),
    ].where((item) => item.gate.isNotEmpty).toList(growable: false);
  }

  void _drawTopologyHandoffReadinessMatrix(
    StringBuffer buffer,
    List<_TopologyHandoffGate> gates, {
    required int width,
    required int height,
  }) {
    if (gates.isEmpty) return;
    final y = height - 604;
    final visible = gates.take(4).toList(growable: false);
    final readyCount = gates.where((gate) => gate.ready).length;
    buffer.writeln(
      '<g id="topology-handoff-readiness" data-handoff-gate-count="${gates.length}" data-ready-handoff-gate-count="$readyCount">',
    );
    buffer.writeln(
      '<rect x="36" y="$y" width="${width - 72}" height="50" rx="12" fill="#121615" stroke="#2b3835"/>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 18}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Customer handoff readiness</text>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 37}" fill="#78aaa5" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="700">$readyCount/${gates.length} gates ready</text>',
    );
    var x = 262.0;
    final cardWidth =
        (width - x - 54 - ((visible.length - 1) * 8)) /
        math.max(1, visible.length);
    for (var i = 0; i < visible.length; i++) {
      final gate = visible[i];
      final cardX = x + (i * (cardWidth + 8));
      buffer
        ..writeln(
          '<rect x="${cardX.toStringAsFixed(1)}" y="${y + 9}" width="${cardWidth.toStringAsFixed(1)}" height="32" rx="8" fill="${gate.ready ? '#182621' : '#2a241b'}" stroke="${gate.ready ? '#2e5148' : '#59482b'}"/>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 22}" fill="${gate.ready ? '#8dd3bd' : '#e1bb6d'}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9" font-weight="700">${_xml(_shorten('${gate.gate}: ${gate.status}', 34))}</text>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 36}" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="8">${_xml(_shorten(gate.ownerAction, 42))}</text>',
        );
    }
    buffer.writeln('</g>');
  }

  void _drawSegmentationPanel(
    StringBuffer buffer,
    List<_SegmentationDomain> domains, {
    required int width,
    required int height,
  }) {
    if (domains.isEmpty) return;
    final y = height - 548;
    final visible = domains.take(4).toList(growable: false);
    final readyCount = domains.where((domain) => domain.ready).length;
    buffer.writeln(
      '<g id="topology-segmentation" data-segmentation-domain-count="${domains.length}" data-ready-segmentation-domain-count="$readyCount">',
    );
    buffer.writeln(
      '<rect x="36" y="$y" width="${width - 72}" height="50" rx="12" fill="#121615" stroke="#26302d"/>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 18}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Segmentation review</text>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 37}" fill="#78aaa5" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="700">$readyCount/${domains.length} VLAN/VRF/subnet domains ready</text>',
    );
    var x = 294.0;
    final cardWidth =
        (width - x - 54 - ((visible.length - 1) * 8)) /
        math.max(1, visible.length);
    for (var i = 0; i < visible.length; i++) {
      final domain = visible[i];
      final cardX = x + (i * (cardWidth + 8));
      buffer
        ..writeln(
          '<rect x="${cardX.toStringAsFixed(1)}" y="${y + 9}" width="${cardWidth.toStringAsFixed(1)}" height="32" rx="8" fill="${domain.ready ? '#182621' : '#2a241b'}" stroke="${domain.ready ? '#2e5148' : '#59482b'}"/>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 22}" fill="${domain.ready ? '#8dd3bd' : '#e1bb6d'}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9" font-weight="700">${_xml(_shorten(domain.name, 32))}</text>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 36}" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="8">${_xml(_shorten(domain.subnet.isEmpty ? domain.scope : domain.subnet, 38))}</text>',
        );
    }
    buffer.writeln('</g>');
  }

  void _drawLinkSchedule(
    StringBuffer buffer,
    List<({String from, String to, String link, String validation})> links, {
    required int width,
    required int height,
  }) {
    final y = height - 380;
    final visible = links.take(3).toList(growable: false);
    buffer.writeln(
      '<g id="topology-link-schedule" data-link-schedule-count="${links.length}">',
    );
    buffer.writeln(
      '<rect x="36" y="$y" width="${width - 72}" height="50" rx="12" fill="#111413" stroke="#26302d"/>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 18}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Link schedule</text>',
    );
    var x = 150.0;
    final cardWidth =
        (width - x - 54 - ((visible.length - 1) * 8)) /
        math.max(1, visible.length);
    for (var i = 0; i < visible.length; i++) {
      final link = visible[i];
      final cardX = x + (i * (cardWidth + 8));
      buffer
        ..writeln(
          '<rect x="${cardX.toStringAsFixed(1)}" y="${y + 9}" width="${cardWidth.toStringAsFixed(1)}" height="32" rx="8" fill="#171918" stroke="#2b302f"/>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 22}" fill="#f2f2ef" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9" font-weight="700">${_xml(_shorten('${link.from} → ${link.to}', 35))}</text>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 36}" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="8">${_xml(_shorten(link.validation, 44))}</text>',
        );
    }
    buffer.writeln('</g>');
  }

  List<({String check, String state, bool ready})> _readinessItems(
    _TopologyProfile profile,
    List<String> assumptions,
  ) {
    final readySegmentationCount = profile.segmentationDomains
        .where((domain) => domain.ready)
        .length;
    return [
      (
        check: 'Redundancy',
        state: profile.hasDualWan || profile.hasWarmSpare
            ? profile.resiliencyLabel
            : 'Needs review',
        ready: profile.hasDualWan || profile.hasWarmSpare,
      ),
      (
        check: 'Power',
        state: profile.hasPoe || profile.hasWifi7
            ? 'Validate budget'
            : 'Unknown',
        ready: profile.hasPoe || profile.hasWifi7,
      ),
      (
        check: 'Uplinks',
        state: profile.hasMultigig ? 'mGig/10G noted' : 'Confirm speed',
        ready: profile.hasMultigig,
      ),
      (
        check: 'Evidence',
        state: assumptions.isEmpty ? 'Needs assumptions' : 'Assumptions listed',
        ready: assumptions.isNotEmpty,
      ),
      if (profile.hasSegmentationSignal ||
          profile.segmentationDomains.isNotEmpty)
        (
          check: 'Segmentation',
          state: profile.segmentationDomains.isEmpty
              ? 'Confirm VLAN/IP plan'
              : '$readySegmentationCount/${profile.segmentationDomains.length} domains ready',
          ready:
              profile.segmentationDomains.isNotEmpty &&
              readySegmentationCount == profile.segmentationDomains.length,
        ),
    ];
  }

  List<({String metric, String value, String guidance, bool ready})>
  _capacityItems(_TopologyProfile profile) {
    final portLoad = profile.apPortLoadPercent;
    return [
      (
        metric: 'Access ports',
        value: profile.accessPortCount > 0 && profile.apCount > 0
            ? '${profile.apCount}/${profile.accessPortCount} AP ports'
            : 'Confirm counts',
        guidance: portLoad == null
            ? 'Capture access switch port count and AP count.'
            : portLoad >= 75
            ? 'High AP port pressure; validate spare ports per IDF.'
            : 'AP port headroom appears reasonable.',
        ready: portLoad != null && portLoad < 75,
      ),
      (
        metric: 'AP power',
        value: profile.estimatedApPowerWatts > 0
            ? '${profile.estimatedApPowerWatts}W est.'
            : 'Unknown',
        guidance: profile.hasWifi7 || profile.hasUpoe
            ? 'Validate UPOE budget, supplies, and AP draw.'
            : 'Confirm PoE class and power budget.',
        ready: profile.hasPoe || profile.hasUpoe,
      ),
      (
        metric: 'Uplinks',
        value: profile.hasMultigig ? 'mGig/10G noted' : 'Confirm speed',
        guidance: profile.hasMultigig
            ? 'Validate access-to-core oversubscription.'
            : 'Capture uplink and WAN handoff speeds.',
        ready: profile.hasMultigig,
      ),
      (
        metric: 'Wi-Fi readiness',
        value: profile.hasWifi7 ? 'Wi-Fi 7 sensitive' : 'Confirm generation',
        guidance: profile.hasWifi7
            ? 'Check UPOE/mGig access and lifecycle fit.'
            : 'Record AP generation and replacement horizon.',
        ready: profile.hasWifi7 && (profile.hasUpoe || profile.hasPoe),
      ),
    ];
  }

  List<_FailureDomainRow> _failureDomainRows(_TopologyProfile profile) {
    return [
      (
        domain: 'WAN edge',
        redundancy: profile.hasDualWan ? 'Dual WAN captured' : 'Single/unknown',
        impact: profile.hasDualWan
            ? 'ISP failure should have an alternate path.'
            : 'WAN or ISP loss can isolate sites.',
        validation: profile.hasDualWan
            ? 'Document failover test, routing preference, and SLA owner.'
            : 'Confirm secondary WAN/MPLS/Internet path and routing failover.',
        ready: profile.hasDualWan,
      ),
      (
        domain: 'Security edge',
        redundancy: profile.hasWarmSpare || profile.firewallCount > 1
            ? 'HA / warm spare captured'
            : profile.firewallCount > 0
            ? 'Single edge device'
            : 'No edge device identified',
        impact: profile.hasWarmSpare || profile.firewallCount > 1
            ? 'Firewall failure should preserve edge service.'
            : 'Firewall failure can interrupt site edge services.',
        validation: profile.hasWarmSpare || profile.firewallCount > 1
            ? 'Validate HA cabling, state sync, licensing, and failover test.'
            : 'Confirm HA pair, warm spare, or accepted single-device risk.',
        ready: profile.hasWarmSpare || profile.firewallCount > 1,
      ),
      (
        domain: 'MDF / Core',
        redundancy: profile.coreSwitchCount > 1
            ? 'Core pair / stack captured'
            : profile.coreSwitchCount == 1
            ? 'Single core switch'
            : 'Core count unknown',
        impact: profile.coreSwitchCount > 1
            ? 'Core device failure should have an alternate control/data path.'
            : 'Core failure can affect campus-wide connectivity.',
        validation: profile.coreSwitchCount > 1
            ? 'Validate stack/virtual pair design, uplinks, and software train.'
            : 'Confirm core redundancy or document accepted outage domain.',
        ready: profile.coreSwitchCount > 1,
      ),
      (
        domain: 'IDF / Access',
        redundancy: profile.accessSwitchCount > 1
            ? '${profile.accessSwitchCount} access switches'
            : profile.accessSwitchCount == 1
            ? 'Single access switch'
            : 'Access count unknown',
        impact: profile.accessSwitchCount > 1
            ? 'Access failure scope can be isolated by IDF/switch.'
            : 'Access failure scope and spare capacity are unclear.',
        validation: profile.accessSwitchCount > 0
            ? 'Map switches to IDFs, uplink pairs, spare ports, and PoE budgets.'
            : 'Capture IDF/access inventory and uplink topology.',
        ready: profile.accessSwitchCount > 0 && profile.idfCount > 0,
      ),
      (
        domain: 'Wireless / PoE',
        redundancy: profile.hasWifi7
            ? profile.hasPoe && profile.hasMultigig
                  ? 'Wi-Fi 7 power/uplink noted'
                  : 'Wi-Fi 7 needs validation'
            : profile.apCount > 0
            ? 'AP estate captured'
            : 'Wireless unknown',
        impact: profile.hasWifi7 && !(profile.hasPoe && profile.hasMultigig)
            ? 'AP performance or power draw may exceed access design.'
            : 'Wireless risk depends on placement, power, and spare ports.',
        validation: profile.hasWifi7
            ? 'Validate UPOE/UPOE+, mGig ports, power supplies, and AP density.'
            : 'Confirm AP generation, PoE class, density, and spare-port plan.',
        ready: profile.hasWifi7
            ? profile.hasPoe && profile.hasMultigig
            : profile.apCount > 0,
      ),
    ];
  }

  String _topologyTypeFor(_TopologyProfile profile) {
    if (profile.siteCount > 1) return 'Multi-site topology';
    if (profile.idfCount > 0 || profile.coreSwitchCount > 0) {
      return 'Campus topology';
    }
    if (profile.firewallCount > 0 || profile.hasDualWan) {
      return 'WAN edge topology';
    }
    return 'Network topology';
  }

  List<String> _readinessSignalLabels(
    List<({String check, String state, bool ready})> readinessItems,
  ) {
    return readinessItems
        .where((item) => item.ready)
        .map((item) => item.check)
        .toList(growable: false);
  }

  List<String> _validationGapLabels(
    List<({String check, String state, bool ready})> readinessItems,
    List<({String metric, String value, String guidance, bool ready})>
    capacityItems,
    List<String> assumptions,
    List<_FailureDomainRow> failureDomains,
  ) {
    final gaps = <String>[
      for (final item in readinessItems)
        if (!item.ready) item.check,
      for (final item in capacityItems)
        if (!item.ready) item.metric,
      for (final item in failureDomains)
        if (!item.ready) 'Failure domain: ${item.domain}',
      if (assumptions.isEmpty) 'Assumptions',
    ];
    return gaps.toSet().toList(growable: false);
  }

  List<String> _topologyReviewChecklistFor({
    required _TopologyProfile profile,
    required List<String> validationGaps,
    required List<_FailureDomainRow> failureDomains,
  }) {
    final items = <String>[
      'Confirm topology scope, site count, MDF/IDF boundaries, and ownership.',
      'Validate WAN handoffs, uplink speeds, routing preference, and failover test plan.',
      'Review HA, warm spare, and failure-domain impact for WAN, security, core, access, and wireless.',
    ];
    if (profile.apCount > 0 || profile.hasWifi7 || profile.hasPoe) {
      items.add(
        'Validate AP count, PoE/UPOE budget, mGig need, spare ports, and IDF-level power headroom.',
      );
    }
    if (profile.switchCount > 0 ||
        profile.firewallCount > 0 ||
        profile.apCount > 0) {
      items.add(
        'Confirm device inventory, model assumptions, licensing, software train, and lifecycle posture.',
      );
    }
    if (validationGaps.isNotEmpty) {
      items.add(
        'Resolve or explicitly accept validation gaps before customer handoff: ${validationGaps.take(3).join(', ')}.',
      );
    }
    if (failureDomains.any((domain) => !domain.ready)) {
      items.add(
        'Document outage impact and mitigation owner for each unresolved failure domain.',
      );
    }
    return items.toSet().toList(growable: false);
  }

  List<String> _topologyHandoffActionsFor({
    required _TopologyProfile profile,
    required List<String> validationGaps,
    required List<String> topologyRiskFlags,
  }) {
    final actions = <String>[
      'Package diagram with inventory, link schedule, assumptions, and validation gaps.',
      'Walk stakeholders through resiliency model, failover path, and outage domains.',
    ];
    if (validationGaps.isNotEmpty) {
      actions.add(
        'Assign owner, due date, and evidence source for each validation gap.',
      );
    }
    if (profile.hasWifi7 || profile.hasUpoe || profile.apCount > 0) {
      actions.add(
        'Confirm Wi-Fi/AP power, UPOE/UPOE+, mGig ports, and switch power supplies before model selection.',
      );
    }
    if (topologyRiskFlags.any((flag) => flag.contains('Lifecycle'))) {
      actions.add(
        'Treat EoX replacement PIDs as migration hints and validate current portfolio fit.',
      );
    }
    return actions.toSet().toList(growable: false);
  }

  List<String> _topologyRiskFlagsFor({
    required _TopologyProfile profile,
    required _DiagramGraph graph,
    required List<String> assumptions,
    required List<String> validationGaps,
    required List<_FailureDomainRow> failureDomains,
  }) {
    final flags = <String>[
      for (final gap in validationGaps.take(6)) 'Validation gap: $gap',
      for (final domain in failureDomains.where((domain) => !domain.ready))
        'Failure domain: ${domain.domain}',
      if (graph.nodes.isEmpty) 'No device inventory captured',
      if (graph.edges.isEmpty) 'No link schedule captured',
      if (assumptions.isEmpty) 'No assumptions captured',
      if (profile.hasWifi7 && !profile.hasUpoe)
        'Wi-Fi 7 APs need explicit UPOE/UPOE+ validation',
      if (profile.hasWifi7 && !profile.hasMultigig)
        'Wi-Fi 7 APs need explicit mGig access validation',
      if (profile.hasDualWan == false && profile.siteCount > 1)
        'Multi-site topology lacks dual-WAN signal',
      if (profile.hasWarmSpare == false && profile.firewallCount > 0)
        'Security edge lacks warm-spare/HA signal',
      'Lifecycle replacements require current-portfolio validation',
    ];
    return flags.toSet().toList(growable: false);
  }

  int _topologyReadinessScoreFor({
    required List<({String check, String state, bool ready})> readinessItems,
    required List<String> validationGaps,
    required List<String> topologyRiskFlags,
    required List<_FailureDomainRow> failureDomains,
    required _DiagramGraph graph,
    required List<String> assumptions,
  }) {
    var score = 60;
    score += readinessItems.where((item) => item.ready).length * 8;
    if (graph.nodes.isNotEmpty) score += 8;
    if (graph.edges.isNotEmpty) score += 8;
    if (assumptions.isNotEmpty) score += 6;
    score -= validationGaps.length * 6;
    score -= failureDomains.where((domain) => !domain.ready).length * 5;
    score -=
        topologyRiskFlags
            .where(
              (flag) =>
                  flag.contains('Wi-Fi 7') ||
                  flag.contains('No ') ||
                  flag.contains('lacks'),
            )
            .length *
        5;
    return math.max(0, math.min(100, score));
  }

  String _topologyReadinessLevelFor(int score, List<String> riskFlags) {
    if (riskFlags.any(
      (flag) =>
          flag.contains('Wi-Fi 7') ||
          flag.contains('Failure domain') ||
          flag.contains('No '),
    )) {
      return score >= 50
          ? 'Needs validation before handoff'
          : 'Discovery inputs required';
    }
    if (score >= 88 && riskFlags.length <= 2) {
      return 'Customer handoff ready';
    }
    if (score >= 72) {
      return 'Ready for architecture review';
    }
    if (score >= 50) {
      return 'Needs validation before handoff';
    }
    return 'Discovery inputs required';
  }

  String _topologyQualityStatusFor(
    int readinessScore,
    List<String> validationGaps,
    List<String> topologyRiskFlags,
  ) {
    if (validationGaps.isEmpty &&
        topologyRiskFlags.length <= 2 &&
        readinessScore >= 88) {
      return 'Customer-review ready';
    }
    if (validationGaps.isNotEmpty || topologyRiskFlags.length > 2) {
      return readinessScore >= 50 ? 'Needs validation' : 'Discovery required';
    }
    if (readinessScore >= 72) return 'Architecture-review ready';
    if (readinessScore >= 50) return 'Needs validation';
    return 'Discovery required';
  }

  List<String> _topologyQualityChecklistFor({
    required _TopologyProfile profile,
    required _DiagramGraph graph,
    required Map<_DiagramNodeRole, List<_DiagramNode>> tiers,
    required List<String> assumptions,
    required List<({String check, String state, bool ready})> readinessItems,
    required List<({String metric, String value, String guidance, bool ready})>
    capacityItems,
    required List<({String from, String to, String link, String validation})>
    linkSchedule,
    required List<({String topic, String guidance, bool critical})> advisories,
    required List<_FailureDomainRow> failureDomains,
  }) {
    return <String>[
      if (graph.nodes.isNotEmpty) 'Device and role inventory embedded',
      if (graph.edges.isNotEmpty) 'Logical links and labels embedded',
      if (tiers.isNotEmpty) 'Design-zone legend embedded',
      if (linkSchedule.isNotEmpty) 'Link validation schedule embedded',
      if (readinessItems.isNotEmpty) 'Readiness scorecard embedded',
      if (capacityItems.isNotEmpty) 'Capacity checks embedded',
      if (failureDomains.isNotEmpty) 'Failure-domain review embedded',
      if (advisories.isNotEmpty) 'Architecture advisories embedded',
      'Customer handoff readiness matrix embedded',
      if (profile.segmentationDomains.isNotEmpty)
        'Segmentation domains and subnet validation embedded',
      if (assumptions.isNotEmpty) 'Assumptions embedded',
    ];
  }

  List<String> _topologyVisualVerificationChecklistFor(
    _TopologyProfile profile,
  ) {
    return <String>[
      'SVG has title, description, viewBox, and embedded metadata',
      'Topology summary, design zones, links, and nodes are visible',
      'Readiness, capacity, validation, and failure-domain panels are visible',
      'Customer handoff readiness matrix is visible',
      if (profile.segmentationDomains.isNotEmpty)
        'VLAN/VRF/subnet segmentation plan is visible',
      if (profile.apCount > 0)
        'Wireless/AP counts and port-power checks are visible',
      if (profile.hasDualWan || profile.hasWarmSpare)
        'Resiliency model and failure-domain posture are visible',
    ];
  }

  List<String> _topologyEvidencePolicyFor(_TopologyProfile profile) {
    return <String>[
      'Lifecycle and EoX data is evidence for dates, not final replacement selection',
      'Replacement choices require current portfolio, PoE, uplink, licensing, and lifecycle validation',
      if (profile.hasWifi7)
        'Wi-Fi 7 designs require explicit UPOE/UPOE+, mGig, and power-supply validation',
      if (profile.segmentationDomains.isNotEmpty)
        'VLAN, VRF, subnet, gateway, DHCP, and ACL assumptions must be validated against customer standards',
      'Customer handoff requires named assumptions, validation gaps, and review owner',
    ];
  }

  List<String> _topologyPublishingMetadataFor(
    int readinessScore,
    List<String> validationGaps,
    List<String> topologyRiskFlags,
  ) {
    return <String>[
      'Readiness score: $readinessScore/100',
      validationGaps.isEmpty
          ? 'No validation gaps detected by parser'
          : 'Validation gaps: ${validationGaps.take(3).join(', ')}',
      topologyRiskFlags.length <= 2
          ? 'Risk posture: review standard topology assumptions'
          : 'Risk posture: ${topologyRiskFlags.take(3).join(', ')}',
    ];
  }

  List<String> _externalHandoffManifestFor({
    required _TopologyProfile profile,
    required List<String> assumptions,
    required int citationCount,
    required String topologyType,
    required String readinessLevel,
    required String qualityStatus,
    required List<String> validationGaps,
    required List<String> topologyRiskFlags,
  }) {
    final publishingGate =
        validationGaps.isEmpty && topologyRiskFlags.length <= 2
        ? 'ready for architecture approval'
        : 'resolve ${math.max(validationGaps.length, topologyRiskFlags.length)} topology review item${math.max(validationGaps.length, topologyRiskFlags.length) == 1 ? '' : 's'}';
    final evidenceStatus = citationCount > 0 && assumptions.isNotEmpty
        ? 'Sources and assumptions attached'
        : citationCount > 0
        ? 'Sources attached, assumptions need owner review'
        : assumptions.isNotEmpty
        ? 'Assumptions captured, sources need validation'
        : 'Sources and assumptions need validation';
    final decisionAsk = switch (topologyType) {
      'Multi-site topology' =>
        'Approve resiliency model, failure-domain posture, and validation owners.',
      'Campus topology' =>
        'Review MDF/IDF design, PoE/uplink assumptions, and implementation readiness.',
      'WAN edge topology' =>
        'Confirm WAN handoffs, HA behavior, and edge ownership before implementation.',
      _ =>
        'Review topology assumptions, validation gaps, and next design step.',
    };
    return [
      'Review owner: Network architecture owner / customer sponsor',
      'Topology type: $topologyType',
      'Review path: Network architecture review -> failure-domain validation -> implementation decision',
      'Handoff readiness: $readinessLevel',
      'Quality status: $qualityStatus',
      'Evidence status: $evidenceStatus',
      'Publishing gate: $publishingGate',
      'Decision ask: $decisionAsk',
      'Source package: ${citationCount == 0 ? 'sources missing' : '$citationCount source item${citationCount == 1 ? '' : 's'} attached'}',
      'Assumption package: ${assumptions.isEmpty ? 'assumptions missing' : '${assumptions.length} assumption${assumptions.length == 1 ? '' : 's'} captured'}',
      if (profile.segmentationDomains.isNotEmpty)
        'Segmentation package: ${profile.segmentationDomains.length} VLAN/VRF/subnet domain${profile.segmentationDomains.length == 1 ? '' : 's'} captured',
      'Capacity package: ${profile.hasWifi7 || profile.hasPoe || profile.hasUpoe ? 'PoE/UPOE and AP power review required' : 'capture AP/PoE requirements if wireless is in scope'}',
    ];
  }

  List<_TopologyHandoffGate> _topologyHandoffReadinessMatrixFor({
    required _TopologyProfile profile,
    required List<String> assumptions,
    required int citationCount,
    required String topologyReadinessLevel,
    required List<String> validationGaps,
    required List<String> topologyRiskFlags,
    required List<_FailureDomainRow> failureDomains,
  }) {
    final capacityReady =
        profile.accessPortCount > 0 &&
        (!profile.hasWifi7 || (profile.hasPoe && profile.hasMultigig));
    final failureReady =
        failureDomains.isNotEmpty && failureDomains.every((item) => item.ready);
    final publishingReady =
        validationGaps.isEmpty && topologyRiskFlags.length <= 2;
    return [
      (
        gate: 'Evidence package',
        signal: citationCount == 0
            ? 'No cited sources attached'
            : '$citationCount source item${citationCount == 1 ? '' : 's'} attached',
        status: citationCount == 0 ? 'Needs evidence' : 'Ready',
        ownerAction: citationCount == 0
            ? 'Attach inventory, design notes, or source evidence.'
            : 'Keep source evidence with the topology handoff package.',
        ready: citationCount > 0,
      ),
      (
        gate: 'Assumptions',
        signal: assumptions.isEmpty
            ? 'No assumptions captured'
            : '${assumptions.length} assumption${assumptions.length == 1 ? '' : 's'} captured',
        status: assumptions.isEmpty ? 'Needs owner review' : 'Ready',
        ownerAction: assumptions.isEmpty
            ? 'Capture topology assumptions and accountable owners.'
            : 'Review assumptions with the customer sponsor.',
        ready: assumptions.isNotEmpty,
      ),
      (
        gate: 'Capacity validation',
        signal: profile.apCount > 0
            ? '${profile.apCount} APs / ${profile.accessPortCount} access ports / ${profile.estimatedApPowerWatts}W est.'
            : profile.accessPortCount > 0
            ? '${profile.accessPortCount} access ports captured'
            : 'Access capacity not captured',
        status: capacityReady ? 'Ready' : 'Needs capacity review',
        ownerAction: capacityReady
            ? 'Confirm PoE, mGig, uplink, and power-supply headroom.'
            : 'Validate AP power, mGig, uplinks, and access-port headroom.',
        ready: capacityReady,
      ),
      (
        gate: 'Failure domains',
        signal: failureDomains.isEmpty
            ? 'No failure-domain review'
            : '${failureDomains.where((item) => item.ready).length}/${failureDomains.length} domains ready',
        status: failureReady ? 'Ready' : 'Needs resiliency review',
        ownerAction: failureReady
            ? 'Confirm failover behavior and operational ownership.'
            : 'Assign owners to unresolved failure-domain risks.',
        ready: failureReady,
      ),
      (
        gate: 'Publishing gate',
        signal: topologyReadinessLevel,
        status: publishingReady ? 'Ready' : 'Needs review',
        ownerAction: publishingReady
            ? 'Proceed to architecture approval review.'
            : 'Resolve validation gaps and high-risk topology flags.',
        ready: publishingReady,
      ),
    ];
  }

  List<String> _designZoneLabels(
    Map<_DiagramNodeRole, List<_DiagramNode>> tiers,
  ) {
    return [
      for (final role in _tierOrder)
        if ((tiers[role] ?? const <_DiagramNode>[]).isNotEmpty)
          _tierLabel(role),
    ];
  }

  void _drawReadinessScorecard(
    StringBuffer buffer,
    List<({String check, String state, bool ready})> items, {
    required int width,
    required int height,
  }) {
    final y = height - 324;
    final readyCount = items.where((item) => item.ready).length;
    buffer.writeln(
      '<g id="topology-readiness" data-readiness-item-count="${items.length}" data-ready-count="$readyCount">',
    );
    buffer.writeln(
      '<rect x="36" y="$y" width="${width - 72}" height="50" rx="12" fill="#141615" stroke="#28302e"/>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 19}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Readiness scorecard</text>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 37}" fill="#78aaa5" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="700">$readyCount/${items.length} review signals captured</text>',
    );
    var x = 232.0;
    for (final item in items) {
      final label = '${item.check}: ${item.state}';
      final widthForLabel = math.min(178.0, 22 + (label.length * 6.2));
      if (x + widthForLabel > width - 36) break;
      buffer
        ..writeln(
          '<rect x="${x.toStringAsFixed(1)}" y="${y + 16}" width="${widthForLabel.toStringAsFixed(1)}" height="20" rx="10" fill="${item.ready ? '#1d342f' : '#302f21'}" stroke="${item.ready ? '#315f55' : '#5c5530'}"/>',
        )
        ..writeln(
          '<text x="${(x + 9).toStringAsFixed(1)}" y="${y + 30}" fill="${item.ready ? '#8dd3bd' : '#e1bb6d'}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9" font-weight="700">${_xml(label)}</text>',
        );
      x += widthForLabel + 8;
    }
    buffer.writeln('</g>');
  }

  void _drawCapacityPanel(
    StringBuffer buffer,
    List<({String metric, String value, String guidance, bool ready})> items,
    _TopologyProfile profile, {
    required int width,
    required int height,
  }) {
    final y = height - 268;
    final visible = items.take(4).toList(growable: false);
    buffer.writeln(
      '<g id="topology-capacity" data-capacity-item-count="${items.length}" data-access-port-count="${profile.accessPortCount}" data-estimated-ap-power-watts="${profile.estimatedApPowerWatts}" data-ap-port-load-percent="${profile.apPortLoadPercent ?? 0}">',
    );
    buffer.writeln(
      '<rect x="36" y="$y" width="${width - 72}" height="50" rx="12" fill="#111413" stroke="#26302d"/>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 19}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Capacity checks</text>',
    );
    var x = 170.0;
    final cardWidth =
        (width - x - 54 - ((visible.length - 1) * 8)) /
        math.max(1, visible.length);
    for (var i = 0; i < visible.length; i++) {
      final item = visible[i];
      final cardX = x + (i * (cardWidth + 8));
      buffer
        ..writeln(
          '<rect x="${cardX.toStringAsFixed(1)}" y="${y + 9}" width="${cardWidth.toStringAsFixed(1)}" height="32" rx="8" fill="${item.ready ? '#182621' : '#2a241b'}" stroke="${item.ready ? '#2e5148' : '#59482b'}"/>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 22}" fill="${item.ready ? '#8dd3bd' : '#e1bb6d'}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9" font-weight="700">${_xml(_shorten('${item.metric}: ${item.value}', 35))}</text>',
        )
        ..writeln(
          '<text x="${(cardX + 8).toStringAsFixed(1)}" y="${y + 36}" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="8">${_xml(_shorten(item.guidance, 42))}</text>',
        );
    }
    buffer.writeln('</g>');
  }

  void _drawInventoryPanel(
    StringBuffer buffer,
    _TopologyProfile profile, {
    required int width,
    required int height,
  }) {
    final y = height - 212;
    final inventory = [
      'Sites ${profile.siteCount}',
      if (profile.mdfCount > 0) 'MDF ${profile.mdfCount}',
      if (profile.idfCount > 0) 'IDF ${profile.idfCount}',
      if (profile.firewallCount > 0) 'Firewalls ${profile.firewallCount}',
      if (profile.coreSwitchCount > 0) 'Core ${profile.coreSwitchCount}',
      if (profile.accessSwitchCount > 0) 'Access ${profile.accessSwitchCount}',
      if (profile.apCount > 0) 'APs ${profile.apCount}',
    ];
    final requirements = [
      if (profile.hasDualWan) 'Dual WAN',
      if (profile.hasWarmSpare) 'Warm spare',
      if (profile.hasPoe) 'PoE/UPOE',
      if (profile.hasMultigig) 'mGig/10G',
      if (profile.hasWifi7) 'Wi-Fi 7',
    ];
    buffer.writeln(
      '<g id="topology-inventory" data-mdf-count="${profile.mdfCount}" data-idf-count="${profile.idfCount}" data-core-switch-count="${profile.coreSwitchCount}" data-access-switch-count="${profile.accessSwitchCount}">',
    );
    buffer.writeln(
      '<rect x="36" y="$y" width="${width - 72}" height="44" rx="12" fill="#111413" stroke="#26302d"/>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 18}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Inventory</text>',
    );
    buffer.writeln(
      '<text x="126" y="${y + 18}" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11">${_xml(inventory.join(' • '))}</text>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 35}" fill="#78aaa5" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="700">${_xml(requirements.isEmpty ? 'Requirements: validate redundancy, power, uplinks, and lifecycle' : 'Requirements: ${requirements.join(' • ')}')}</text>',
    );
    buffer.writeln('</g>');
  }

  void _drawValidationChecklist(
    StringBuffer buffer,
    _TopologyProfile profile, {
    required int width,
    required int height,
  }) {
    final y = height - 150;
    final checks = [
      ('Dual WAN', profile.hasDualWan),
      ('Warm spare', profile.hasWarmSpare),
      ('PoE/UPOE', profile.hasPoe),
      ('mGig', profile.hasMultigig),
      ('Wi-Fi 7', profile.hasWifi7),
    ];
    buffer.writeln(
      '<g id="topology-validation" data-has-dual-wan="${profile.hasDualWan}" data-has-warm-spare="${profile.hasWarmSpare}" data-has-poe="${profile.hasPoe}" data-has-multigig="${profile.hasMultigig}" data-has-wifi7="${profile.hasWifi7}">',
    );
    buffer.writeln(
      '<rect x="36" y="$y" width="${width - 72}" height="50" rx="12" fill="#141615" stroke="#28302e"/>',
    );
    buffer.writeln(
      '<text x="54" y="${y + 20}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Validation checklist</text>',
    );
    var x = 54.0;
    for (final check in checks) {
      final label = '${check.$2 ? '✓' : '!'} ${check.$1}';
      final widthForLabel = 16.0 + (label.length * 7.0);
      buffer
        ..writeln(
          '<rect x="${x.toStringAsFixed(1)}" y="${y + 27}" width="${widthForLabel.toStringAsFixed(1)}" height="16" rx="8" fill="${check.$2 ? '#1d342f' : '#302f21'}" stroke="${check.$2 ? '#315f55' : '#5c5530'}"/>',
        )
        ..writeln(
          '<text x="${(x + 8).toStringAsFixed(1)}" y="${y + 39}" fill="${check.$2 ? '#8dd3bd' : '#e1bb6d'}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="10" font-weight="700">${_xml(label)}</text>',
        );
      x += widthForLabel + 8;
    }
    buffer.writeln('</g>');
  }

  void _drawAssumptions(
    StringBuffer buffer,
    List<String> assumptions, {
    required int width,
    required int height,
  }) {
    final visible = assumptions.take(3).toList(growable: false);
    if (visible.isEmpty) return;
    const x = 36;
    final y = height - 76;
    buffer.writeln(
      '<g id="topology-assumptions" data-assumption-count="${visible.length}">',
    );
    buffer.writeln(
      '<rect x="$x" y="${y - 22}" width="${width - 72}" height="58" rx="12" fill="#171918" stroke="#2b302f"/>',
    );
    buffer.writeln(
      '<text x="${x + 18}" y="${y - 2}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">Assumptions</text>',
    );
    buffer.writeln(
      '<text x="${x + 18}" y="${y + 20}" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11">${_xml(visible.map((item) => _shorten(item, 58)).join(' • '))}</text>',
    );
    buffer.writeln('</g>');
  }

  List<String> _extractAssumptions(String content) {
    final heading = RegExp(
      r'^\s{0,3}#{1,4}\s+assumptions\b.*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(content);
    if (heading == null) return const [];
    final tail = content.substring(heading.end);
    final nextHeading = RegExp(
      r'^\s{0,3}#{1,4}\s+',
      multiLine: true,
    ).firstMatch(tail);
    final block = nextHeading == null
        ? tail
        : tail.substring(0, nextHeading.start);
    return block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('- ') || line.startsWith('* '))
        .map((line) => line.substring(2).trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  _TopologyProfile _profileFrom(String content, ArtifactDocument document) {
    final hasRawContent = content.trim().isNotEmpty;
    final combined = hasRawContent
        ? [content, document.title, ...document.assumptions].join('\n')
        : [
            document.title,
            document.summary,
            for (final section in document.sections) ...[
              section.title,
              section.body,
              ...section.bullets,
            ],
            ...document.assumptions,
          ].join('\n');
    final normalized = combined.toLowerCase();
    final branchCount =
        _countFromText(
          combined,
          RegExp(
            r'(\d+)\s+(?:branches|branch sites|remote sites)',
            caseSensitive: false,
          ),
        ) ??
        0;
    final explicitSiteCount = _countFromText(
      combined,
      RegExp(r'(\d+)\s+(?:sites|campuses|locations)', caseSensitive: false),
    );
    final hasHq = RegExp(
      r'\b(hq|headquarters|mdf|campus)\b',
      caseSensitive: false,
    ).hasMatch(combined);
    final mdfCount =
        _countFromText(
          combined,
          RegExp(r'(\d+)\s+MDFs?', caseSensitive: false),
        ) ??
        (RegExp(r'\b(mdf|core)\b', caseSensitive: false).hasMatch(combined)
            ? 1
            : 0);
    final idfCount =
        _countFromText(
          combined,
          RegExp(r'(\d+)\s+IDFs?', caseSensitive: false),
        ) ??
        0;
    final siteCount = explicitSiteCount ?? branchCount + (hasHq ? 1 : 0);
    final firewallCount = _deviceCount(
      combined,
      RegExp(r'\bMX[A-Za-z0-9-]*\b', caseSensitive: false),
      warmSpareDefault:
          RegExp(r'\bwarm spare\b', caseSensitive: false).hasMatch(combined)
          ? 2
          : 1,
    );
    final coreSwitchCount = _deviceCount(
      combined,
      RegExp(r'\bC95\d{2}[A-Z0-9-]*\b', caseSensitive: false),
    );
    final accessSwitchCount = _deviceCount(
      combined,
      RegExp(r'\bC93\d{2}[A-Z0-9-]*\b', caseSensitive: false),
    );
    final accessPortCount = _accessPortCount(combined, accessSwitchCount);
    final apCount =
        _countFromText(
          combined,
          RegExp(
            r'(\d+)\s+(?:CW9\d{3}[A-Z0-9-]*|aps?|access points?)',
            caseSensitive: false,
          ),
        ) ??
        _deviceCount(
          combined,
          RegExp(r'\bCW9\d{3}[A-Z0-9-]*\b', caseSensitive: false),
        );
    final segmentationDomains = _segmentationDomainsFor(combined);
    final hasSegmentationSignal = RegExp(
      r'\b(vlan|vrf|subnet|cidr|segment|segmentation|ssid|gateway|acl)\b',
      caseSensitive: false,
    ).hasMatch(combined);
    return _TopologyProfile(
      siteCount: siteCount == 0 && branchCount == 0 ? 1 : siteCount,
      mdfCount: mdfCount,
      idfCount: idfCount,
      firewallCount: firewallCount,
      coreSwitchCount: coreSwitchCount,
      accessSwitchCount: accessSwitchCount,
      switchCount: coreSwitchCount + accessSwitchCount,
      apCount: apCount,
      accessPortCount: accessPortCount,
      estimatedApPowerWatts: _estimatedApPowerWatts(
        apCount,
        hasWifi7: RegExp(r'\b(wi-?fi 7|wifi7|cw9\d{3})\b').hasMatch(normalized),
        hasUpoe: RegExp(r'\b(upoe|upoe\+)\b').hasMatch(normalized),
        hasPoe: RegExp(r'\b(poe|upoe|upoe\+)\b').hasMatch(normalized),
      ),
      hasDualWan: RegExp(
        r'\b(dual wan|redundant wan|primary/secondary|two wan)\b',
        caseSensitive: false,
      ).hasMatch(combined),
      hasWarmSpare: RegExp(
        r'\bwarm spare\b',
        caseSensitive: false,
      ).hasMatch(combined),
      hasPoe: RegExp(r'\b(poe|upoe|upoe\+)\b').hasMatch(normalized),
      hasUpoe: RegExp(r'\b(upoe|upoe\+)\b').hasMatch(normalized),
      hasMultigig: RegExp(
        r'\b(mgig|multi-?gig|2\.5g|5g|10g|10gig)\b',
        caseSensitive: false,
      ).hasMatch(combined),
      hasWifi7: RegExp(r'\b(wi-?fi 7|wifi7|cw9\d{3})\b').hasMatch(normalized),
      hasSegmentationSignal: hasSegmentationSignal,
      segmentationDomains: segmentationDomains,
    );
  }

  List<_SegmentationDomain> _segmentationDomainsFor(String content) {
    final domains = <_SegmentationDomain>[];
    final seen = <String>{};
    for (final raw in const LineSplitter().convert(content)) {
      final line = raw
          .trim()
          .replaceFirst(RegExp(r'^[-*]\s*'), '')
          .replaceFirst(RegExp(r'^\d+[.)]\s*'), '');
      if (line.isEmpty) continue;
      if (!RegExp(
        r'\b(vlan|vrf|subnet|cidr|segment|segmentation|ssid)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }
      final name = _segmentationNameFrom(line);
      if (name.isEmpty) continue;
      final subnet = _subnetFrom(line);
      final scope = _segmentationScopeFor(line);
      final ready = subnet.isNotEmpty && !subnet.endsWith('/0');
      final domain = (
        name: name,
        scope: scope,
        subnet: subnet,
        validation: _segmentationValidationFor(line, subnet),
        ready: ready,
      );
      final key = '${domain.name}|${domain.subnet}'.toLowerCase();
      if (!seen.add(key)) continue;
      domains.add(domain);
      if (domains.length >= 8) break;
    }
    return domains;
  }

  String _segmentationNameFrom(String line) {
    final vlanMatch = RegExp(
      r'\bVLAN\s*([0-9]{1,4})\b\s*[:\-–—]?\s*([^,;|()]*)',
      caseSensitive: false,
    ).firstMatch(line);
    if (vlanMatch != null) {
      final number = vlanMatch.group(1)?.trim() ?? '';
      final label = (vlanMatch.group(2) ?? '')
          .replaceAll(RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}\b'), '')
          .replaceAll(
            RegExp(r'\b(subnet|cidr|gateway|acl)\b.*$', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'[-–—:|,\s]+$'), '')
          .trim();
      return label.isEmpty ? 'VLAN $number' : 'VLAN $number $label';
    }
    final vrfMatch = RegExp(
      r'\bVRF\s+([A-Za-z0-9_-]+)\b',
      caseSensitive: false,
    ).firstMatch(line);
    if (vrfMatch != null) {
      return 'VRF ${vrfMatch.group(1)?.trim() ?? ''}'.trim();
    }
    final ssidMatch = RegExp(
      r'\bSSID\s+([A-Za-z0-9 _-]+)',
      caseSensitive: false,
    ).firstMatch(line);
    if (ssidMatch != null) {
      return 'SSID ${ssidMatch.group(1)?.trim() ?? ''}'.trim();
    }
    final subnet = _subnetFrom(line);
    if (subnet.isNotEmpty) return 'Subnet $subnet';
    final segmentMatch = RegExp(
      r'\b(?:segment|segmentation)\s+([A-Za-z0-9 _-]+)',
      caseSensitive: false,
    ).firstMatch(line);
    return segmentMatch?.group(1)?.trim() ?? '';
  }

  String _subnetFrom(String line) {
    return RegExp(
          r'\b\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}\b',
        ).firstMatch(line)?.group(0) ??
        '';
  }

  String _segmentationScopeFor(String line) {
    final normalized = line.toLowerCase();
    if (RegExp(r'\b(guest|guest wi-?fi|visitor)\b').hasMatch(normalized)) {
      return 'Guest access';
    }
    if (RegExp(r'\b(voice|voip|phone)\b').hasMatch(normalized)) {
      return 'Voice';
    }
    if (RegExp(r'\b(iot|camera|printer|ot)\b').hasMatch(normalized)) {
      return 'IoT / OT';
    }
    if (RegExp(r'\b(mgmt|management|admin)\b').hasMatch(normalized)) {
      return 'Management';
    }
    if (RegExp(r'\b(server|data center|datacenter)\b').hasMatch(normalized)) {
      return 'Server / datacenter';
    }
    if (RegExp(r'\b(wireless|ssid|ap)\b').hasMatch(normalized)) {
      return 'Wireless';
    }
    if (RegExp(r'\b(wan|transit|routing)\b').hasMatch(normalized)) {
      return 'WAN / transit';
    }
    if (RegExp(r'\b(user|client|employee|corp)\b').hasMatch(normalized)) {
      return 'Users';
    }
    return 'Segmentation domain';
  }

  String _segmentationValidationFor(String line, String subnet) {
    final needs = <String>[
      if (subnet.isEmpty) 'subnet/CIDR',
      if (!RegExp(
        r'\b(gateway|default gateway)\b',
        caseSensitive: false,
      ).hasMatch(line))
        'gateway',
      if (!RegExp(r'\b(dhcp|scope)\b', caseSensitive: false).hasMatch(line))
        'DHCP scope',
      if (!RegExp(
        r'\b(acl|policy|firewall)\b',
        caseSensitive: false,
      ).hasMatch(line))
        'ACL/policy',
    ];
    if (needs.isEmpty) {
      return 'Validate gateway, DHCP, ACL, and ownership against customer standards.';
    }
    return 'Confirm ${needs.join(', ')} before implementation.';
  }

  int _accessPortCount(String content, int accessSwitchCount) {
    if (accessSwitchCount <= 0) return 0;
    final portsPerSwitch =
        _countFromText(
          content,
          RegExp(r'all\s+(\d+)\s+ports?', caseSensitive: false),
        ) ??
        _countFromText(
          content,
          RegExp(r'(\d+)\s+ports?', caseSensitive: false),
        ) ??
        (RegExp(r'\bC93\d{2}-48', caseSensitive: false).hasMatch(content)
            ? 48
            : 0);
    return portsPerSwitch * accessSwitchCount;
  }

  int _estimatedApPowerWatts(
    int apCount, {
    required bool hasWifi7,
    required bool hasUpoe,
    required bool hasPoe,
  }) {
    if (apCount <= 0) return 0;
    final wattsPerAp = hasWifi7
        ? 30
        : hasUpoe
        ? 30
        : hasPoe
        ? 25
        : 0;
    return wattsPerAp * apCount;
  }

  int _deviceCount(
    String content,
    RegExp tokenExpression, {
    int warmSpareDefault = 1,
  }) {
    final tokenMatches = tokenExpression.allMatches(content).toList();
    if (tokenMatches.isEmpty) return 0;
    var count = 0;
    for (final match in tokenMatches) {
      final beforeStart = math.max(0, match.start - 90);
      final before = content.substring(beforeStart, match.start);
      final samePhrase = before.split(RegExp(r'[,.;\n]')).last;
      final phrase = samePhrase.trim();
      final quantity =
          RegExp(r'(\d+)\s*$').firstMatch(phrase)?.group(1) ??
          RegExp(r'(\d+)').firstMatch(phrase)?.group(1);
      count += int.tryParse(quantity ?? '') ?? warmSpareDefault;
    }
    return count;
  }

  int? _countFromText(String content, RegExp expression) {
    final match = expression.firstMatch(content);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  String _deviceLabel(String content, String prefix, String fallback) {
    final match = RegExp(
      '\\b($prefix[A-Za-z0-9-]*)\\b',
      caseSensitive: false,
    ).firstMatch(content);
    return match?.group(1)?.toUpperCase() ?? fallback;
  }

  String _deviceGroupLabel(
    String content,
    String prefix,
    String fallback,
    int count, {
    String? suffix,
  }) {
    final label = _deviceLabel(content, prefix, fallback);
    if (count <= 1) {
      return suffix == null || label.contains(suffix)
          ? label
          : '$label $suffix';
    }
    return suffix == null ? '${count}x $label' : '${count}x $label $suffix';
  }

  _DiagramNodeRole _roleFor(String value) {
    final normalized = value.toLowerCase();
    if (RegExp(
      r'\b(internet|isp|wan|cloud|saas|mpls)\b',
    ).hasMatch(normalized)) {
      return _DiagramNodeRole.external;
    }
    if (RegExp(
      r'\b(firewall|fw|mx\d+|asa|ftd|edge|router)\b',
    ).hasMatch(normalized)) {
      return _DiagramNodeRole.edge;
    }
    if (RegExp(
      r'\b(core|mdf|c95\d{2}|9500|distribution)\b',
    ).hasMatch(normalized)) {
      return _DiagramNodeRole.core;
    }
    if (RegExp(r'\b(access|idf|switch|c93\d{2}|9300)\b').hasMatch(normalized)) {
      return _DiagramNodeRole.access;
    }
    if (RegExp(
      r'\b(ap\b|aps\b|access point|wifi|wi-fi|client|user|endpoint|cw9\d{3})\b',
    ).hasMatch(normalized)) {
      return _DiagramNodeRole.endpoint;
    }
    if (RegExp(
      r'\b(branch|site|campus|hq|headquarters)\b',
    ).hasMatch(normalized)) {
      return _DiagramNodeRole.site;
    }
    return _DiagramNodeRole.other;
  }

  _DiagramNodeStyle _styleFor(_DiagramNodeRole role) {
    return switch (role) {
      _DiagramNodeRole.external => const _DiagramNodeStyle(
        '#202622',
        '#3d5148',
        '#8dd3bd',
      ),
      _DiagramNodeRole.edge => const _DiagramNodeStyle(
        '#25221d',
        '#5c4a2c',
        '#e1bb6d',
      ),
      _DiagramNodeRole.core => const _DiagramNodeStyle(
        '#1f2528',
        '#37505c',
        '#8fc9df',
      ),
      _DiagramNodeRole.access => const _DiagramNodeStyle(
        '#202328',
        '#39435c',
        '#aab7ef',
      ),
      _DiagramNodeRole.endpoint => const _DiagramNodeStyle(
        '#242126',
        '#4c3d58',
        '#d6adef',
      ),
      _DiagramNodeRole.site => const _DiagramNodeStyle(
        '#232522',
        '#435142',
        '#b5d88d',
      ),
      _DiagramNodeRole.other => const _DiagramNodeStyle(
        '#242625',
        '#3c403f',
        '#b9c0bd',
      ),
    };
  }

  String _tierLabel(_DiagramNodeRole role) {
    return switch (role) {
      _DiagramNodeRole.external => 'WAN / Cloud',
      _DiagramNodeRole.edge => 'Security Edge',
      _DiagramNodeRole.core => 'MDF / Core',
      _DiagramNodeRole.access => 'IDF / Access',
      _DiagramNodeRole.endpoint => 'Wireless / Clients',
      _DiagramNodeRole.site => 'Sites',
      _DiagramNodeRole.other => 'Other',
    };
  }

  String _roleLabel(_DiagramNodeRole role) {
    return switch (role) {
      _DiagramNodeRole.external => 'WAN/CLOUD',
      _DiagramNodeRole.edge => 'EDGE',
      _DiagramNodeRole.core => 'CORE',
      _DiagramNodeRole.access => 'ACCESS',
      _DiagramNodeRole.endpoint => 'ENDPOINT',
      _DiagramNodeRole.site => 'SITE',
      _DiagramNodeRole.other => 'NODE',
    };
  }

  String _shorten(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1).trim()}…';
  }

  String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

class _DiagramGraph {
  final Map<String, _DiagramNode> nodes;
  final List<_DiagramEdge> edges;

  const _DiagramGraph({required this.nodes, required this.edges});
}

class _DiagramNode {
  final String id;
  final String label;
  final _DiagramNodeRole role;

  const _DiagramNode({
    required this.id,
    required this.label,
    required this.role,
  });
}

class _DiagramEdge {
  final String from;
  final String to;
  final String label;

  const _DiagramEdge({required this.from, required this.to, this.label = ''});
}

class _TopologyProfile {
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
  final bool hasDualWan;
  final bool hasWarmSpare;
  final bool hasPoe;
  final bool hasUpoe;
  final bool hasMultigig;
  final bool hasWifi7;
  final bool hasSegmentationSignal;
  final List<_SegmentationDomain> segmentationDomains;

  const _TopologyProfile({
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
    required this.hasDualWan,
    required this.hasWarmSpare,
    required this.hasPoe,
    required this.hasUpoe,
    required this.hasMultigig,
    required this.hasWifi7,
    required this.hasSegmentationSignal,
    required this.segmentationDomains,
  });

  int? get apPortLoadPercent {
    if (accessPortCount <= 0 || apCount <= 0) return null;
    return ((apCount / accessPortCount) * 100).round();
  }

  String get resiliencyLabel {
    if (hasDualWan && hasWarmSpare) return 'Dual WAN + HA';
    if (hasDualWan) return 'Dual WAN';
    if (hasWarmSpare) return 'Warm spare';
    return 'Review';
  }
}

class _Point {
  final double x;
  final double y;

  const _Point(this.x, this.y);
}

enum _DiagramNodeRole { external, site, edge, core, access, endpoint, other }

const _tierOrder = [
  _DiagramNodeRole.site,
  _DiagramNodeRole.external,
  _DiagramNodeRole.edge,
  _DiagramNodeRole.core,
  _DiagramNodeRole.access,
  _DiagramNodeRole.endpoint,
  _DiagramNodeRole.other,
];

class _DiagramNodeStyle {
  final String fill;
  final String stroke;
  final String accent;

  const _DiagramNodeStyle(this.fill, this.stroke, this.accent);
}
