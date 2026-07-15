import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/config/models_config.dart';
import '../../agent/providers/provider_interface.dart';
import '../../core/constants/design_tokens.dart';
import '../../models/agent_config_model.dart';
import '../../models/custom_agent_routing.dart';
import '../../models/token_usage.dart';
import '../../models/turn_intent.dart';
import '../../state/agent_manager_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';
import 'studio_composer_control_helpers.dart';
import 'studio_motion.dart';

class StudioComposerPill extends ConsumerWidget {
  final IconData? icon;
  final String label;
  final IconData? trailing;
  final bool active;

  const StudioComposerPill({
    super.key,
    this.icon,
    required this.label,
    this.trailing,
    this.active = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return AnimatedContainer(
      duration: studioMotionDuration(context, AnimationDurations.fast),
      curve: AnimationCurves.smooth,
      constraints: const BoxConstraints(minHeight: 20),
      padding: EdgeInsets.symmetric(
        horizontal: active ? 7 : 0,
        vertical: active ? 2 : 0,
      ),
      decoration: BoxDecoration(
        color: active
            ? tokens.studioControl.withValues(alpha: 0.58)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: active
            ? Border.all(color: tokens.studioDivider.withValues(alpha: 0.42))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: active ? tokens.textSecondary : tokens.textMuted,
              size: 12,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? tokens.textSecondary : tokens.textMuted,
              fontSize: FontSizes.xs,
              height: 1.0,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 3),
            Icon(trailing, color: tokens.textMuted, size: 12),
          ],
        ],
      ),
    );
  }
}

class StudioAddContextButton extends ConsumerWidget {
  final FocusNode? focusNode;

  const StudioAddContextButton({super.key, this.focusNode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StudioChromeIconButton(
      focusNode: focusNode,
      tooltip: 'Add context',
      icon: StudioIcons.add,
      width: 24,
      height: 24,
      iconSize: 14,
      onTap: () {
        ref.read(studioShellProvider.notifier).showRightProgressPanel();
        ref.read(studioRightDrawerProvider.notifier).openContext();
      },
    );
  }
}

class StudioCustomAgentSelector extends ConsumerWidget {
  static const _generalAgentId = '__general__';
  static const _autoAgentId = '__auto__';

  final String? selectedAgentId;

