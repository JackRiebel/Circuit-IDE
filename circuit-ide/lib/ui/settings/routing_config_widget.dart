import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/routing_models.dart';
import '../../state/model_routing_provider.dart';
import '../../state/theme_provider.dart';
import '../common/toggle_switch.dart';

class RoutingConfigWidget extends ConsumerWidget {
  const RoutingConfigWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final config = ref.watch(modelRoutingProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Enabled toggle
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto-Route Models',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Automatically select the best model based on task complexity.',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xs,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.lg),
              ToggleSwitch(
                value: config.enabled,
                onChanged: (v) =>
                    ref.read(modelRoutingProvider.notifier).setEnabled(v),
              ),
            ],
          ),
        ),

        if (config.enabled) ...[
          Divider(color: tokens.border, height: 1),

          // Minimum tier
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Minimum Tier',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                    ),
                  ),
                ),
                _TierDropdown(
                  value: config.minTier,
                  onChanged: (tier) =>
                      ref.read(modelRoutingProvider.notifier).setMinTier(tier),
                ),
              ],
            ),
          ),
          Divider(color: tokens.border, height: 1),

          // Preference
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preference',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    _PreferenceChip(
                      label: 'Speed',
                      isSelected: config.preferSpeed,
                      onTap: () => ref
                          .read(modelRoutingProvider.notifier)
                          .setPreferSpeed(!config.preferSpeed),
                    ),
                    const SizedBox(width: Spacing.md),
                    _PreferenceChip(
                      label: 'Balanced',
                      isSelected: !config.preferSpeed && !config.preferQuality,
                      onTap: () {
                        ref
                            .read(modelRoutingProvider.notifier)
                            .setPreferSpeed(false);
                        ref
                            .read(modelRoutingProvider.notifier)
                            .setPreferQuality(false);
                      },
                    ),
                    const SizedBox(width: Spacing.md),
                    _PreferenceChip(
                      label: 'Quality',
                      isSelected: config.preferQuality,
                      onTap: () => ref
                          .read(modelRoutingProvider.notifier)
                          .setPreferQuality(!config.preferQuality),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(color: tokens.border, height: 1),

          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Routing Stats',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        '${config.routedRequests} requests routed',
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: FontSizes.xs,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.lg,
                    vertical: Spacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Text(
                    'Saved ~\$${config.costSavings.toStringAsFixed(3)}',
                    style: TextStyle(
                      color: tokens.success,
                      fontSize: FontSizes.xs,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TierDropdown extends ConsumerWidget {
  final ModelTier value;
  final ValueChanged<ModelTier> onChanged;

  const _TierDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      decoration: BoxDecoration(
        color: tokens.inputBg,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.inputBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ModelTier>(
          value: value,
          dropdownColor: tokens.bgLighter,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.xs,
          ),
          items: ModelTier.values
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(_tierLabel(t)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  String _tierLabel(ModelTier tier) => switch (tier) {
        ModelTier.fast => 'Fast (nano/haiku)',
        ModelTier.balanced => 'Balanced (mini/sonnet)',
        ModelTier.powerful => 'Powerful (full)',
      };
}

class _PreferenceChip extends ConsumerWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PreferenceChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? tokens.accent.withValues(alpha: 0.15)
                : tokens.inputBg,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: isSelected
                  ? tokens.accent.withValues(alpha: 0.5)
                  : tokens.inputBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? tokens.accent : tokens.textSecondary,
              fontSize: FontSizes.xs,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
