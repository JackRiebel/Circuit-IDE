import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../agent/config/models_config.dart';
import '../../agent/providers/provider_interface.dart';
import '../../core/constants/design_tokens.dart';
import '../../models/settings_model.dart';
import '../../models/studio_shell.dart';
import '../../models/token_usage.dart';
import '../../state/chat_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/git_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';

class StudioPromptComposer extends ConsumerStatefulWidget {
  final String hintText;
  final String submitTooltip;
  final ValueChanged<String> onSubmit;
  final bool compact;

  const StudioPromptComposer({
    super.key,
    required this.hintText,
    required this.onSubmit,
    this.submitTooltip = 'Start',
    this.compact = false,
  });

  @override
  ConsumerState<StudioPromptComposer> createState() =>
      _StudioPromptComposerState();
}

class _StudioPromptComposerState extends ConsumerState<StudioPromptComposer> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(studioShellProvider).composerText,
    );
    _controller.addListener(() {
      ref.read(studioShellProvider.notifier).setComposerText(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final studio = ref.watch(studioShellProvider);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final branch = ref.watch(gitProvider).status.branch;
    final settings = ref.watch(settingsProvider);
    final tokenUsage = ref.watch(chatProvider).tokenUsage;
    final projectLabel = rootPath == null
        ? 'Choose project'
        : p.basename(rootPath);

    return Container(
      decoration: BoxDecoration(
        color: tokens.studioComposer,
        borderRadius: BorderRadius.circular(widget.compact ? 18 : 22),
        border: Border.all(color: tokens.studioDivider),
        boxShadow: Shadows.elevated,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: widget.compact ? 92 : 96,
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.sm,
              Spacing.sm,
            ),
            child: Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: widget.compact ? 3 : 4,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.base,
                      height: 1.35,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: TextStyle(color: tokens.textMuted),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _PermissionsSelector(
                              autoApprove: settings.autoApprove,
                            ),
                            const SizedBox(width: Spacing.lg),
                            _ComposerModeSelector(value: studio.promptMode),
                            const SizedBox(width: Spacing.md),
                            _ModelSelector(selectedModel: settings.ciscoModel),
                            const SizedBox(width: Spacing.md),
                            _TokenRemainingPill(
                              modelId: settings.ciscoModel,
                              usage: tokenUsage,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Tooltip(
                      message: widget.submitTooltip,
                      child: InkWell(
                        onTap: _submit,
                        borderRadius: BorderRadius.circular(Radii.pill),
                        child: Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _controller.text.trim().isEmpty
                                ? tokens.textMuted.withValues(alpha: 0.18)
                                : tokens.textPrimary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_upward,
                            color: tokens.bgDark,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!widget.compact)
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              decoration: BoxDecoration(
                color: tokens.surfaceBase.withValues(alpha: 0.36),
                border: Border(top: BorderSide(color: tokens.studioDivider)),
              ),
              child: Row(
                children: [
                  _ProjectPickerPill(
                    icon: Icons.folder_copy_outlined,
                    label: projectLabel,
                  ),
                  const SizedBox(width: Spacing.lg),
                  _ComposerPill(
                    icon: Icons.account_tree_outlined,
                    label: branch.isEmpty ? 'main' : branch,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
    ref.read(studioShellProvider.notifier).clearComposer();
  }
}

class _ComposerModeSelector extends ConsumerWidget {
  final StudioPromptMode value;

  const _ComposerModeSelector({required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return PopupMenuButton<StudioPromptMode>(
      tooltip: 'Task mode',
      color: tokens.studioPanel,
      elevation: 12,
      position: PopupMenuPosition.under,
      shape: _softMenuShape(tokens),
      onSelected: (mode) =>
          ref.read(studioShellProvider.notifier).setPromptMode(mode),
      itemBuilder: (context) => [
        for (final mode in StudioPromptMode.values)
          PopupMenuItem(value: mode, child: Text(mode.label)),
      ],
      child: _ComposerPill(
        icon: Icons.route_outlined,
        label: value.label,
        trailing: Icons.expand_more,
      ),
    );
  }
}

class _PermissionsSelector extends ConsumerWidget {
  final bool autoApprove;

  const _PermissionsSelector({required this.autoApprove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final label = autoApprove ? 'Auto approve tools' : 'Review first';
    return PopupMenuButton<bool>(
      tooltip: 'Tool permissions',
      color: tokens.studioPanel,
      elevation: 12,
      position: PopupMenuPosition.under,
      shape: _softMenuShape(tokens),
      onSelected: (value) {
        ref.read(settingsProvider.notifier).setAutoApprove(value);
        ref.read(agentServiceProvider).setAutoApprove(value);
      },
      itemBuilder: (context) => [
        _permissionItem(
          value: false,
          selected: !autoApprove,
          icon: Icons.rate_review_outlined,
          title: 'Review first',
          detail: 'Ask before file writes and tool requests.',
          tokens: tokens,
        ),
        _permissionItem(
          value: true,
          selected: autoApprove,
          icon: Icons.flash_auto_outlined,
          title: 'Auto approve tools',
          detail: 'Allow configured agent tools without prompts.',
          tokens: tokens,
        ),
      ],
      child: _ComposerPill(
        icon: Icons.back_hand_outlined,
        label: label,
        trailing: Icons.expand_more,
      ),
    );
  }

  PopupMenuItem<bool> _permissionItem({
    required bool value,
    required bool selected,
    required IconData icon,
    required String title,
    required String detail,
    required ThemeTokens tokens,
  }) {
    return PopupMenuItem<bool>(
      value: value,
      child: SizedBox(
        width: 260,
        child: Row(
          children: [
            Icon(icon, color: tokens.textMuted, size: 16),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
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
            if (selected)
              Icon(Icons.check, color: tokens.textPrimary, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ComposerPill extends ConsumerWidget {
  final IconData? icon;
  final String label;
  final IconData? trailing;

  const _ComposerPill({this.icon, required this.label, this.trailing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: tokens.textMuted, size: 14),
          const SizedBox(width: Spacing.sm),
        ],
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
        ),
        if (trailing != null) ...[
          const SizedBox(width: Spacing.xs),
          Icon(trailing, color: tokens.textMuted, size: 14),
        ],
      ],
    );
  }
}

class _ModelSelector extends ConsumerWidget {
  final String selectedModel;

  const _ModelSelector({required this.selectedModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final models = _availableModels(settings);
    final selectedInfo = models.firstWhere(
      (model) => model.id == selectedModel,
      orElse: () => ModelInfo(
        id: selectedModel,
        displayName: selectedModel,
        contextWindow: 120000,
      ),
    );

    return PopupMenuButton<String>(
      tooltip: 'Choose model',
      color: tokens.studioPanel,
      elevation: 12,
      position: PopupMenuPosition.under,
      shape: _softMenuShape(tokens),
      onSelected: (modelId) =>
          ref.read(settingsProvider.notifier).setCiscoModel(modelId),
      itemBuilder: (context) => [
        for (final model in models)
          PopupMenuItem<String>(
            value: model.id,
            child: SizedBox(
              width: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${TokenUsage.formatCount(model.contextWindow)} context'
                    '${model.supportsTools ? ' · tools' : ' · chat only'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      child: _ComposerPill(
        icon: Icons.memory_outlined,
        label: selectedInfo.id,
        trailing: Icons.expand_more,
      ),
    );
  }
}

class _TokenRemainingPill extends ConsumerWidget {
  final String modelId;
  final TokenUsage usage;

  const _TokenRemainingPill({required this.modelId, required this.usage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inputLimit = ModelsConfig.periodInputTokenLimitForModel(modelId);
    final outputLimit = ModelsConfig.periodOutputTokenLimitForModel(modelId);
    final inputLeft = (inputLimit - usage.promptTokens)
        .clamp(0, inputLimit)
        .toInt();
    final outputLeft = (outputLimit - usage.completionTokens)
        .clamp(0, outputLimit)
        .toInt();
    final label =
        'In ${TokenUsage.formatCount(inputLeft)} left / '
        'Out ${TokenUsage.formatCount(outputLeft)} left';

    return Tooltip(
      message:
          'Free-tier period for $modelId: '
          'used ${usage.formattedInputOutput} of '
          'In ${TokenUsage.formatCount(inputLimit)} / '
          'Out ${TokenUsage.formatCount(outputLimit)}.',
      child: _ComposerPill(icon: Icons.data_usage_outlined, label: label),
    );
  }
}

class _ProjectPickerPill extends ConsumerWidget {
  final IconData icon;
  final String label;

  const _ProjectPickerPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => unawaited(_chooseProjectRoot(ref)),
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _ComposerPill(
          icon: icon,
          label: label,
          trailing: Icons.expand_more,
        ),
      ),
    );
  }
}

List<ModelInfo> _availableModels(SettingsModel settings) {
  if (settings.connectorModels.isNotEmpty) {
    return settings.connectorModels
        .map((model) => model.toModelInfo())
        .toList();
  }
  return ModelsConfig.ciscoModels;
}

Future<void> _chooseProjectRoot(WidgetRef ref) async {
  final result = await FilePicker.platform.getDirectoryPath();
  if (result == null) return;
  final openResult = await ref
      .read(fileTreeProvider.notifier)
      .openDirectory(result);
  if (!openResult.success) return;
  ref.read(settingsProvider.notifier).addRecentProject(result);
  ref.read(studioShellProvider.notifier).openProject(result);
}

ShapeBorder _softMenuShape(ThemeTokens tokens) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: BorderSide(color: tokens.studioDivider),
  );
}
