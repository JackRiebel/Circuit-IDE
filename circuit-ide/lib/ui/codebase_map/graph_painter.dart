import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/codebase_graph.dart';
import '../../theme/theme_tokens.dart';
import 'codebase_map_panel.dart';

/// CustomPainter that renders the codebase dependency graph.
///
/// Draws:
/// - Cluster bounds as semi-transparent rectangles with directory labels
/// - Edges as lines (gray, lighter for external/non-relative imports)
/// - Nodes as circles colored by file extension
/// - Selected node with accent glow
/// - Node labels (filename) positioned below each node
class GraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<GraphCluster> clusters;
  final String? selectedNodeId;
  final Set<String> highlightedNodeIds;
  final ThemeTokens tokens;

  GraphPainter({
    required this.nodes,
    required this.edges,
    required this.clusters,
    this.selectedNodeId,
    this.highlightedNodeIds = const {},
    required this.tokens,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawClusters(canvas);
    _drawEdges(canvas);
    _drawNodes(canvas);
    _drawLabels(canvas);
  }

  // ── Clusters ─────────────────────────────────────────────────────────

  void _drawClusters(Canvas canvas) {
    for (final cluster in clusters) {
      if (cluster.bounds == Rect.zero || cluster.nodeIds.isEmpty) continue;

      final paint = Paint()
        ..color = cluster.color.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = cluster.color.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      final rrect = RRect.fromRectAndRadius(
        cluster.bounds,
        const Radius.circular(6),
      );
      canvas.drawRRect(rrect, paint);
      canvas.drawRRect(rrect, borderPaint);

      // Directory label
      final textPainter = TextPainter(
        text: TextSpan(
          text: cluster.label,
          style: TextStyle(
            color: cluster.color.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: cluster.bounds.width - 12);
      textPainter.paint(
        canvas,
        Offset(cluster.bounds.left + 6, cluster.bounds.top + 4),
      );
    }
  }

  // ── Edges ────────────────────────────────────────────────────────────

  void _drawEdges(Canvas canvas) {
    final nodePositions = <String, Offset>{};
    for (final node in nodes) {
      nodePositions[node.id] = node.position;
    }

    for (final edge in edges) {
      final sourcePos = nodePositions[edge.sourceId];
      final targetPos = nodePositions[edge.targetId];
      if (sourcePos == null || targetPos == null) continue;

      final isHighlighted =
          highlightedNodeIds.contains(edge.sourceId) &&
          highlightedNodeIds.contains(edge.targetId);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHighlighted ? 1.5 : 0.5;

      if (isHighlighted) {
        paint.color = tokens.accent.withValues(alpha: 0.6);
      } else if (edge.isRelative) {
        paint.color = tokens.textMuted.withValues(alpha: 0.15);
      } else {
        paint.color = tokens.textMuted.withValues(alpha: 0.08);
      }

      canvas.drawLine(sourcePos, targetPos, paint);
    }
  }

  // ── Nodes ────────────────────────────────────────────────────────────

  void _drawNodes(Canvas canvas) {
    for (final node in nodes) {
      final isSelected = node.id == selectedNodeId;
      final isHighlighted = highlightedNodeIds.contains(node.id);
      final nodeColor = node.type == GraphNodeType.externalPackage
          ? tokens.textMuted.withValues(alpha: 0.3)
          : colorForExtension(node.extension);

      // Glow for selected node
      if (isSelected) {
        final glowPaint = Paint()
          ..color = tokens.accent.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(node.position, node.size + 4, glowPaint);
      }

      // Node circle
      final fillPaint = Paint()
        ..color = isHighlighted ? nodeColor : nodeColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(node.position, node.size, fillPaint);

      // Border for selected
      if (isSelected) {
        final borderPaint = Paint()
          ..color = tokens.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(node.position, node.size + 1, borderPaint);
      }
    }
  }

  // ── Labels ───────────────────────────────────────────────────────────

  void _drawLabels(Canvas canvas) {
    for (final node in nodes) {
      // Skip labels for external packages (too noisy)
      if (node.type == GraphNodeType.externalPackage) continue;

      final isSelected = node.id == selectedNodeId;
      final isHighlighted = highlightedNodeIds.contains(node.id);

      final textPainter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(
            color: isSelected
                ? tokens.textPrimary
                : isHighlighted
                ? tokens.textSecondary
                : tokens.textMuted.withValues(alpha: 0.6),
            fontSize: isSelected ? 10 : 8,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 120);

      // Position label below the node, centered
      final labelOffset = Offset(
        node.position.dx - textPainter.width / 2,
        node.position.dy + node.size + 4,
      );
      textPainter.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.clusters != clusters ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.highlightedNodeIds != highlightedNodeIds;
  }
}
