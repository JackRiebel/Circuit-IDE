import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/config/models_config.dart';
import '../../agent/providers/provider_interface.dart';
import '../../core/constants/design_tokens.dart';
import '../../models/settings_model.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_provider_connection.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';
import 'studio_settings_diagnostics.dart';
import 'studio_network_policy_settings.dart';
import 'studio_motion.dart';
import 'studio_settings_recovery.dart';
import 'studio_update_settings.dart';

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
    final selectedModelInfo = [
      ...settings.connectorModels.map((model) => model.toModelInfo()),
      ...ModelsConfig.ciscoModels,
    ].where((model) => model.id == selectedModel).firstOrNull;
    final supportsReasoning = selectedModelInfo?.supportsReasoning == true;

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
              detail: _connectorHealthDetail(settings),
              trailing: const _ConnectorHealthControl(),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        const _SettingsSection(
          title: 'Project network access',
          children: [ProjectNetworkPolicyPanel()],
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
              detail: supportsReasoning
                  ? 'Request additional reasoning from the selected model.'
                  : 'The selected model does not advertise reasoning controls.',
              trailing: StudioSettingsToggle(
                value: supportsReasoning && settings.thinkingMode,
                enabled: supportsReasoning,
                semanticLabel: 'Thinking mode',
                tooltip: supportsReasoning
                    ? settings.thinkingMode
                          ? 'Turn thinking mode off'
                          : 'Turn thinking mode on'
                    : 'Thinking mode is unavailable for this model',
                onChanged: supportsReasoning
                    ? (value) => ref
                          .read(settingsProvider.notifier)
                          .setThinkingMode(value)
                    : null,
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
        const SizedBox(height: Spacing.lg),
        _SettingsSection(
          title: 'Keyboard',
          children: [
            _SettingsRow(
              title: 'Send behavior',
              detail: settings.sendOnEnter
                  ? 'Enter sends a prompt; Shift+Enter inserts a new line.'
                  : 'Shift+Enter sends a prompt; Enter inserts a new line.',
              trailing: StudioSettingsToggle(
                value: settings.sendOnEnter,
                semanticLabel: 'Enter sends prompts',
                tooltip: 'Toggle whether Enter sends prompts',
                onChanged: (value) =>
                    ref.read(settingsProvider.notifier).setSendOnEnter(value),
              ),
            ),
            const _KeyboardShortcutReference(),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        const _SettingsSection(
          title: 'Diagnostics and privacy',
          children: [
            StudioDiagnosticRetentionPanel(),
            StudioCrashReportingPanel(),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        const _SettingsSection(
          title: 'App updates',
          children: [StudioUpdateSettingsPanel()],
        ),
        const SizedBox(height: Spacing.lg),
        const _SettingsSection(
          title: 'Thread history recovery',
          children: [StudioThreadHistoryRecoveryPanel()],
        ),
        const SizedBox(height: Spacing.lg),
        const _SettingsSection(
          title: 'Portable project history',
          children: [StudioProjectTransferPanel()],
        ),
      ],
    );
  }
}

class _ConnectorHealthControl extends ConsumerStatefulWidget {
  const _ConnectorHealthControl();

  @override
  ConsumerState<_ConnectorHealthControl> createState() =>
      _ConnectorHealthControlState();
}

class _ConnectorHealthControlState
    extends ConsumerState<_ConnectorHealthControl> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final provider = ref.read(studioAgentConnectionProvider).provider;
      if (provider == null) {
        ref
            .read(settingsProvider.notifier)
            .setConnectorHealth(
              ConnectorHealth(
                status: ConnectorHealthStatus.credentialsMissing,
                message:
                    'Circuit AI is not connected. Add credentials, then retry the connection check.',
                checkedAt: DateTime.now(),
                errorCategory: ConnectorHealthErrorCategory.credentials,
                retryAdvice:
                    'Add valid Circuit credentials in Settings, then run the connection check again.',
              ),
            );
        return;
      }
      final health = await provider.checkHealth();
      ref.read(settingsProvider.notifier).setConnectorHealth(health);
      if (health.status == ConnectorHealthStatus.connected) {
        final models = await provider.refreshModels();
        ref.read(settingsProvider.notifier).setConnectorModels(models);
      }
    } catch (_) {
      ref
          .read(settingsProvider.notifier)
          .setConnectorHealth(
            ConnectorHealth(
              status: ConnectorHealthStatus.requestFailed,
              message: 'Connection check failed. Verify the network and retry.',
              checkedAt: DateTime.now(),
              errorCategory: ConnectorHealthErrorCategory.unknown,
              retryAdvice:
                  'Retry the connection check. If it repeats, export the redacted support bundle.',
            ),
          );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(
      settingsProvider.select((settings) => settings.connectorHealthStatus),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioMiniChip(
          label: status.name,
          attention: status != ConnectorHealthStatus.connected,
        ),
        const SizedBox(width: Spacing.xs),
        StudioChromeIconButton(
          tooltip: 'Check Circuit AI connection',
          onTap: () => unawaited(_check()),
          loading: _checking,
          icon: StudioIcons.refresh,
          iconSize: 16,
        ),
      ],
    );
  }
}

