import 'dart:math';
import 'dart:ui';

import '../models/codebase_graph.dart';

/// Force-directed graph layout engine using Coulomb repulsion,
/// Hooke's law attraction, center gravity, and velocity damping.
class GraphLayoutEngine {
  /// Coulomb repulsion strength between all node pairs.
  final double repulsionStrength;

  /// Hooke's law spring constant along edges.
  final double springStrength;

  /// Ideal spring rest length in pixels.
  final double idealLength;

  /// Gravity pull toward center to prevent drift.
  final double gravityStrength;

  /// Velocity damping per tick (0..1).
  final double damping;

  /// Convergence threshold — stop when total kinetic energy falls below this.
  final double convergenceThreshold;

  /// Maximum displacement per tick to prevent explosions.
  final double maxDisplacement;

  GraphLayoutEngine({
    this.repulsionStrength = 5000.0,
    this.springStrength = 0.005,
    this.idealLength = 150.0,
    this.gravityStrength = 0.01,
    this.damping = 0.9,
    this.convergenceThreshold = 0.5,
    this.maxDisplacement = 50.0,
  });

  /// Assign initial random positions within [width] x [height].
  List<GraphNode> initializePositions(
    List<GraphNode> nodes, {
    double width = 1200,
    double height = 800,
  }) {
    final rng = Random(42);
    final centerX = width / 2;
    final centerY = height / 2;
    final spread = min(width, height) * 0.4;

    return [
      for (int i = 0; i < nodes.length; i++)
        nodes[i].copyWith(
          position: Offset(
            centerX + (rng.nextDouble() - 0.5) * spread * 2,
            centerY + (rng.nextDouble() - 0.5) * spread * 2,
          ),
          velocity: Offset.zero,
        ),
    ];
  }

