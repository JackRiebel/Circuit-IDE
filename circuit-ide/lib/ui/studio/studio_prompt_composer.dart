import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../agent/config/models_config.dart';
import '../../agent/providers/provider_interface.dart';
import '../../core/constants/design_tokens.dart';
import '../../models/settings_model.dart';
import '../../models/specialist_agent.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_shell.dart';
import '../../models/token_usage.dart';
import '../../state/file_tree_provider.dart';
import '../../state/git_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_token_usage_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/workspace_session_provider.dart';
import '../../theme/theme_tokens.dart';
import '../../core/config/studio_feature_flags.dart';

class StudioPromptComposer extends ConsumerStatefulWidget {
  final String hintText;
  final String submitTooltip;
  final ValueChanged<String> onSubmit;
  final bool compact;
  final String? taskId;

  const StudioPromptComposer({
    super.key,
    required this.hintText,
    required this.onSubmit,
    this.submitTooltip = 'Start',
    this.compact = false,
    this.taskId,
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
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(
      studioShellProvider.select((state) => state.composerText),
      (previous, next) {
        if (next == _controller.text) return;
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      },
    );
    final tokens = ref.watch(themeProvider);
    final studioControls = ref.watch(
      studioShellProvider.select(
        (state) => (
          promptMode: state.promptMode,
          planModeEnabled: state.planModeEnabled,
          specialistAgentId: state.specialistAgentId,
          executionMode: state.executionMode,
        ),
      ),
    );
    final rootPath = ref.watch(
      fileTreeProvider.select((state) => state.rootPath),
    );
    final branch = ref.watch(
      gitProvider.select((state) => state.status.branch),
    );
    final settings = ref.watch(settingsProvider);
    final tokenUsage = ref.watch(
      studioTokenUsageForTaskViewProvider(widget.taskId),
    );
    final projectLabel = rootPath == null
        ? 'Choose project'
        : p.basename(rootPath);

    return Container(
      decoration: BoxDecoration(
        color: tokens.studioComposer,
        borderRadius: BorderRadius.circular(widget.compact ? 16 : 19),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: widget.compact ? 0.035 : 0.06,
            ),
            blurRadius: widget.compact ? 6 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_slashMatches.isNotEmpty)
            _SlashCommandMenu(
              commands: _slashMatches,
              onSelect: _applySlashCommand,
            ),
          Container(
            height: widget.compact ? 78 : 80,
            padding: const EdgeInsets.fromLTRB(13, 10, 8, 8),
            child: Column(
              children: [
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): _submit,
                      const SingleActivator(LogicalKeyboardKey.numpadEnter):
                          _submit,
                    },
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: widget.compact ? 3 : 4,
                      textInputAction: TextInputAction.send,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.md,
                        height: 1.22,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.md,
                          height: 1.22,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        filled: false,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const _AddContextButton(),
                            const SizedBox(width: 9),
                            const _PermissionsSelector(),
                            const SizedBox(width: 9),
                            _ComposerModeSelector(
                              value: studioControls.promptMode,
                            ),
                            const SizedBox(width: 9),
                            _PlanModeToggle(
                              enabled: studioControls.planModeEnabled,
                            ),
                            const SizedBox(width: 9),
                            if (widget.compact &&
                                StudioFeatureFlags.enterpriseSpecialists) ...[
                              _SpecialistAgentSelector(
                                value: studioControls.specialistAgentId,
                              ),
                              const SizedBox(width: 9),
                            ],
                            _ModelSelector(selectedModel: settings.ciscoModel),
                            const SizedBox(width: 9),
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
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _controller.text.trim().isEmpty
                                ? tokens.studioControl.withValues(alpha: 0.52)
                                : tokens.textPrimary.withValues(alpha: 0.94),
                            shape: BoxShape.circle,
                            border: _controller.text.trim().isEmpty
                                ? Border.all(
                                    color: tokens.studioDivider.withValues(
                                      alpha: 0.28,
                                    ),
                                  )
                                : null,
                          ),
                          child: Icon(
                            Icons.arrow_upward,
                            color: _controller.text.trim().isEmpty
                                ? tokens.textMuted
                                : tokens.bgDark,
                            size: 16,
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
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              decoration: BoxDecoration(
                color: tokens.surfaceBase.withValues(alpha: 0.16),
                border: Border(
                  top: BorderSide(
                    color: tokens.studioDivider.withValues(alpha: 0.54),
                  ),
                ),
              ),
              child: Row(
                children: [
                  _ProjectPickerPill(
                    icon: Icons.folder_copy_outlined,
                    label: projectLabel,
                  ),
                  const SizedBox(width: Spacing.xl),
                  _ExecutionModeSelector(value: studioControls.executionMode),
                  const SizedBox(width: Spacing.xl),
                  _ComposerPill(
                    icon: Icons.account_tree_outlined,
                    label: branch.isEmpty ? 'main' : branch,
                  ),
                  const SizedBox(width: Spacing.xl),
                  if (StudioFeatureFlags.enterpriseSpecialists)
                    _SpecialistAgentSelector(
                      value: studioControls.specialistAgentId,
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

  List<_SlashCommand> get _slashMatches {
    final text = _controller.text.trimLeft();
    if (!text.startsWith('/')) return const [];
    final query = text.substring(1).toLowerCase();
    return _slashCommands
        .where((command) => command.name.startsWith(query))
        .take(8)
        .toList();
  }

  void _applySlashCommand(_SlashCommand command) {
    command.run?.call(ref);
    if (command.prompt.isNotEmpty) {
      _controller.text = command.prompt;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    } else {
      _controller.clear();
    }
  }
}

class _ComposerModeSelector extends ConsumerWidget {
  final StudioPromptMode value;

  const _ComposerModeSelector({required this.value});

  static const _visibleModes = <StudioPromptMode>[
    StudioPromptMode.ask,
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
      shape: _softMenuShape(tokens),
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
      child: _ComposerPill(
        icon: Icons.route_outlined,
        label: displayValue.label,
        trailing: Icons.expand_more,
      ),
    );
  }
}

class _PlanModeToggle extends ConsumerWidget {
  final bool enabled;

  const _PlanModeToggle({required this.enabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: enabled
          ? 'Plan Mode is on'
          : 'Create a plan before making changes',
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: () => ref.read(studioShellProvider.notifier).togglePlanMode(),
        child: _ComposerPill(
          icon: Icons.alt_route_outlined,
          label: 'Plan',
          active: enabled,
        ),
      ),
    );
  }
}

class _SpecialistAgentSelector extends ConsumerWidget {
  final SpecialistAgentId value;

  const _SpecialistAgentSelector({required this.value});

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
      shape: _softMenuShape(tokens),
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
                    Icon(Icons.check, color: tokens.textPrimary, size: 13),
                ],
              ),
            ),
          ),
      ],
      child: _ComposerPill(
        icon: _specialistIcon(value),
        label: selected.shortLabel,
        trailing: Icons.expand_more,
      ),
    );
  }
}

