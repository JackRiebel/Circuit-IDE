import 'dart:ui';

enum GraphNodeType { file, directory, externalPackage }

enum GraphViewMode { force, hierarchical, circular }

class GraphNode {
  final String id;
  final String label;
  final String fullPath;
  final GraphNodeType type;
  final String extension;
  final String? directory;
  final Offset position;
  final Offset velocity;
  final bool isSelected;
  final String? aiAnnotation;
  final double size;

  const GraphNode({
    required this.id,
    required this.label,
    required this.fullPath,
    required this.type,
    this.extension = '',
    this.directory,
    this.position = Offset.zero,
    this.velocity = Offset.zero,
    this.isSelected = false,
    this.aiAnnotation,
    this.size = 8.0,
  });

  GraphNode copyWith({
    Offset? position,
    Offset? velocity,
    bool? isSelected,
    String? aiAnnotation,
    double? size,
  }) {
    return GraphNode(
      id: id,
      label: label,
      fullPath: fullPath,
      type: type,
      extension: extension,
      directory: directory,
      position: position ?? this.position,
      velocity: velocity ?? this.velocity,
      isSelected: isSelected ?? this.isSelected,
      aiAnnotation: aiAnnotation ?? this.aiAnnotation,
      size: size ?? this.size,
    );
  }
}

class GraphEdge {
  final String sourceId;
  final String targetId;
  final String importStatement;
  final bool isRelative;

  const GraphEdge({
    required this.sourceId,
    required this.targetId,
    this.importStatement = '',
    this.isRelative = true,
  });
}

class GraphCluster {
  final String directoryPath;
  final String label;
  final Color color;
  final List<String> nodeIds;
  final Rect bounds;

  const GraphCluster({
    required this.directoryPath,
    required this.label,
    required this.color,
    this.nodeIds = const [],
    this.bounds = Rect.zero,
  });

  GraphCluster copyWith({List<String>? nodeIds, Rect? bounds}) {
    return GraphCluster(
      directoryPath: directoryPath,
      label: label,
      color: color,
      nodeIds: nodeIds ?? this.nodeIds,
      bounds: bounds ?? this.bounds,
    );
  }
}

class CodebaseGraphState {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<GraphCluster> clusters;
  final bool isLoading;
  final bool isLayoutRunning;
  final String? selectedNodeId;
  final Set<String> highlightedNodeIds;
  final double zoom;
  final Offset panOffset;
  final GraphViewMode viewMode;
  final String? aiExplanation;
  final String? error;

  const CodebaseGraphState({
    this.nodes = const [],
    this.edges = const [],
    this.clusters = const [],
    this.isLoading = false,
    this.isLayoutRunning = false,
    this.selectedNodeId,
    this.highlightedNodeIds = const {},
    this.zoom = 1.0,
    this.panOffset = Offset.zero,
    this.viewMode = GraphViewMode.force,
    this.aiExplanation,
    this.error,
  });

  CodebaseGraphState copyWith({
    List<GraphNode>? nodes,
    List<GraphEdge>? edges,
    List<GraphCluster>? clusters,
    bool? isLoading,
    bool? isLayoutRunning,
    String? selectedNodeId,
    Set<String>? highlightedNodeIds,
    double? zoom,
    Offset? panOffset,
    GraphViewMode? viewMode,
    String? aiExplanation,
    String? error,
  }) {
    return CodebaseGraphState(
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      clusters: clusters ?? this.clusters,
      isLoading: isLoading ?? this.isLoading,
      isLayoutRunning: isLayoutRunning ?? this.isLayoutRunning,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
      highlightedNodeIds: highlightedNodeIds ?? this.highlightedNodeIds,
      zoom: zoom ?? this.zoom,
      panOffset: panOffset ?? this.panOffset,
      viewMode: viewMode ?? this.viewMode,
      aiExplanation: aiExplanation ?? this.aiExplanation,
      error: error ?? this.error,
    );
  }

  CodebaseGraphState clearSelection() {
    return CodebaseGraphState(
      nodes: nodes,
      edges: edges,
      clusters: clusters,
      isLoading: isLoading,
      isLayoutRunning: isLayoutRunning,
      selectedNodeId: null,
      highlightedNodeIds: const {},
      zoom: zoom,
      panOffset: panOffset,
      viewMode: viewMode,
      aiExplanation: null,
      error: error,
    );
  }
}
