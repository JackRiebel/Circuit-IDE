import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/config/models_config.dart';
import '../../agent/providers/provider_interface.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/connection_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/vericoding_provider.dart';
import '../common/toggle_switch.dart';
import 'credential_card.dart';
import 'routing_config_widget.dart';
import 'theme_picker.dart';

class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final vstate = ref.watch(vericodingProvider);
    final connectorModels = settings.connectorModels
        .map((model) => model.toModelInfo())
        .toList(growable: false);
    final availableModels = connectorModels.isEmpty
        ? ModelsConfig.ciscoModels
        : connectorModels;

    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        // Theme
        const _SectionHeader(title: 'Theme'),
        const _SettingsCard(child: ThemePicker()),
        const SizedBox(height: Spacing.xxl),

        // Credentials
        const _SectionHeader(title: 'AI Credentials'),
        const CredentialCard(),
        const SizedBox(height: Spacing.xxl),

        // Model Selection
        const _SectionHeader(title: 'Circuit AI'),
        _SettingsCard(
          child: Column(
            children: [
              _ModelSelector(
                label: 'Model',
                value: settings.ciscoModel,
                models: availableModels,
                onChanged: (model) {
                  ref.read(settingsProvider.notifier).setCiscoModel(model);
                  ref.read(agentServiceProvider).setModel(model);
                },
              ),
              Divider(color: tokens.border, height: 1),
              _ConnectorHealthRow(
                status: settings.connectorHealthStatus,
                message: settings.connectorHealthMessage,
                refreshedAt: settings.connectorModelsRefreshedAt,
                onRefresh: () async {
                  final service = ref.read(agentServiceProvider);
                  final health = await service.checkProviderHealth();
                  ref
                      .read(settingsProvider.notifier)
                      .setConnectorHealth(health);
                  final models = await service.refreshConnectorModels();
                  ref
                      .read(settingsProvider.notifier)
                      .setConnectorModels(models);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.xxl),

        // Editor Settings
        const _SectionHeader(title: 'Editor'),
        _SettingsCard(
          child: Column(
            children: [
              _SettingRow(
                label: 'Font Size',
                child: _FontSizeStepper(
                  value: settings.editorFontSize,
                  onChanged: (size) {
                    ref.read(settingsProvider.notifier).setEditorFontSize(size);
                    ref.read(editorProvider.notifier).setFontSize(size);
                  },
                ),
              ),
              Divider(color: tokens.border, height: 1),
              _SettingToggle(
                label: 'Word Wrap',
                value: settings.editorWordWrap,
                onChanged: (_) {
                  ref.read(settingsProvider.notifier).toggleWordWrap();
                  ref.read(editorProvider.notifier).toggleWordWrap();
                },
              ),
              Divider(color: tokens.border, height: 1),
              _SettingToggle(
                label: 'Minimap',
                value: settings.editorMinimap,
                onChanged: (_) {
                  ref.read(settingsProvider.notifier).toggleMinimap();
                  ref.read(editorProvider.notifier).toggleMinimap();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.xxl),

        // Model Routing
        const _SectionHeader(title: 'Model Routing'),
        const _SettingsCard(child: RoutingConfigWidget()),
        const SizedBox(height: Spacing.xxl),

        // Vericoding
        const _SectionHeader(title: 'Vericoding'),
        _SettingsCard(
          child: Column(
            children: [
              _SettingToggleWithDescription(
                label: 'Enabled',
                description:
                    'Automatically verify code after AI edits by running '
                    'configurable checks (dart analyze, tests, etc).',
                value: vstate.config.enabled,
                onChanged: (v) {
                  ref
                      .read(vericodingProvider.notifier)
                      .updateConfig(vstate.config.copyWith(enabled: v));
                },
              ),
              Divider(color: tokens.border, height: 1),
              _SettingToggle(
                label: 'Auto-run after AI edits',
                value: vstate.config.autoRunAfterEdit,
                onChanged: (_) {
                  ref
                      .read(vericodingProvider.notifier)
                      .updateConfig(
                        vstate.config.copyWith(
                          autoRunAfterEdit: !vstate.config.autoRunAfterEdit,
                        ),
                      );
                },
              ),
              Divider(color: tokens.border, height: 1),
              _SettingRow(
                label: 'Max fix attempts',
                child: _FontSizeStepper(
                  value: vstate.config.maxRetries.toDouble(),
                  onChanged: (v) {
                    ref
                        .read(vericodingProvider.notifier)
                        .updateConfig(
                          vstate.config.copyWith(
                            maxRetries: v.toInt().clamp(1, 10),
                          ),
                        );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.xxl),

        // Agent Settings
        const _SectionHeader(title: 'Agent'),
        _SettingsCard(
          child: Column(
            children: [
              _SettingToggleWithDescription(
                label: 'Write Permissions',
                description:
                    'Allow agent to edit files, run commands, and '
                    'commit without asking for confirmation each time.',
                value: settings.autoApprove,
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).setAutoApprove(v);
                  ref.read(agentServiceProvider).setAutoApprove(v);
                },
              ),
              Divider(color: tokens.border, height: 1),
              _SettingToggleWithDescription(
                label: 'Thinking Mode',
                description:
                    'Enable extended thinking for more thorough AI reasoning. '
                    'May increase response time.',
                value: settings.thinkingMode,
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).setThinkingMode(v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectorHealthRow extends ConsumerStatefulWidget {
  final ConnectorHealthStatus status;
  final String? message;
  final DateTime? refreshedAt;
  final Future<void> Function() onRefresh;

  const _ConnectorHealthRow({
    required this.status,
    required this.message,
    required this.refreshedAt,
    required this.onRefresh,
  });

  @override
  ConsumerState<_ConnectorHealthRow> createState() =>
      _ConnectorHealthRowState();
}

class _ConnectorHealthRowState extends ConsumerState<_ConnectorHealthRow> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final color = switch (widget.status) {
      ConnectorHealthStatus.connected => tokens.success,
      ConnectorHealthStatus.degraded => tokens.warning,
      ConnectorHealthStatus.connecting => tokens.warning,
      ConnectorHealthStatus.unknown => tokens.textMuted,
      _ => tokens.error,
    };
    final label = switch (widget.status) {
      ConnectorHealthStatus.connected => 'Connected',
      ConnectorHealthStatus.degraded => 'Degraded',
      ConnectorHealthStatus.connecting => 'Checking',
      ConnectorHealthStatus.credentialsMissing => 'Credentials missing',
      ConnectorHealthStatus.tokenFailed => 'Token failed',
      ConnectorHealthStatus.modelUnavailable => 'Model unavailable',
      ConnectorHealthStatus.requestFailed => 'Request failed',
      ConnectorHealthStatus.unknown => 'Not checked',
    };
    final refreshed = widget.refreshedAt == null
        ? null
        : 'Models refreshed ${widget.refreshedAt!.toLocal()}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connector $label',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                  ),
                ),
                if (widget.message != null || refreshed != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.message ?? refreshed!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xs,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: tokens.textMuted,
                    ),
                  )
                : const Icon(Icons.refresh, size: 14),
            label: const Text('Refresh Models'),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends ConsumerWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.bgLight,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.border),
        boxShadow: Shadows.subtle,
      ),
      child: child,
    );
  }
}

class _SectionHeader extends ConsumerWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: FontSizes.xs,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingRow extends ConsumerWidget {
  final String label;
  final Widget child;

  const _SettingRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SettingToggle extends ConsumerWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
              ),
            ),
          ),
          ToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SettingToggleWithDescription extends ConsumerWidget {
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingToggleWithDescription({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  description,
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
          ToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ModelSelector extends ConsumerWidget {
  final String label;
  final String value;
  final List<ModelInfo> models;
  final ValueChanged<String> onChanged;

  const _ModelSelector({
    required this.label,
    required this.value,
    required this.models,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: tokens.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: models.any((m) => m.id == value)
                    ? value
                    : models.first.id,
                dropdownColor: tokens.bgLight,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.xs,
                  fontFamily: 'JetBrains Mono',
                ),
                icon: Icon(
                  Icons.expand_more,
                  size: 16,
                  color: tokens.textMuted,
                ),
                isDense: true,
                items: models.map((model) {
                  return DropdownMenuItem<String>(
                    value: model.id,
                    child: Text(
                      model.displayName,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.xs,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FontSizeStepper extends ConsumerWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _FontSizeStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove,
            onTap: () => onChanged((value - 1).clamp(8, 32)),
          ),
          Container(
            width: 36,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${value.toInt()}',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add,
            onTap: () => onChanged((value + 1).clamp(8, 32)),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends ConsumerStatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  ConsumerState<_StepperButton> createState() => _StepperButtonState();
}

class _StepperButtonState extends ConsumerState<_StepperButton> {
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _isHovered
                ? tokens.accent.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Icon(
            widget.icon,
            size: 14,
            color: _isHovered ? tokens.accent : tokens.textMuted,
          ),
        ),
      ),
    );
  }
}