class _PermissionsSelector extends ConsumerWidget {
  const _PermissionsSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Tooltip(
      message:
          'Studio uses review-first permissions. Approval grants live on each tool request and can be scoped to one action or this turn.',
      child: _ComposerPill(
        icon: Icons.back_hand_outlined,
        label: 'Review first',
      ),
    );
  }
}

IconData _specialistIcon(SpecialistAgentId id) {
  return switch (id) {
    SpecialistAgentId.auto => Icons.auto_awesome_outlined,
    SpecialistAgentId.topologyDesigner => Icons.account_tree_outlined,
    SpecialistAgentId.solutionSizer => Icons.straighten_outlined,
    SpecialistAgentId.lifecycleValidator => Icons.event_available_outlined,
    SpecialistAgentId.architectureReviewer => Icons.fact_check_outlined,
    SpecialistAgentId.businessUseCaseResearcher => Icons.query_stats_outlined,
    SpecialistAgentId.evidenceReviewer => Icons.verified_outlined,
  };
}

class _ExecutionModeSelector extends ConsumerWidget {
  final StudioExecutionMode value;

  const _ExecutionModeSelector({required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return PopupMenuButton<StudioExecutionMode>(
      tooltip: 'Execution mode',
      color: tokens.studioPanel,
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: _softMenuShape(tokens),
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
      ],
      child: _ComposerPill(
        icon: Icons.computer_outlined,
        label: value.label,
        trailing: Icons.expand_more,
      ),
    );
  }
}

class _SlashCommandMenu extends ConsumerWidget {
  final List<_SlashCommand> commands;
  final ValueChanged<_SlashCommand> onSelect;

