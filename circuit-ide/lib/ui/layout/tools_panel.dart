import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
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
    final tokens = ref.watch(themeProvider);

    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Text(
          'Advanced tools',
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.md,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          'The main rail stays focused. Everything deeper still lives here.',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            height: 1.35,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        ..._groups.expand(
          (group) => [
            Padding(
              padding: const EdgeInsets.only(
                top: Spacing.md,
                bottom: Spacing.sm,
              ),
              child: Text(
                group.label.toUpperCase(),
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            ...group.tools.map(
              (tool) => Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: _ToolButton(tool: tool),
              ),
            ),
          ],
        ),
      ],
    );
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
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: tokens.outlineSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.08),
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
