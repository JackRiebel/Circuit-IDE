import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/codebase_graph.dart';
import '../../state/codebase_map_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/theme_provider.dart';

/// Node colors by file extension.
const extensionColors = <String, Color>{
  '.dart': Color(0xFF56B6C2),
  '.py': Color(0xFF4EC9B0),
  '.js': Color(0xFFDCDCAA),
  '.jsx': Color(0xFFDCDCAA),
  '.ts': Color(0xFF569CD6),
  '.tsx': Color(0xFF569CD6),
  '.html': Color(0xFFE06C75),
  '.css': Color(0xFFC678DD),
  '.json': Color(0xFFD19A66),
  '.yaml': Color(0xFFA6E22E),
  '.yml': Color(0xFFA6E22E),
  '.md': Color(0xFF888888),
  '.go': Color(0xFF00ADD8),
  '.rs': Color(0xFFDEA584),
  '.java': Color(0xFFF89820),
  '.kt': Color(0xFFA97BFF),
};

Color colorForExtension(String ext) {
  return extensionColors[ext.toLowerCase()] ?? const Color(0xFF808080);
}

class CodebaseMapPanel extends ConsumerStatefulWidget {
  const CodebaseMapPanel({super.key});

  @override
  ConsumerState<CodebaseMapPanel> createState() => _CodebaseMapPanelState();
}

class _CodebaseMapPanelState extends ConsumerState<CodebaseMapPanel> {
  final _filterController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final graphState = ref.watch(codebaseMapProvider);

    return Column(
      children: [
        // Header actions
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Build Map button
              SizedBox(
                width: double.infinity,
                height: 30,
                child: ElevatedButton.icon(
                  onPressed: graphState.isLoading
                      ? null
                      : () =>
                            ref.read(codebaseMapProvider.notifier).buildGraph(),
                  icon: graphState.isLoading
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: tokens.accent,
                          ),
                        )
                      : const Icon(Icons.account_tree_outlined, size: 14),
                  label: Text(
                    graphState.isLoading ? 'Building...' : 'Build Map',
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),

              // Filter text field
              TextField(
                controller: _filterController,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                ),
                decoration: InputDecoration(
                  hintText: 'Filter nodes...',
                  prefixIcon: Icon(
                    Icons.filter_list,
                    size: 15,
                    color: tokens.textMuted,
                  ),
                ),
                onChanged: (value) {
                  setState(() => _filter = value.toLowerCase());
                },
              ),
            ],
          ),
        ),
        Container(height: 1, color: tokens.border.withValues(alpha: 0.3)),

        // View mode selector
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Text(
                'Layout',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              _ViewModeChip(
                label: 'Force',
                isActive: graphState.viewMode == GraphViewMode.force,
                onTap: () => ref
                    .read(codebaseMapProvider.notifier)
                    .setViewMode(GraphViewMode.force),
              ),
              const SizedBox(width: 4),
              _ViewModeChip(
                label: 'Tree',
                isActive: graphState.viewMode == GraphViewMode.hierarchical,
                onTap: () => ref
                    .read(codebaseMapProvider.notifier)
                    .setViewMode(GraphViewMode.hierarchical),
              ),
              const SizedBox(width: 4),
              _ViewModeChip(
                label: 'Circle',
                isActive: graphState.viewMode == GraphViewMode.circular,
                onTap: () => ref
                    .read(codebaseMapProvider.notifier)
                    .setViewMode(GraphViewMode.circular),
              ),
            ],
          ),
        ),
        Container(height: 1, color: tokens.border.withValues(alpha: 0.3)),

        // Stats
        if (graphState.nodes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  '${graphState.nodes.length} nodes',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Text(
                  '${graphState.edges.length} edges',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                  ),
                ),
                if (graphState.isLayoutRunning) ...[
                  const Spacer(),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: tokens.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),

        // Legend
        if (graphState.nodes.isNotEmpty) ...[
          Container(height: 1, color: tokens.border.withValues(alpha: 0.3)),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LEGEND',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.md,
                  runSpacing: Spacing.xs,
                  children: _buildLegendItems(graphState, tokens),
                ),
              ],
            ),
          ),
        ],

        // Open Map button
        if (graphState.nodes.isNotEmpty) ...[
          Container(height: 1, color: tokens.border.withValues(alpha: 0.3)),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: SizedBox(
              width: double.infinity,
              height: 30,
              child: ElevatedButton.icon(
                onPressed: () {
                  ref.read(editorProvider.notifier).openCodebaseMapTab();
                },
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Open Map'),
              ),
            ),
          ),
        ],

        // Node list (filtered)
        Expanded(child: _buildNodeList(graphState, tokens)),

        // Error display
        if (graphState.error != null)
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Text(
              graphState.error!,
              style: TextStyle(color: tokens.error, fontSize: FontSizes.xs),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  List<Widget> _buildLegendItems(
    CodebaseGraphState graphState,
    dynamic tokens,
  ) {
    // Collect unique extensions from actual nodes
    final exts = <String>{};
    for (final node in graphState.nodes) {
      if (node.extension.isNotEmpty) exts.add(node.extension);
    }

    return exts.map((ext) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colorForExtension(ext),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            ext,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xxs,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ],
      );
    }).toList();
  }

  Widget _buildNodeList(CodebaseGraphState graphState, dynamic tokens) {
    if (graphState.nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 32,
              color: tokens.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Build a map to visualize\nyour codebase',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
            ),
          ],
        ),
      );
    }

    // Filter to only project files (not external)
    var filteredNodes = graphState.nodes
        .where((n) => n.type == GraphNodeType.file)
        .toList();

    if (_filter.isNotEmpty) {
      filteredNodes = filteredNodes
          .where(
            (n) =>
                n.label.toLowerCase().contains(_filter) ||
                n.id.toLowerCase().contains(_filter),
          )
          .toList();
    }

    return ListView.builder(
      itemCount: filteredNodes.length,
      itemBuilder: (context, index) {
        final node = filteredNodes[index];
        final isSelected = node.id == graphState.selectedNodeId;

        return _NodeListItem(
          node: node,
          isSelected: isSelected,
          onTap: () {
            ref.read(codebaseMapProvider.notifier).selectNode(node.id);
          },
          onDoubleTap: () {
            ref.read(editorProvider.notifier).openFile(node.fullPath);
          },
        );
      },
    );
  }
}

class _ViewModeChip extends ConsumerStatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ViewModeChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  ConsumerState<_ViewModeChip> createState() => _ViewModeChipState();
}

class _ViewModeChipState extends ConsumerState<_ViewModeChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: widget.isActive
                ? tokens.accent.withValues(alpha: 0.15)
                : _isHovered
                ? tokens.accent.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.xs),
            border: Border.all(
              color: widget.isActive
                  ? tokens.accent.withValues(alpha: 0.5)
                  : tokens.border.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isActive ? tokens.accent : tokens.textSecondary,
              fontSize: FontSizes.xxs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeListItem extends ConsumerStatefulWidget {
  final GraphNode node;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _NodeListItem({
    required this.node,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  ConsumerState<_NodeListItem> createState() => _NodeListItemState();
}

class _NodeListItemState extends ConsumerState<_NodeListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: AnimationDurations.instant,
          color: widget.isSelected
              ? tokens.accent.withValues(alpha: 0.1)
              : _isHovered
              ? tokens.accent.withValues(alpha: 0.05)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: 3,
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colorForExtension(widget.node.extension),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.node.label,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        letterSpacing: 0,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.node.directory != null &&
                        widget.node.directory!.isNotEmpty)
                      Text(
                        widget.node.directory!,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xxs,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
