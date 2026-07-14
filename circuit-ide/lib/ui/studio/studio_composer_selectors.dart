import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/specialist_agent.dart';
import '../../models/studio_shell.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';
import 'studio_composer_control_helpers.dart';
import 'studio_composer_utility_controls.dart';

/// Selector controls for the prompt-composer task configuration.
///
/// The main composer owns text editing and submission. These controls only
/// read or update persisted Studio configuration, which keeps both boundaries
/// independently testable and avoids a growing composer state class.
class StudioComposerModeSelector extends ConsumerWidget {
  final StudioPromptMode value;

  const StudioComposerModeSelector({super.key, required this.value});

  static const _visibleModes = <StudioPromptMode>[
    StudioPromptMode.ask,
    StudioPromptMode.research,
    StudioPromptMode.code,
    StudioPromptMode.review,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final displayValue = _visibleModes.contains(value)
        ? value
        : StudioPromptMode.code;
    return PopupMenuButton<StudioPromptMode>(
      tooltip: 'Task mode',
      color: tokens.studioPanel,
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: studioComposerSoftMenuShape(tokens),
      onSelected: (mode) =>
          ref.read(studioShellProvider.notifier).setPromptMode(mode),
      itemBuilder: (context) => [
        for (final mode in _visibleModes)
          PopupMenuItem(
            height: 34,
            value: mode,
            child: Text(
              mode.label,
              style: TextStyle(
                color: mode == displayValue
                    ? tokens.textSecondary
                    : tokens.textMuted,
                fontSize: FontSizes.xs,
                fontWeight: mode == displayValue
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
            ),
          ),
      ],
      child: StudioComposerPill(
        icon: StudioIcons.routeOutlined,
        label: displayValue.label,
        trailing: StudioIcons.expandMore,
      ),
    );
  }
}

class StudioComposerPlanModeToggle extends ConsumerWidget {
  final bool enabled;

  const StudioComposerPlanModeToggle({super.key, required this.enabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: enabled
          ? 'Plan Mode is on'
          : 'Create a plan before making changes',
      child: StudioFocusableActionSurface(
        semanticLabel: 'Toggle Plan mode',
        selected: enabled,
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: () => ref.read(studioShellProvider.notifier).togglePlanMode(),
        child: StudioComposerPill(
          icon: StudioIcons.altRouteOutlined,
          label: 'Plan',
          active: enabled,
        ),
      ),
    );
  }
}

class StudioComposerSpecialistAgentSelector extends ConsumerWidget {
  final SpecialistAgentId value;

  const StudioComposerSpecialistAgentSelector({super.key, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    const registry = SpecialistAgentRegistry();
    final selected = registry.descriptorFor(value);
    return PopupMenuButton<SpecialistAgentId>(
      tooltip: 'Enterprise specialist',
      color: tokens.studioPanel,
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: studioComposerSoftMenuShape(tokens),
      onSelected: (agentId) =>
          ref.read(studioShellProvider.notifier).setSpecialistAgent(agentId),
      itemBuilder: (context) => [
        for (final descriptor in registry.selectableDescriptors)
          PopupMenuItem<SpecialistAgentId>(
            height: 44,
            value: descriptor.id,
            child: SizedBox(
              width: 258,
              child: Row(
                children: [
                  Icon(
                    _specialistIcon(descriptor.id),
                    color: tokens.textMuted,
                    size: 13,
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          descriptor.label,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FontSizes.xs,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          descriptor.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: FontSizes.xxs,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (descriptor.id == value)
                    Icon(
                      StudioIcons.check,
                      color: tokens.textPrimary,
                      size: 13,
                    ),
                ],
              ),
            ),
          ),
      ],
      child: StudioComposerPill(
        icon: _specialistIcon(value),
        label: selected.shortLabel,
        trailing: StudioIcons.expandMore,
      ),
    );
  }
}

class StudioComposerPermissionsSelector extends ConsumerWidget {
  const StudioComposerPermissionsSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Tooltip(
      message:
          'Studio uses review-first permissions. Approval grants live on each tool request and can be scoped to one action or this turn.',
      child: StudioComposerPill(
        icon: StudioIcons.backHandOutlined,
        label: 'Review first',
      ),
    );
  }
}

class StudioComposerExecutionModeSelector extends ConsumerWidget {
  final StudioExecutionMode value;

  const StudioComposerExecutionModeSelector({super.key, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return PopupMenuButton<StudioExecutionMode>(
      tooltip: 'Execution mode',
      color: tokens.studioPanel,
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: studioComposerSoftMenuShape(tokens),
      onSelected: (mode) =>
          ref.read(studioShellProvider.notifier).setExecutionMode(mode),
      itemBuilder: (context) => [
        PopupMenuItem(
          height: 34,
          value: StudioExecutionMode.local,
          child: Text(
            'Local project',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        PopupMenuItem(
          height: 48,
          value: StudioExecutionMode.worktree,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Isolated worktree',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Create a task branch and keep its files separate',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                ),
              ),
            ],
          ),
        ),
      ],
      child: StudioComposerPill(
        icon: StudioIcons.computerOutlined,
        label: value.label,
        trailing: StudioIcons.expandMore,
      ),
    );
  }
}

IconData _specialistIcon(SpecialistAgentId id) {
  return switch (id) {
    SpecialistAgentId.auto => StudioIcons.autoAwesomeOutlined,
    SpecialistAgentId.topologyDesigner => StudioIcons.accountTreeOutlined,
    SpecialistAgentId.solutionSizer => StudioIcons.straightenOutlined,
    SpecialistAgentId.lifecycleValidator => StudioIcons.eventAvailableOutlined,
    SpecialistAgentId.architectureReviewer => StudioIcons.factCheckOutlined,
    SpecialistAgentId.businessUseCaseResearcher =>
      StudioIcons.queryStatsOutlined,
    SpecialistAgentId.evidenceReviewer => StudioIcons.verifiedOutlined,
  };
}
