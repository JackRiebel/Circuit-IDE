import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../common/circuit_primitives.dart';
import 'activity_bar.dart';

class ToolsPanel extends ConsumerWidget {
  const ToolsPanel({super.key});

  static const _groups = [
    _ToolGroup('Project', [
      _ToolLink(
        ActivityBarItem.codebaseMap,
        Icons.hub_outlined,
        'Codebase Map',
        'Project graph and architecture map',
      ),
      _ToolLink(
        ActivityBarItem.notebook,
        Icons.science_outlined,
        'Notebooks',
        'Scratch pads and executable notes',
      ),
    ]),
    _ToolGroup('AI', [
      _ToolLink(
        ActivityBarItem.memories,
        Icons.auto_awesome_outlined,
        'AI Memories',
        'Reusable project knowledge',
      ),
      _ToolLink(
        ActivityBarItem.rules,
        Icons.rule_outlined,
        'Rules',
        'Agent behavior and project guidance',
      ),
      _ToolLink(
        ActivityBarItem.agents,
        Icons.smart_toy_outlined,
        'Agents',
        'Reusable background agents',
      ),
    ]),
    _ToolGroup('Verification', [
      _ToolLink(
        ActivityBarItem.checkpoints,
        Icons.history_outlined,
        'Checkpoints',
        'Review and restore AI edits',
      ),
      _ToolLink(
        ActivityBarItem.security,
        Icons.shield_outlined,
        'Security',
        'Scan code for security findings',
      ),
      _ToolLink(
        ActivityBarItem.vericoding,
        Icons.verified_outlined,
        'Vericoding',
        'Automated verification checks',
      ),
    ]),
    _ToolGroup('Integrations', [
      _ToolLink(
        ActivityBarItem.mcp,
        Icons.extension_outlined,
        'MCP Hub',
        'External tools and context servers',
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        for (final group in _groups)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: CircuitDisclosureRow(
              icon: _groupIcon(group.label),
              title: group.label,
              subtitle: '${group.tools.length} tools',
              initiallyExpanded: group.label == 'Project',
              children: group.tools
                  .map(
                    (tool) => Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: _ToolButton(tool: tool),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  static IconData _groupIcon(String label) {
    return switch (label) {
      'Project' => Icons.folder_open_outlined,
      'AI' => Icons.auto_awesome_outlined,
      'Verification' => Icons.verified_outlined,
      'Integrations' => Icons.extension_outlined,
      _ => Icons.widgets_outlined,
    };
  }
}

class _ToolButton extends ConsumerWidget {
  final _ToolLink tool;

  const _ToolButton({required this.tool});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return InkWell(
      onTap: () => ref.read(activeActivityItemProvider.notifier).set(tool.item),
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: tokens.surfaceInset,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: tokens.outlineSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: tokens.surfacePressed,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(tool.icon, color: tokens.accent, size: 16),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.title,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tool.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: tokens.textMuted, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ToolLink {
  final ActivityBarItem item;
  final IconData icon;
  final String title;
  final String description;

  const _ToolLink(this.item, this.icon, this.title, this.description);
}

class _ToolGroup {
  final String label;
  final List<_ToolLink> tools;

  const _ToolGroup(this.label, this.tools);
}