  const _SlashCommandMenu({required this.commands, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: tokens.studioDrawer.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.66)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final command in commands)
              _SlashCommandRow(command: command, onSelect: onSelect),
          ],
        ),
      ),
    );
  }
}

class _SlashCommandRow extends ConsumerWidget {
  final _SlashCommand command;
  final ValueChanged<_SlashCommand> onSelect;

  const _SlashCommandRow({required this.command, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      onTap: () => onSelect(command),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.studioControl.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(command.icon, size: 14, color: tokens.textMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  command.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Flexible(
                child: Text(
                  command.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlashCommand {
  final String name;
  final String title;
  final String detail;
  final String prompt;
  final IconData icon;
  final void Function(WidgetRef ref)? run;

  const _SlashCommand({
    required this.name,
    required this.title,
    required this.detail,
    required this.prompt,
    required this.icon,
    this.run,
  });
}

final _slashCommands = <_SlashCommand>[
  const _SlashCommand(
    name: 'status',
    title: 'Status',
    detail: 'Summarize project state',
    prompt: 'Summarize the current project status, branch, changes, and risks.',
    icon: Icons.radio_button_checked,
  ),
  _SlashCommand(
    name: 'review',
    title: 'Review',
    detail: 'Inspect current changes',
    prompt: 'Review the current changes and call out risks or missing checks.',
    icon: Icons.rate_review_outlined,
    run: (ref) => ref
        .read(studioShellProvider.notifier)
        .setPromptMode(StudioPromptMode.review),
  ),
  _SlashCommand(
    name: 'plan',
    title: 'Plan',
    detail: 'Create plan first',
    prompt: 'Create a short implementation plan before making changes.',
    icon: Icons.alt_route_outlined,
    run: (ref) =>
        ref.read(studioShellProvider.notifier).setPlanModeEnabled(true),
  ),
  const _SlashCommand(
    name: 'init',
    title: 'Initialize',
    detail: 'Explain structure',
    prompt:
        'Inspect this project and explain its structure and best next steps.',
    icon: Icons.auto_awesome_outlined,
  ),
  _SlashCommand(
    name: 'files',
    title: 'Files',
    detail: 'Open file drawer',
    prompt: '',
    icon: Icons.folder_outlined,
    run: (ref) => ref
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.files),
  ),
  _SlashCommand(
    name: 'context',
    title: 'Context',
    detail: 'Open context drawer',
    prompt: '',
    icon: Icons.inventory_2_outlined,
    run: (ref) => ref.read(studioRightDrawerProvider.notifier).openContext(),
  ),
  _SlashCommand(
    name: 'terminal',
    title: 'Terminal',
    detail: 'Open command logs',
    prompt: '',
    icon: Icons.terminal_outlined,
    run: (ref) => ref
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.terminal),
  ),
  const _SlashCommand(
    name: 'image',
    title: 'Image',
    detail: 'Attach image path',
    prompt: '/image ',
    icon: Icons.image_outlined,
  ),
  const _SlashCommand(
    name: 'screenshot',
    title: 'Screenshot',
    detail: 'Attach screenshot path',
    prompt: '/screenshot ',
    icon: Icons.screenshot_monitor_outlined,
  ),
];

class _ComposerPill extends ConsumerWidget {
  final IconData? icon;
  final String label;
  final IconData? trailing;
  final bool active;

  const _ComposerPill({
    this.icon,
    required this.label,
    this.trailing,
    this.active = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return AnimatedContainer(
      duration: AnimationDurations.fast,
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

class _AddContextButton extends ConsumerWidget {
  const _AddContextButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Tooltip(
      message: 'Add context',
      child: InkWell(
        onTap: () {
          ref.read(studioShellProvider.notifier).showRightProgressPanel();
          ref.read(studioRightDrawerProvider.notifier).openContext();
        },
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Icon(Icons.add, color: tokens.textMuted, size: 14),
        ),
      ),
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
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: _softMenuShape(tokens),
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
                    '${model.supportsTools ? ' · tools' : ' · chat only'}',
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
        padding: const EdgeInsets.symmetric(vertical: 5),
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
      .read(workspaceSessionProvider.notifier)
      .openWorkspaceAndBindAgent(result);
  if (!openResult.success) return;
  ref.read(settingsProvider.notifier).addRecentProject(result);
  ref.read(studioShellProvider.notifier).openProject(result);
}

ShapeBorder _softMenuShape(ThemeTokens tokens) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
    side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.64)),
  );
}
