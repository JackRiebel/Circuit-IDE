import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/codebase_graph.dart';
import '../services/graph_layout_engine.dart';
import '../services/import_parser.dart';
import 'connection_provider.dart';
import 'file_tree_provider.dart';

/// Cluster colors for directory groups.
const _clusterColors = [
  Color(0xFF56B6C2),
  Color(0xFF4EC9B0),
  Color(0xFFDCDCAA),
  Color(0xFF569CD6),
  Color(0xFFE06C75),
  Color(0xFFC678DD),
  Color(0xFFD19A66),
  Color(0xFFA6E22E),
  Color(0xFF61AFEF),
  Color(0xFFE5C07B),
];

/// Directories to ignore when building the graph.
const _ignoredDirs = {
  '.git', '.dart_tool', 'build', 'node_modules', '__pycache__',
  '.venv', 'venv', '.idea', '.vscode', 'target', '.gradle',
  '.cache', 'dist', '.next', '.nuxt', 'coverage',
};

/// File extensions to ignore.
const _ignoreExtensions = {
  '.lock', '.log', '.cache', '.pyc', '.class', '.o', '.obj',
  '.exe', '.dll', '.so', '.dylib', '.png', '.jpg', '.jpeg',
  '.gif', '.ico', '.svg', '.woff', '.woff2', '.ttf', '.eot',
};

class CodebaseMapNotifier extends Notifier<CodebaseGraphState> {
  Timer? _layoutTimer;
  final GraphLayoutEngine _engine = GraphLayoutEngine();

  @override
  CodebaseGraphState build() => const CodebaseGraphState();

