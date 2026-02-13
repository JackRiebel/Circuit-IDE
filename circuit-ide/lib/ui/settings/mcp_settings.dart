import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../common/toggle_switch.dart';

class MCPSettings extends ConsumerWidget {
  const MCPSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.bgLight,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.border.withValues(alpha: 0.5)),
        boxShadow: Shadows.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.extension_outlined,
                size: 14,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'MCP Servers',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Model Context Protocol servers extend the agent\'s capabilities with additional tools.',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              height: 1.4,
            ),
          ),
          const SizedBox(height: Spacing.xl),
          // GitHub MCP Server
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: tokens.bgDark,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: tokens.border.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    color: tokens.textMuted.withValues(alpha: 0.08),
                  ),
                  child: Icon(
                    Icons.source_outlined,
                    size: 15,
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GitHub MCP Server',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: FontSizes.sm,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Extended GitHub integration',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xxs,
                        ),
                      ),
                    ],
                  ),
                ),
                ToggleSwitch(
                  value: false,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