class _KeyboardShortcutReference extends ConsumerWidget {
  const _KeyboardShortcutReference();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final sendKey = ref.watch(
      settingsProvider.select(
        (settings) => settings.sendOnEnter ? 'Enter' : 'Shift+Enter',
      ),
    );
    final entries = [
      ('New chat', '⌘N'),
      ('Search tasks', '⌘F'),
      ('Command palette', '⌘K / ⇧⌘P'),
      ('Send prompt', sendKey),
      ('Cancel active request', 'Esc'),
      ('Plan mode', '⇧⌘O'),
      ('Files', '⌘P'),
      ('Repository diff', '⇧⌘D'),
      ('Terminal', '⌘J'),
      ('Toggle Progress', '⌥⌘→'),
      ('Archive selected task', '⇧⌘A'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 0, 11, 11),
      child: Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.xs,
        children: [
          for (final entry in entries)
            Tooltip(
              message: entry.$1,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm,
                  vertical: Spacing.xs,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.studioDivider),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(
                  '${entry.$1}  ${entry.$2}',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _connectorHealthDetail(SettingsModel settings) {
  final details = <String>[
    settings.connectorHealthMessage ?? settings.connectorHealthStatus.name,
    if (settings.connectorHealthEndpoint.isNotEmpty)
      'Endpoint: ${settings.connectorHealthEndpoint}',
    if (settings.connectorHealthProtocolVersion > 0)
      'Protocol v${settings.connectorHealthProtocolVersion}',
    if (settings.connectorHealthLatencyMs > 0)
      '${settings.connectorHealthLatencyMs} ms',
    if (settings.connectorHealthErrorCategory !=
        ConnectorHealthErrorCategory.none)
      'Category: ${settings.connectorHealthErrorCategory.name}',
    if (settings.connectorHealthRetryAdvice.isNotEmpty)
      settings.connectorHealthRetryAdvice,
  ];
  return details.join(' · ');
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
                  Icon(StudioIcons.check, color: tokens.textMuted, size: 13),
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
            Icon(
              StudioIcons.keyboardArrowDown,
              color: tokens.textMuted,
              size: 13,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact settings toggle shared by the local-only configuration panels.
class StudioSettingsToggle extends ConsumerStatefulWidget {
  /// WCAG 2.2 target-size baseline for compact desktop actions.
  static const minimumTargetSize = 24.0;

  final bool value;
  final bool enabled;

  /// The accessible setting name announced with the toggle's on/off state.
  ///
  /// Compact visual controls have no visible text of their own, so callers
  /// should provide this whenever the neighboring row label would otherwise
  /// be the only description of the setting.
  final String? semanticLabel;
  final String? tooltip;
  final ValueChanged<bool>? onChanged;
  final FocusNode? focusNode;

  const StudioSettingsToggle({
    super.key,
    required this.value,
    this.enabled = true,
    this.semanticLabel,
    this.tooltip,
    this.onChanged,
    this.focusNode,
  });

  @override
  ConsumerState<StudioSettingsToggle> createState() =>
      _StudioSettingsToggleState();
}

class _StudioSettingsToggleState extends ConsumerState<StudioSettingsToggle> {
  FocusNode? _ownedFocusNode;
  FocusNode? _listenedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _configureFocusNode();
  }

  @override
  void didUpdateWidget(covariant StudioSettingsToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _configureFocusNode();
    }
  }

  @override
  void dispose() {
    _listenedFocusNode?.removeListener(_onFocusChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _configureFocusNode() {
    _listenedFocusNode?.removeListener(_onFocusChanged);
    if (widget.focusNode == null) {
      _ownedFocusNode ??= FocusNode(
        debugLabel:
            'studio-setting-${widget.semanticLabel ?? widget.tooltip ?? 'toggle'}',
      );
    } else {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
    _listenedFocusNode = _focusNode..addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, bool enabled) {
    if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    widget.onChanged!(!widget.value);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final effectiveEnabled = widget.enabled && widget.onChanged != null;
    final resolvedTooltip =
        widget.tooltip ??
        (!effectiveEnabled
            ? 'This setting is not available'
            : widget.value
            ? 'Turn setting off'
            : 'Turn setting on');
    return Semantics(
      label: widget.semanticLabel ?? resolvedTooltip,
      toggled: widget.value,
      enabled: effectiveEnabled,
      onTap: effectiveEnabled ? () => widget.onChanged!(!widget.value) : null,
      child: ExcludeSemantics(
        child: Tooltip(
          message: resolvedTooltip,
          child: Focus(
            focusNode: _focusNode,
            canRequestFocus: effectiveEnabled,
            onKeyEvent: (_, event) => _handleKeyEvent(event, effectiveEnabled),
            child: InkWell(
              canRequestFocus: false,
              onTap: effectiveEnabled
                  ? () {
                      _focusNode.requestFocus();
                      widget.onChanged!(!widget.value);
                    }
                  : null,
              borderRadius: BorderRadius.circular(Radii.pill),
              child: AnimatedContainer(
                duration: studioMotionDuration(
                  context,
                  AnimationDurations.fast,
                ),
                curve: AnimationCurves.snappy,
                width: 34,
                height: StudioSettingsToggle.minimumTargetSize,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: !effectiveEnabled
                      ? tokens.studioControl.withValues(alpha: 0.34)
                      : widget.value
                      ? tokens.accent.withValues(alpha: 0.78)
                      : tokens.studioControl.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: _focusNode.hasFocus
                      ? Border.all(color: tokens.outlineFocus, width: 1.5)
                      : Border.all(
                          color: !effectiveEnabled
                              ? tokens.studioDivider.withValues(alpha: 0.35)
                              : widget.value
                              ? tokens.accent.withValues(alpha: 0.36)
                              : tokens.studioDivider.withValues(alpha: 0.5),
                        ),
                ),
                child: AnimatedAlign(
                  duration: studioMotionDuration(
                    context,
                    AnimationDurations.fast,
                  ),
                  curve: AnimationCurves.snappy,
                  alignment: widget.value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: !effectiveEnabled
                          ? tokens.studioDivider
                          : widget.value
                          ? tokens.bgDark
                          : tokens.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