  /// Build the full graph from project files.
  Future<void> buildGraph() async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) {
      state = state.copyWith(error: 'No project opened');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      // 1. Walk project files
      final files = await _collectFiles(rootPath);

      // 2. Create nodes
      final nodes = <GraphNode>[];
      final nodeById = <String, GraphNode>{};

      for (final file in files) {
        final relativePath = p.relative(file.path, from: rootPath);
        final ext = p.extension(file.path).toLowerCase();
        final dir = p.dirname(relativePath);
        final node = GraphNode(
          id: relativePath,
          label: p.basename(file.path),
          fullPath: file.path,
          type: GraphNodeType.file,
          extension: ext,
          directory: dir == '.' ? '' : dir,
        );
        nodes.add(node);
        nodeById[relativePath] = node;
      }

      // 3. Parse imports and create edges
      final parser = ImportParser(rootPath: rootPath);
      final edges = <GraphEdge>[];
      final externalNodes = <String, GraphNode>{};

      for (final file in files) {
        final relativePath = p.relative(file.path, from: rootPath);
        String content;
        try {
          content = await file.readAsString();
        } catch (_) {
          continue;
        }

        final imports = parser.parseFile(file.path, content);
        for (final imp in imports) {
          String targetId;

          if (imp.isRelative) {
            // Resolve to relative path from root
            final absTarget = p.isAbsolute(imp.targetPath)
                ? imp.targetPath
                : p.normalize(p.join(p.dirname(file.path), imp.targetPath));
            targetId = p.relative(absTarget, from: rootPath);
          } else {
            targetId = imp.targetPath;
          }

          // Create external node if target is not in our file set
          if (!nodeById.containsKey(targetId) &&
              !externalNodes.containsKey(targetId)) {
            final extNode = GraphNode(
              id: targetId,
              label: _shortenExternalLabel(targetId),
              fullPath: targetId,
              type: GraphNodeType.externalPackage,
              extension: '',
              size: 5.0,
            );
            externalNodes[targetId] = extNode;
          }

          edges.add(GraphEdge(
            sourceId: relativePath,
            targetId: targetId,
            importStatement: imp.rawStatement,
            isRelative: imp.isRelative,
          ));
        }
      }

      // Combine all nodes
      final allNodes = [...nodes, ...externalNodes.values];

      // 4. Build clusters from directories
      final dirMap = <String, List<String>>{};
      for (final node in nodes) {
        final dir = node.directory ?? '';
        (dirMap[dir] ??= []).add(node.id);
      }

      final clusters = <GraphCluster>[];
      int colorIdx = 0;
      for (final entry in dirMap.entries) {
        clusters.add(GraphCluster(
          directoryPath: entry.key,
          label: entry.key.isEmpty ? '(root)' : entry.key,
          color: _clusterColors[colorIdx % _clusterColors.length],
          nodeIds: entry.value,
        ));
        colorIdx++;
      }

      // 5. Initialize positions and start layout
      final positioned = _engine.initializePositions(allNodes);

      state = state.copyWith(
        nodes: positioned,
        edges: edges,
        clusters: clusters,
        isLoading: false,
        isLayoutRunning: true,
      );

      _startLayoutSimulation();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to build graph: $e',
      );
    }
  }

  /// Collect all source files in the project, respecting ignore patterns.
  Future<List<File>> _collectFiles(String rootPath) async {
    final files = <File>[];
    await _walkDirectory(Directory(rootPath), files);
    return files;
  }

  Future<void> _walkDirectory(Directory dir, List<File> files) async {
    try {
      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);
        if (name.startsWith('.') && name != '.gitignore') continue;

        if (entity is Directory) {
          if (_ignoredDirs.contains(name)) continue;
          await _walkDirectory(entity, files);
        } else if (entity is File) {
          final ext = p.extension(name).toLowerCase();
          if (_ignoreExtensions.contains(ext)) continue;
          files.add(entity);
        }
      }
    } catch (_) {
      // Skip unreadable directories
    }
  }

  String _shortenExternalLabel(String path) {
    // e.g., "package:flutter/material.dart" → "flutter/material"
    if (path.startsWith('package:')) {
      return path.substring(8).replaceAll('.dart', '');
    }
    if (path.startsWith('dart:')) return path;
    // For JS packages like "react", "lodash"
    final parts = path.split('/');
    return parts.length > 2 ? '${parts[0]}/${parts[1]}' : path;
  }

  /// Start the physics simulation timer.
  void _startLayoutSimulation() {
    _layoutTimer?.cancel();
    int ticks = 0;
    const maxTicks = 300;

    _layoutTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (timer) {
        ticks++;
        final mutableNodes = List<GraphNode>.from(state.nodes);
        final converged = _engine.step(mutableNodes, state.edges);

        // Update cluster bounds
        final updatedClusters = _computeClusterBounds(
          state.clusters,
          mutableNodes,
        );

        state = state.copyWith(
          nodes: mutableNodes,
          clusters: updatedClusters,
        );

        if (converged || ticks >= maxTicks) {
          timer.cancel();
          _layoutTimer = null;
          state = state.copyWith(isLayoutRunning: false);
        }
      },
    );
  }

  List<GraphCluster> _computeClusterBounds(
    List<GraphCluster> clusters,
    List<GraphNode> nodes,
  ) {
    final nodeMap = <String, GraphNode>{};
    for (final n in nodes) {
      nodeMap[n.id] = n;
    }

    return [
      for (final cluster in clusters)
        () {
          final clusterNodes = cluster.nodeIds
              .map((id) => nodeMap[id])
              .whereType<GraphNode>()
              .toList();
          if (clusterNodes.isEmpty) return cluster;

          double minX = double.infinity, minY = double.infinity;
          double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
          for (final n in clusterNodes) {
            minX = min(minX, n.position.dx);
            minY = min(minY, n.position.dy);
            maxX = max(maxX, n.position.dx);
            maxY = max(maxY, n.position.dy);
          }
          const padding = 20.0;
          return cluster.copyWith(
            bounds: Rect.fromLTRB(
              minX - padding,
              minY - padding,
              maxX + padding,
              maxY + padding,
            ),
          );
        }(),
    ];
  }

  /// Select a node and highlight its connected edges.
  void selectNode(String id) {
    final highlighted = <String>{id};
    for (final edge in state.edges) {
      if (edge.sourceId == id) highlighted.add(edge.targetId);
      if (edge.targetId == id) highlighted.add(edge.sourceId);
    }

    final updatedNodes = [
      for (final node in state.nodes)
        node.copyWith(isSelected: node.id == id),
    ];

    state = state.copyWith(
      nodes: updatedNodes,
      selectedNodeId: id,
      highlightedNodeIds: highlighted,
      aiExplanation: null,
    );
  }

  /// Clear selection.
  void clearSelection() {
    final updatedNodes = [
      for (final node in state.nodes) node.copyWith(isSelected: false),
    ];
    state = CodebaseGraphState(
      nodes: updatedNodes,
      edges: state.edges,
      clusters: state.clusters,
      isLoading: false,
      isLayoutRunning: state.isLayoutRunning,
      selectedNodeId: null,
      highlightedNodeIds: const {},
      zoom: state.zoom,
      panOffset: state.panOffset,
      viewMode: state.viewMode,
      aiExplanation: null,
      error: state.error,
    );
  }

  /// Ask AI to explain a node's role in the codebase.
  Future<void> explainNode(String nodeId) async {
    final node = state.nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return;

    state = state.copyWith(aiExplanation: 'Analyzing...');

    // Gather import context
    final inEdges = state.edges.where((e) => e.targetId == nodeId).toList();
    final outEdges = state.edges.where((e) => e.sourceId == nodeId).toList();

    final prompt = '''Explain the role of this file in the codebase.
File: ${node.id}
Extension: ${node.extension}
Directory: ${node.directory ?? '(root)'}
Imports (${outEdges.length}): ${outEdges.map((e) => e.targetId).take(10).join(', ')}
Imported by (${inEdges.length}): ${inEdges.map((e) => e.sourceId).take(10).join(', ')}

Give a brief 2-3 sentence explanation of what this file likely does and its role in the architecture.''';

    try {
      final service = ref.read(agentServiceProvider);
      if (!service.isConnected) {
        state = state.copyWith(
          aiExplanation: 'AI is not connected. Connect to an AI provider first.',
        );
        return;
      }
      final response = await service.sendOneShot(
        prompt,
        systemPrompt:
            'You are a code analysis assistant. Be concise and precise.',
      );

      if (response != null) {
        state = state.copyWith(aiExplanation: response);
        // Also annotate the node
        final updatedNodes = [
          for (final n in state.nodes)
            n.id == nodeId ? n.copyWith(aiAnnotation: response) : n,
        ];
        state = state.copyWith(nodes: updatedNodes);
      } else {
        state = state.copyWith(
          aiExplanation: 'AI returned no response.',
        );
      }
    } catch (e) {
      state = state.copyWith(aiExplanation: 'Error: $e');
    }
  }

  /// Switch view mode and re-layout.
  void setViewMode(GraphViewMode mode) {
    state = state.copyWith(viewMode: mode);

    switch (mode) {
      case GraphViewMode.force:
        // Re-run force layout
        final repositioned = _engine.initializePositions(state.nodes);
        state = state.copyWith(
          nodes: repositioned,
          isLayoutRunning: true,
        );
        _startLayoutSimulation();
      case GraphViewMode.hierarchical:
        final laid = _engine.layoutHierarchical(state.nodes, state.edges);
        final clusters = _computeClusterBounds(state.clusters, laid);
        state = state.copyWith(
          nodes: laid,
          clusters: clusters,
          isLayoutRunning: false,
        );
      case GraphViewMode.circular:
        final laid = _engine.layoutCircular(state.nodes, state.clusters);
        final clusters = _computeClusterBounds(state.clusters, laid);
        state = state.copyWith(
          nodes: laid,
          clusters: clusters,
          isLayoutRunning: false,
        );
    }
  }

  /// Update zoom level.
  void setZoom(double zoom) {
    state = state.copyWith(zoom: zoom.clamp(0.1, 5.0));
  }

  /// Update pan offset.
  void setPanOffset(Offset offset) {
    state = state.copyWith(panOffset: offset);
  }

  /// Stop layout simulation and clean up.
  void dispose() {
    _layoutTimer?.cancel();
    _layoutTimer = null;
  }
}

final codebaseMapProvider =
    NotifierProvider<CodebaseMapNotifier, CodebaseGraphState>(
  CodebaseMapNotifier.new,
);
