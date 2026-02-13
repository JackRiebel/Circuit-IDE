import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/connection_provider.dart';
import '../../state/editor_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/theme_provider.dart';
import '../common/toggle_switch.dart';
import 'credential_card.dart';
import 'theme_picker.dart';

class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        // Theme
        const _SectionHeader(title: 'Theme'),
        const _SettingsCard(
          child: ThemePicker(),
        ),
        const SizedBox(height: Spacing.xxl),

        // Credentials
        const _SectionHeader(title: 'AI Credentials'),
        const CredentialCard(),
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

        // Agent Settings
        const _SectionHeader(title: 'Agent'),
        _SettingsCard(
          child: Column(
            children: [
              _SettingToggleWithDescription(
                label: 'Write Permissions',
                description: 'Allow agent to edit files, run commands, and '
                    'commit without asking for confirmation each time.',
                value: settings.autoApprove,
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).setAutoApprove(v);
                  ref.read(agentServiceProvider).setAutoApprove(v);
                },
              ),
              Divider(color: tokens.border, height: 1),
              _SettingToggle(
                label: 'Stream responses',
                value: settings.streamResponses,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ],
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
          ToggleSwitch(
            value: value,
            onChanged: onChanged,
          ),
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
          ToggleSwitch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _FontSizeStepper extends ConsumerWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _FontSizeStepper({
    required this.value,
    required this.onChanged,
  });

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
            color: _isHovered
                ? tokens.accent
                : tokens.textMuted,
          ),
        ),
      ),
    );
  }
}