  const StudioCustomAgentSelector({super.key, required this.selectedAgentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final studio = ref.watch(studioShellProvider);
    final configs = ref.watch(
      agentManagerProvider.select(
        (state) => state.configs.where((config) => config.enabled).toList(),
      ),
    );
    final selected = configs
        .where((config) => config.id == selectedAgentId)
        .firstOrNull;
    final selection = const CustomAgentRouter().route(
      prompt: studio.composerText,
      intent: IntentClassifier.classify(
        studio.composerText,
        promptMode: studio.promptMode,
        planModeEnabled: studio.planModeEnabled,
      ),
      configs: configs,
      explicitAgentId: studio.customAgentId,
      auto: studio.autoCustomAgent,
    );

    return PopupMenuButton<String>(
      tooltip: studio.autoCustomAgent
          ? '${selection.confidenceLabel} · ${selection.rationale}'
          : 'Choose custom agent',
      color: tokens.studioPanel,
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: studioComposerSoftMenuShape(tokens),
      onSelected: (agentId) {
        final notifier = ref.read(studioShellProvider.notifier);
        if (agentId == _autoAgentId) {
          notifier.setAutoCustomAgent(true);
        } else {
          notifier.setCustomAgent(agentId == _generalAgentId ? null : agentId);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: _autoAgentId,
          child: SizedBox(
            width: 238,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Auto'),
                Text(
                  studio.autoCustomAgent
                      ? '${selection.label} · ${selection.confidenceLabel}'
                      : 'Match an enabled agent when confidence is high',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuItem<String>(
          value: _generalAgentId,
          child: Text('General Studio agent'),
        ),
        if (configs.isNotEmpty) const PopupMenuDivider(),
        for (final config in configs)
          PopupMenuItem<String>(
            value: config.id,
            child: SizedBox(
              width: 238,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.xs,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${config.model} · ${_customAgentDetailsLabel(config)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xxs,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      child: StudioComposerPill(
        icon: StudioIcons.smartToyOutlined,
        label: studio.autoCustomAgent
            ? 'Auto: ${selection.label}'
            : selected?.name ?? 'General',
        trailing: StudioIcons.expandMore,
      ),
    );
  }
}

class StudioCustomAgentRoutingPreview extends ConsumerWidget {
  const StudioCustomAgentRoutingPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioShellProvider);
    if (!studio.autoCustomAgent || studio.composerText.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final configs = ref.watch(
      agentManagerProvider.select(
        (state) => state.configs.where((config) => config.enabled).toList(),
      ),
    );
    final intent = IntentClassifier.classify(
      studio.composerText,
      promptMode: studio.promptMode,
      planModeEnabled: studio.planModeEnabled,
    );
    final selection = const CustomAgentRouter().route(
      prompt: studio.composerText,
      intent: intent,
      configs: configs,
      auto: true,
    );
    final tokens = ref.watch(themeProvider);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: Spacing.xl),
        child: Row(
          children: [
            Icon(
              StudioIcons.autoAwesomeOutlined,
              size: 12,
              color: tokens.accent,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                'Auto: ${selection.label} · ${selection.confidenceLabel} · ${selection.rationale}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _customAgentDetailsLabel(AgentConfigModel config) {
  return config.allowedTools.isEmpty
      ? 'no tools'
      : '${config.allowedTools.length} declared tools';
}

class StudioModelSelector extends ConsumerWidget {
  final String selectedModel;

  const StudioModelSelector({super.key, required this.selectedModel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final models = studioComposerAvailableModels(settings);
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
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: studioComposerSoftMenuShape(tokens),
      onSelected: (modelId) =>
          ref.read(settingsProvider.notifier).setCiscoModel(modelId),
      itemBuilder: (context) => [
        for (final model in models)
          PopupMenuItem<String>(
            height: 44,
            value: model.id,
            child: SizedBox(
              width: 238,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.xs,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${TokenUsage.formatCount(model.contextWindow)} context'
                    '${model.supportsTools ? ' · tools' : ' · chat only'}'
                    '${model.supportsImageInput ? ' · vision' : ''}'
                    '${model.supportsJsonSchema ? ' · structured' : ''}'
                    '${model.supportsReasoning ? ' · reasoning' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xxs,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      child: StudioComposerPill(
        icon: StudioIcons.memoryOutlined,
        label: selectedInfo.id,
        trailing: StudioIcons.expandMore,
      ),
    );
  }
}

class StudioTokenRemainingPill extends ConsumerWidget {
  final String modelId;
  final TokenUsage threadUsage;
  final TokenUsage requestUsage;

  const StudioTokenRemainingPill({
    super.key,
    required this.modelId,
    required this.threadUsage,
    required this.requestUsage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inputLimit = ModelsConfig.periodInputTokenLimitForModel(modelId);
    final outputLimit = ModelsConfig.periodOutputTokenLimitForModel(modelId);
    final inputLeft = (inputLimit - threadUsage.promptTokens)
        .clamp(0, inputLimit)
        .toInt();
    final outputLeft = (outputLimit - threadUsage.completionTokens)
        .clamp(0, outputLimit)
        .toInt();
    final label =
        'In ${TokenUsage.formatCount(inputLeft)} left / '
        'Out ${TokenUsage.formatCount(outputLeft)} left';

    return Tooltip(
      message:
          'Free-tier period for $modelId: '
          'thread total ${threadUsage.formattedDetailedBreakdown}; '
          'latest request ${requestUsage.formattedDetailedBreakdown}. '
          'Free-tier allowance uses the thread total of '
          'In ${TokenUsage.formatCount(inputLimit)} / '
          'Out ${TokenUsage.formatCount(outputLimit)}.',
      child: StudioComposerPill(
        icon: StudioIcons.dataUsageOutlined,
        label: label,
      ),
    );
  }
}

class StudioProjectPickerPill extends ConsumerWidget {
  final IconData icon;
  final String label;

  const StudioProjectPickerPill({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StudioFocusableActionSurface(
      semanticLabel: 'Choose project folder',
      onTap: () => unawaited(chooseStudioComposerProjectRoot(ref)),
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: StudioComposerPill(
          icon: icon,
          label: label,
          trailing: StudioIcons.expandMore,
        ),
      ),
    );
  }
}