  /// Perform one simulation step.
  /// Returns `true` when the layout has converged (kinetic energy < threshold).
  bool step(List<GraphNode> nodes, List<GraphEdge> edges) {
    if (nodes.isEmpty) return true;

    final forces = List<Offset>.filled(nodes.length, Offset.zero);
    final nodeIndex = <String, int>{};
    for (int i = 0; i < nodes.length; i++) {
      nodeIndex[nodes[i].id] = i;
    }

    // Center of mass for gravity
    double cx = 0, cy = 0;
    for (final node in nodes) {
      cx += node.position.dx;
      cy += node.position.dy;
    }
    cx /= nodes.length;
    cy /= nodes.length;

    // ── Repulsion (Coulomb's law) between all pairs ───────────────────
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final dx = nodes[i].position.dx - nodes[j].position.dx;
        final dy = nodes[i].position.dy - nodes[j].position.dy;
        final distSq = max(dx * dx + dy * dy, 1.0);
        final dist = sqrt(distSq);
        final force = repulsionStrength / distSq;
        final fx = (dx / dist) * force;
        final fy = (dy / dist) * force;
        forces[i] = forces[i].translate(fx, fy);
        forces[j] = forces[j].translate(-fx, -fy);
      }
    }

    // ── Attraction (Hooke's law) along edges ──────────────────────────
    for (final edge in edges) {
      final si = nodeIndex[edge.sourceId];
      final ti = nodeIndex[edge.targetId];
      if (si == null || ti == null) continue;

      final dx = nodes[ti].position.dx - nodes[si].position.dx;
      final dy = nodes[ti].position.dy - nodes[si].position.dy;
      final dist = max(sqrt(dx * dx + dy * dy), 0.1);
      final displacement = dist - idealLength;
      final force = springStrength * displacement;
      final fx = (dx / dist) * force;
      final fy = (dy / dist) * force;
      forces[si] = forces[si].translate(fx, fy);
      forces[ti] = forces[ti].translate(-fx, -fy);
    }

    // ── Gravity toward center ─────────────────────────────────────────
    for (int i = 0; i < nodes.length; i++) {
      final dx = cx - nodes[i].position.dx;
      final dy = cy - nodes[i].position.dy;
      forces[i] = forces[i].translate(
        dx * gravityStrength,
        dy * gravityStrength,
      );
    }

    // ── Apply forces with damping ─────────────────────────────────────
    double totalKineticEnergy = 0;

    for (int i = 0; i < nodes.length; i++) {
      var vx = (nodes[i].velocity.dx + forces[i].dx) * damping;
      var vy = (nodes[i].velocity.dy + forces[i].dy) * damping;

      // Clamp displacement
      final speed = sqrt(vx * vx + vy * vy);
      if (speed > maxDisplacement) {
        vx = (vx / speed) * maxDisplacement;
        vy = (vy / speed) * maxDisplacement;
      }

      final newPos = Offset(
        nodes[i].position.dx + vx,
        nodes[i].position.dy + vy,
      );
      final newVel = Offset(vx, vy);

      // Mutate in place for performance (caller provides mutable list)
      nodes[i] = nodes[i].copyWith(position: newPos, velocity: newVel);

      totalKineticEnergy += vx * vx + vy * vy;
    }

    return totalKineticEnergy < convergenceThreshold;
  }

  /// Arrange nodes in a hierarchical (top-down) layout based on dependency depth.
  List<GraphNode> layoutHierarchical(
    List<GraphNode> nodes,
    List<GraphEdge> edges, {
    double layerSpacing = 120,
    double nodeSpacing = 80,
  }) {
    if (nodes.isEmpty) return nodes;

    final nodeIndex = <String, int>{};
    for (int i = 0; i < nodes.length; i++) {
      nodeIndex[nodes[i].id] = i;
    }

    // Compute depth via BFS from root nodes (nodes with no incoming edges)
    final incomingCount = <String, int>{};
    final children = <String, List<String>>{};
    for (final node in nodes) {
      incomingCount[node.id] = 0;
      children[node.id] = [];
    }
    for (final edge in edges) {
      incomingCount[edge.targetId] = (incomingCount[edge.targetId] ?? 0) + 1;
      children[edge.sourceId]?.add(edge.targetId);
    }

    final depth = <String, int>{};
    final queue = <String>[];
    for (final node in nodes) {
      if ((incomingCount[node.id] ?? 0) == 0) {
        queue.add(node.id);
        depth[node.id] = 0;
      }
    }

    // BFS to assign depths
    int qi = 0;
    while (qi < queue.length) {
      final current = queue[qi++];
      final d = depth[current]!;
      for (final child in children[current] ?? <String>[]) {
        if (!depth.containsKey(child) || depth[child]! < d + 1) {
          depth[child] = d + 1;
          queue.add(child);
        }
      }
    }

    // Assign depth 0 to orphans
    for (final node in nodes) {
      depth.putIfAbsent(node.id, () => 0);
    }

    // Group by layer
    final layers = <int, List<String>>{};
    for (final node in nodes) {
      final d = depth[node.id]!;
      (layers[d] ??= []).add(node.id);
    }

    final maxLayer = layers.keys.fold(0, max);
    final result = List<GraphNode>.from(nodes);

    for (int layer = 0; layer <= maxLayer; layer++) {
      final ids = layers[layer] ?? [];
      final totalWidth = (ids.length - 1) * nodeSpacing;
      final startX = -totalWidth / 2;
      for (int i = 0; i < ids.length; i++) {
        final idx = nodeIndex[ids[i]];
        if (idx == null) continue;
        result[idx] = result[idx].copyWith(
          position: Offset(startX + i * nodeSpacing, layer * layerSpacing),
          velocity: Offset.zero,
        );
      }
    }

    return result;
  }

  /// Arrange nodes in a circular layout grouped by directory cluster.
  List<GraphNode> layoutCircular(
    List<GraphNode> nodes,
    List<GraphCluster> clusters, {
    double radius = 300,
  }) {
    if (nodes.isEmpty) return nodes;

    final nodeIndex = <String, int>{};
    for (int i = 0; i < nodes.length; i++) {
      nodeIndex[nodes[i].id] = i;
    }

    final result = List<GraphNode>.from(nodes);

    if (clusters.isEmpty) {
      // Simple circle for all nodes
      final angleStep = 2 * pi / nodes.length;
      for (int i = 0; i < nodes.length; i++) {
        result[i] = result[i].copyWith(
          position: Offset(
            radius * cos(i * angleStep),
            radius * sin(i * angleStep),
          ),
          velocity: Offset.zero,
        );
      }
      return result;
    }

    // Arrange clusters as segments of the circle
    final clusterAngle = 2 * pi / clusters.length;
    for (int ci = 0; ci < clusters.length; ci++) {
      final cluster = clusters[ci];
      final baseAngle = ci * clusterAngle;
      final ids = cluster.nodeIds;
      if (ids.isEmpty) continue;

      final subAngle = clusterAngle * 0.8 / max(ids.length, 1);
      final startAngle = baseAngle + clusterAngle * 0.1;

      for (int ni = 0; ni < ids.length; ni++) {
        final idx = nodeIndex[ids[ni]];
        if (idx == null) continue;
        final angle = startAngle + ni * subAngle;
        result[idx] = result[idx].copyWith(
          position: Offset(
            radius * cos(angle),
            radius * sin(angle),
          ),
          velocity: Offset.zero,
        );
      }
    }

    return result;
  }
}
