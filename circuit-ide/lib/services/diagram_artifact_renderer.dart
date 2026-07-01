import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/artifact_document.dart';

class DiagramRenderResult {
  final Uint8List bytes;
  final int nodeCount;
  final int edgeCount;
  final List<List<String>> previewRows;

  const DiagramRenderResult({
    required this.bytes,
    required this.nodeCount,
    required this.edgeCount,
    required this.previewRows,
  });
}

class DiagramArtifactRenderer {
  const DiagramArtifactRenderer();

  DiagramRenderResult render({
    required ArtifactDocument document,
    required String content,
  }) {
    final graph = _graphFromMermaid(content);
    final networkGraph = graph.nodes.isEmpty
        ? _graphFromNetworkText(content)
        : graph;
    final resolvedGraph = networkGraph.nodes.isEmpty
        ? _graphFromDocument(document)
        : networkGraph;
    final assumptions = document.assumptions.isNotEmpty
        ? document.assumptions
        : _extractAssumptions(content);
    final svg = _svgFor(
      resolvedGraph,
      title: document.title,
      assumptions: assumptions,
    );
    return DiagramRenderResult(
      bytes: Uint8List.fromList(utf8.encode(svg)),
      nodeCount: resolvedGraph.nodes.length,
      edgeCount: resolvedGraph.edges.length,
      previewRows: [
        const ['From', 'To', 'Label'],
        for (final edge in resolvedGraph.edges.take(8))
          [
            resolvedGraph.nodes[edge.from]?.label ?? edge.from,
            resolvedGraph.nodes[edge.to]?.label ?? edge.to,
            edge.label,
          ],
      ],
    );
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
      add(
        'edge',
        _deviceLabel(content, 'MX', 'Security Edge'),
        _DiagramNodeRole.edge,
      );
    }
    if (hasCore) {
      add(
        'core',
        _deviceLabel(content, 'C95', 'MDF Core'),
        _DiagramNodeRole.core,
      );
    }
    if (hasAccess) {
      final accessModel = _deviceLabel(content, 'C93', 'Access / IDF');
      final label = idfCount == null || idfCount <= 1
          ? accessModel
          : accessModel == 'Access / IDF'
          ? '$idfCount IDFs / Access'
          : '$idfCount IDFs / $accessModel';
      add('access', label, _DiagramNodeRole.access);
    }
    if (hasAps) {
      add(
        'aps',
        _deviceLabel(content, 'CW', 'Wireless APs'),
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
  }) {
    final nodeEntries = graph.nodes.values.toList(growable: false);
    const width = 1180;
    final tiers = _layoutTiers(nodeEntries);
    final maxTierSize = tiers.values.fold<int>(
      1,
      (max, nodes) => nodes.length > max ? nodes.length : max,
    );
    final height = math.max(700, 300 + (maxTierSize * 112));
    final positions = _tierPositions(tiers, width: width, height: height);

    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height" role="img">',
      )
      ..writeln('<title>${_xml(title)}</title>')
      ..writeln(
        '<desc>Network topology diagram generated by CircuitCode. Review assumptions before customer handoff.</desc>',
      )
      ..writeln(
        '<metadata>${_xml(jsonEncode({'generator': 'CircuitCode', 'artifact': 'network_topology_diagram', 'nodeCount': graph.nodes.length, 'edgeCount': graph.edges.length, 'tierCount': tiers.length, 'assumptionCount': assumptions.length}))}</metadata>',
      )
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
      final usableHeight = height - 260;
      for (var i = 0; i < nodes.length; i++) {
        final y = nodes.length == 1
            ? 330.0
            : 170 + (usableHeight * i / (nodes.length - 1));
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
          '<rect class="topology-tier-band" data-tier="${_xml(roles[i].name)}" data-tier-label="${_xml(_tierLabel(roles[i]))}" x="$x" y="112" width="${bandWidth - 12}" height="${height - 220}" rx="18" fill="${i.isEven ? '#151716' : '#181a19'}" stroke="#252928"/>',
        )
        ..writeln(
          '<text x="${x + 18}" y="140" fill="#8f9695" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700" letter-spacing="0">${_xml(_tierLabel(roles[i]))}</text>',
        );
    }
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
