import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/codebase_graph.dart';
import '../../state/codebase_map_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/theme_provider.dart';
import 'graph_painter.dart';
import 'node_detail_popup.dart';

/// Main editor-area view for the codebase map.
/// Wraps an InteractiveViewer with a CustomPaint canvas and handles tap events.
class GraphCanvas extends ConsumerStatefulWidget {
  const GraphCanvas({super.key});

  @override
  ConsumerState<GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends ConsumerState<GraphCanvas> {
  final TransformationController _transformController =
      TransformationController();
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final graphState = ref.watch(codebaseMapProvider);

    if (graphState.isLoading) {
      return Container(
        color: tokens.editorBg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(height: Spacing.lg),
              Text(
                'Building codebase map...',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.sm,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (graphState.nodes.isEmpty) {
      return Container(
        color: tokens.editorBg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 48,
                color: tokens.textMuted.withValues(alpha: 0.3),
              ),
              const SizedBox(height: Spacing.lg),
              Text(
                'No codebase map built yet',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.sm,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Text(
                'Use the Codebase Map panel to build a graph',
                style: TextStyle(
                  color: tokens.textMuted.withValues(alpha: 0.6),
                  fontSize: FontSizes.xs,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (graphState.error != null) {
      return Container(
        color: tokens.editorBg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 32,
                color: tokens.error.withValues(alpha: 0.6),
              ),
              const SizedBox(height: Spacing.md),
              Text(
                graphState.error!,
                style: TextStyle(color: tokens.error, fontSize: FontSizes.sm),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Main graph canvas
        Container(
          color: tokens.editorBg,
          child: InteractiveViewer(
            transformationController: _transformController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(500),
            minScale: 0.1,
            maxScale: 5.0,
            child: GestureDetector(
              onTapDown: (details) => _handleTap(details, graphState),
              child: SizedBox(
                width: _computeCanvasWidth(graphState),
                height: _computeCanvasHeight(graphState),
                child: CustomPaint(
                  painter: GraphPainter(
                    nodes: graphState.nodes,
                    edges: graphState.edges,
                    clusters: graphState.clusters,
                    selectedNodeId: graphState.selectedNodeId,
                    highlightedNodeIds: graphState.highlightedNodeIds,
                    tokens: tokens,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Layout running indicator
        if (graphState.isLayoutRunning)
          Positioned(
            top: Spacing.md,
            right: Spacing.md,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              decoration: BoxDecoration(
                color: tokens.bgLight,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: tokens.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: tokens.accent,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    'Simulating layout...',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xxs,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Node detail popup
        if (graphState.selectedNodeId != null)
          Positioned(
            bottom: Spacing.lg,
            left: Spacing.lg,
            child: NodeDetailPopup(nodeId: graphState.selectedNodeId!),
          ),
      ],
    );
  }

  double _computeCanvasWidth(CodebaseGraphState graphState) {
    if (graphState.nodes.isEmpty) return 1200;
    double minX = double.infinity, maxX = double.negativeInfinity;
    for (final node in graphState.nodes) {
      minX = min(minX, node.position.dx);
      maxX = max(maxX, node.position.dx);
    }
    return max(1200, (maxX - minX) + 400);
  }

  double _computeCanvasHeight(CodebaseGraphState graphState) {
    if (graphState.nodes.isEmpty) return 800;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final node in graphState.nodes) {
      minY = min(minY, node.position.dy);
      maxY = max(maxY, node.position.dy);
    }
    return max(800, (maxY - minY) + 400);
  }

  void _handleTap(TapDownDetails details, CodebaseGraphState graphState) {
    // Transform screen coordinates to graph-space using inverse matrix
    Offset scenePoint;
    try {
      final inverseMatrix = Matrix4.inverted(_transformController.value);
      scenePoint = MatrixUtils.transformPoint(
        inverseMatrix,
        details.localPosition,
      );
    } catch (_) {
      // Matrix is singular — fall back to local position
      scenePoint = details.localPosition;
    }

    // Find nearest node within hit radius
    const hitRadius = 20.0;
    GraphNode? hitNode;
    double minDist = double.infinity;

    for (final node in graphState.nodes) {
      final dx = node.position.dx - scenePoint.dx;
      final dy = node.position.dy - scenePoint.dy;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < hitRadius && dist < minDist) {
        minDist = dist;
        hitNode = node;
      }
    }

    final now = DateTime.now();
    final isDoubleClick =
        _lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 400 &&
        _lastTapPosition != null &&
        (details.localPosition - _lastTapPosition!).distance < 20;

    _lastTapTime = now;
    _lastTapPosition = details.localPosition;

    if (hitNode != null) {
      if (isDoubleClick) {
        // Double-click → open file in editor
        if (hitNode.type == GraphNodeType.file) {
          ref.read(editorProvider.notifier).openFile(hitNode.fullPath);
        }
      } else {
        // Single click → select node
        ref.read(codebaseMapProvider.notifier).selectNode(hitNode.id);
      }
    } else {
      // Clicked empty space → clear selection
      ref.read(codebaseMapProvider.notifier).clearSelection();
    }
  }
}
