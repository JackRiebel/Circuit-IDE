import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/codebase_graph.dart';
import '../../state/codebase_map_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/theme_provider.dart';
import 'codebase_map_panel.dart';

/// Overlay popup that appears when a node is selected.
/// Shows file info, import counts, and AI explanation controls.
class NodeDetailPopup extends ConsumerWidget {
  final String nodeId;

  const NodeDetailPopup({super.key, required this.nodeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final graphState = ref.watch(codebaseMapProvider);

    final node = graphState.nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return const SizedBox.shrink();

    final inCount = graphState.edges.where((e) => e.targetId == nodeId).length;
    final outCount = graphState.edges.where((e) => e.sourceId == nodeId).length;

    return Container(
      width: 320,
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: tokens.bgMain,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header: file name + close button
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorForExtension(node.extension),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      node.label,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => ref
                          .read(codebaseMapProvider.notifier)
                          .clearSelection(),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),

              // Full path
              Text(
                node.id,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                  fontFamily: 'JetBrains Mono',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Spacing.md),

              // Stats row: extension badge + import counts
              Row(
                children: [
                  // Extension badge
                  if (node.extension.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorForExtension(
                          node.extension,
                        ).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(Radii.xs),
                        border: Border.all(
                          color: colorForExtension(
                            node.extension,
                          ).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        node.extension,
                        style: TextStyle(
                          color: colorForExtension(node.extension),
                          fontSize: FontSizes.xxs,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                  const SizedBox(width: Spacing.md),
                  Icon(Icons.arrow_downward, size: 11, color: tokens.textMuted),
                  const SizedBox(width: 2),
                  Text(
                    '$inCount in',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xxs,
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Icon(Icons.arrow_upward, size: 11, color: tokens.textMuted),
                  const SizedBox(width: 2),
                  Text(
                    '$outCount out',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xxs,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),

              // Action buttons
              Row(
                children: [
                  // Open in Editor button
                  if (node.type == GraphNodeType.file)
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.open_in_new,
                        label: 'Open in Editor',
                        onTap: () {
                          ref
                              .read(editorProvider.notifier)
                              .openFile(node.fullPath);
                        },
                      ),
                    ),
                  if (node.type == GraphNodeType.file)
                    const SizedBox(width: Spacing.sm),
                  // Explain with AI button
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.auto_awesome,
                      label: 'Explain with AI',
                      isAccent: true,
                      onTap: () {
                        ref
                            .read(codebaseMapProvider.notifier)
                            .explainNode(nodeId);
                      },
                    ),
                  ),
                ],
              ),

              // AI explanation area
              if (graphState.aiExplanation != null) ...[
                const SizedBox(height: Spacing.lg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: tokens.bgLight,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(
                      color: tokens.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 12,
                            color: tokens.accent,
                          ),
                          const SizedBox(width: Spacing.sm),
                          Text(
                            'AI Analysis',
                            style: TextStyle(
                              color: tokens.accent,
                              fontSize: FontSizes.xxs,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        graphState.aiExplanation!,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xs,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends ConsumerStatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isAccent;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isAccent = false,
  });

  @override
  ConsumerState<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends ConsumerState<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final color = widget.isAccent ? tokens.accent : tokens.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: _isHovered
                ? color.withValues(alpha: 0.1)
                : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 12, color: color),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: FontSizes.xxs,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
