import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/config/models_config.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/settings_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';

class StudioSettingsView extends ConsumerWidget {
  const StudioSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final modelOptions = <String>{
      ...settings.connectorModels.map((model) => model.id),
      for (final model in ModelsConfig.ciscoModels) model.id,
    }.toList()..sort();
    final selectedModel = modelOptions.contains(settings.ciscoModel)
        ? settings.ciscoModel
        : ModelsConfig.defaultCiscoModel;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 72,
        vertical: Spacing.xxl,
      ),
      children: [
        Text(
          'Studio settings',
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.xxl,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'Core Studio stays on the turn runtime. Legacy editor tools stay out of this surface.',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.sm,
            height: 1.4,
          ),
        ),
        const SizedBox(height: Spacing.xl),
        _SettingsSection(
          title: 'Circuit AI',
          children: [
            _SettingsRow(
              title: 'Model',
              detail: 'Used for new Studio turns.',
              trailing: DropdownButton<String>(
                value: selectedModel,
                dropdownColor: tokens.studioPanel,
                items: [
                  for (final model in modelOptions)
                    DropdownMenuItem(value: model, child: Text(model)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  ref.read(settingsProvider.notifier).setCiscoModel(value);
                },
              ),
            ),
            _SettingsRow(
              title: 'Connector health',
              detail:
                  settings.connectorHealthMessage ??
                  settings.connectorHealthStatus.name,
              trailing: StudioMiniChip(
                label: settings.connectorHealthStatus.name,
                attention: settings.connectorHealthStatus.name != 'healthy',
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        _SettingsSection(
          title: 'Review first',
          children: [
            const _SettingsRow(
              title: 'Approval scope',
              detail:
                  'Studio approval grants are request-scoped: approve one action or this turn only.',
              trailing: StudioMiniChip(label: 'Locked'),
            ),
            _SettingsRow(
              title: 'Thinking mode',
              detail: 'Request additional reasoning from supported models.',
              trailing: Switch(
                value: settings.thinkingMode,
                onChanged: (value) =>
                    ref.read(settingsProvider.notifier).setThinkingMode(value),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        const _SettingsSection(
          title: 'Runtime boundary',
          children: [
            _SettingsRow(
              title: 'File edits',
              detail:
                  'Studio applies reviewed patch transactions instead of direct editor saves.',
              trailing: StudioMiniChip(label: 'Patch only'),
            ),
            _SettingsRow(
              title: 'Commands',
              detail:
                  'Commands run through approved verification turns and command logs.',
              trailing: StudioMiniChip(label: 'Approval gated'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsSection extends ConsumerWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      decoration: BoxDecoration(
        color: tokens.studioPanel.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              title,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.sm,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Divider(color: tokens.studioDivider, height: 1),
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(color: tokens.studioDivider, height: 1),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends ConsumerWidget {
  final String title;
  final String detail;
  final Widget trailing;

  const _SettingsRow({
    required this.title,
    required this.detail,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.lg),
          trailing,
        ],
      ),
    );
  }
}
