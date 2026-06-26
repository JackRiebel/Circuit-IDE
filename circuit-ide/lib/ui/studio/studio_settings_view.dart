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
            fontSize: FontSizes.lg,
            fontWeight: FontWeight.w600,
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
              trailing: _SettingsModelSelector(
                selectedModel: selectedModel,
                modelOptions: modelOptions,
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
              trailing: _SettingsToggle(
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
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
            child: Text(
              title,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.sm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Divider(
            color: tokens.studioDivider.withValues(alpha: 0.62),
            height: 1,
          ),
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.62),
                height: 1,
              ),
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
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
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
                    fontWeight: FontWeight.w600,
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

class _SettingsModelSelector extends ConsumerWidget {
  final String selectedModel;
  final List<String> modelOptions;

  const _SettingsModelSelector({
    required this.selectedModel,
    required this.modelOptions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return PopupMenuButton<String>(
      tooltip: 'Choose model',
      color: tokens.studioPanel,
      elevation: 4,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.52)),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      onSelected: (value) =>
          ref.read(settingsProvider.notifier).setCiscoModel(value),
      itemBuilder: (context) => [
        for (final model in modelOptions)
          PopupMenuItem<String>(
            value: model,
            height: 30,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    model,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: model == selectedModel
                          ? tokens.textSecondary
                          : tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.15,
                      fontWeight: model == selectedModel
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (model == selectedModel)
                  Icon(Icons.check, color: tokens.textMuted, size: 13),
              ],
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 188),
        height: 28,
        padding: const EdgeInsets.only(left: 9, right: 6),
        decoration: BoxDecoration(
          color: tokens.studioControl.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selectedModel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.keyboard_arrow_down, color: tokens.textMuted, size: 13),
          ],
        ),
      ),
    );
  }
}

class _SettingsToggle extends ConsumerWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Tooltip(
      message: value ? 'Turn thinking mode off' : 'Turn thinking mode on',
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(Radii.pill),
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          curve: AnimationCurves.snappy,
          width: 34,
          height: 20,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value
                ? tokens.accent.withValues(alpha: 0.78)
                : tokens.studioControl.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: value
                  ? tokens.accent.withValues(alpha: 0.36)
                  : tokens.studioDivider.withValues(alpha: 0.5),
            ),
          ),
          child: AnimatedAlign(
            duration: AnimationDurations.fast,
            curve: AnimationCurves.snappy,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: value ? tokens.bgDark : tokens.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
