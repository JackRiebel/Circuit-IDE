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
    final resolvedGraph = graph.nodes.isEmpty
        ? _graphFromDocument(document)
        : graph;
    final svg = _svgFor(resolvedGraph, title: document.title);
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

  _DiagramGraph _graphFromDocument(ArtifactDocument document) {
    final nodes = <String, _DiagramNode>{};
    final edges = <_DiagramEdge>[];
    nodes['artifact'] = _DiagramNode(id: 'artifact', label: document.title);
    final sections = document.sections.take(8).toList(growable: false);
    if (sections.isEmpty) {
      nodes['summary'] = const _DiagramNode(id: 'summary', label: 'Summary');
      edges.add(const _DiagramEdge(from: 'artifact', to: 'summary'));
      return _DiagramGraph(nodes: nodes, edges: edges);
    }
    for (var i = 0; i < sections.length; i++) {
      final id = 'section_${i + 1}';
      nodes[id] = _DiagramNode(id: id, label: sections[i].title);
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
    return _DiagramNode(id: id, label: label.trim());
  }

  String _svgFor(_DiagramGraph graph, {required String title}) {
    final nodeEntries = graph.nodes.values.toList(growable: false);
    final width = math.max(920, nodeEntries.length * 150 + 160);
    const height = 620;
    final positions = <String, _Point>{};
    if (nodeEntries.length == 1) {
      positions[nodeEntries.single.id] = const _Point(460, 300);
    } else {
      final radius = math.min(width / 2 - 140, 220).toDouble();
      final centerX = width / 2;
      const centerY = 330.0;
      for (var i = 0; i < nodeEntries.length; i++) {
        final angle = (-math.pi / 2) + (2 * math.pi * i / nodeEntries.length);
        positions[nodeEntries[i].id] = _Point(
          centerX + radius * math.cos(angle),
          centerY + radius * math.sin(angle),
        );
      }
    }

    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height" role="img">',
      )
      ..writeln('<title>${_xml(title)}</title>')
      ..writeln('<rect width="100%" height="100%" rx="20" fill="#101111"/>')
      ..writeln('<rect x="0" y="0" width="8" height="$height" fill="#78aaa5"/>')
      ..writeln(
        '<text x="36" y="54" fill="#f2f2ef" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="24" font-weight="700">${_xml(title)}</text>',
      )
      ..writeln(
        '<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto"><path d="M0,0 L0,6 L9,3 z" fill="#8f9695"/></marker></defs>',
      );

    for (final edge in graph.edges) {
      final from = positions[edge.from];
      final to = positions[edge.to];
      if (from == null || to == null) continue;
      buffer.writeln(
        '<line x1="${from.x}" y1="${from.y}" x2="${to.x}" y2="${to.y}" stroke="#6f7775" stroke-width="2" marker-end="url(#arrow)"/>',
      );
      if (edge.label.isNotEmpty) {
        buffer.writeln(
          '<text x="${(from.x + to.x) / 2}" y="${(from.y + to.y) / 2 - 8}" fill="#b9c0bd" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12" text-anchor="middle">${_xml(edge.label)}</text>',
        );
      }
    }

    for (final node in nodeEntries) {
      final point = positions[node.id] ?? const _Point(460, 300);
      buffer
        ..writeln(
          '<rect x="${point.x - 86}" y="${point.y - 30}" width="172" height="60" rx="12" fill="#242625" stroke="#3c403f"/>',
        )
        ..writeln(
          '<text x="${point.x}" y="${point.y + 5}" fill="#f5f4f0" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="14" font-weight="600" text-anchor="middle">${_xml(_shorten(node.label, 26))}</text>',
        );
    }

    buffer.writeln('</svg>');
    return buffer.toString();
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

  const _DiagramNode({required this.id, required this.label});
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
