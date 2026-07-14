import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../agent/config/models_config.dart';
import '../../core/constants/design_tokens.dart';
import '../../enums/ai_provider.dart';
import '../../agent/tools/tool_registry.dart';
import '../../models/agent_config_model.dart';
import '../../models/agent_trigger.dart';
import '../../models/turn_intent.dart';
import '../../state/agent_manager_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';

class AgentConfigDialog extends ConsumerStatefulWidget {
  final AgentConfigModel? existing;

  const AgentConfigDialog({super.key, this.existing});

  @override
  ConsumerState<AgentConfigDialog> createState() => _AgentConfigDialogState();
}

class _AgentConfigDialogState extends ConsumerState<AgentConfigDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _promptController;
  late final TextEditingController _revisionController;
  late final TextEditingController _evaluationPromptController;
  late String _model;
  late Set<String> _selectedTools;
  late List<AgentTrigger> _triggers;
  late Set<TurnIntent> _allowedIntents;
  late AgentContextPolicy _contextPolicy;
  late Set<AgentOutputContract> _outputContracts;
  late int _maxTurns;
  late int _maxToolCalls;
  late Duration _maxWallTime;
  late List<AgentEvaluationCase> _additionalEvaluationCases;
  bool _evaluationRequiresCitation = false;

  static final _models = ModelsConfig.ciscoModels
      .map((model) => model.id)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _descController = TextEditingController(text: e?.description ?? '');
    _promptController = TextEditingController(text: e?.systemPrompt ?? '');
    _revisionController = TextEditingController(
      text: e?.author.revision ?? '1',
    );
    final primaryEvaluation = e?.evaluationSuite.cases.firstOrNull;
    _evaluationPromptController = TextEditingController(
      text:
          primaryEvaluation?.prompt ??
          'Explain the agent purpose, limits, and expected output without changing files.',
    );
    _evaluationRequiresCitation = primaryEvaluation?.requiresCitation ?? false;
    _additionalEvaluationCases = List.from(
      e?.evaluationSuite.cases.skip(1) ?? const <AgentEvaluationCase>[],
    );
    _model = ModelsConfig.coerceModelForProvider(
      AIProviderType.cisco,
      e?.model,
    );
    _selectedTools = Set.from(e?.allowedTools ?? {});
    _triggers = List.from(e?.triggers ?? []);
    _allowedIntents = Set.from(e?.allowedIntents ?? {TurnIntent.ask});
    _contextPolicy = e?.contextPolicy ?? AgentContextPolicy.projectOnly;
    _outputContracts = Set.from(
      e?.outputContracts ?? {AgentOutputContract.summary},
    );
    _maxTurns = e?.limits.maxTurns ?? 4;
    _maxToolCalls = e?.limits.maxToolCalls ?? 12;
    _maxWallTime = e?.limits.maxWallTime ?? const Duration(minutes: 5);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _promptController.dispose();
    _revisionController.dispose();
    _evaluationPromptController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final revision = _revisionController.text.trim();
    if (revision.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Version is required.')));
      return;
    }

    final config = AgentConfigModel(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: name,
      description: _descController.text.trim(),
      systemPrompt: _promptController.text.trim(),
      allowedTools: _selectedTools,
      model: _model,
      autoApprove: false,
      enabled: widget.existing?.enabled ?? false,
      enabledAt: widget.existing?.enabledAt,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      triggers: _triggers,
      allowedIntents: _allowedIntents,
      contextPolicy: _contextPolicy,
      outputContracts: _outputContracts,
      limits: AgentExecutionLimits(
        maxTurns: _maxTurns,
        maxToolCalls: _maxToolCalls,
        maxWallTime: _maxWallTime,
      ),
      author: AgentAuthorMetadata(
        author: widget.existing?.author.author ?? 'local',
        revision: revision,
      ),
      evaluationSuite: AgentEvaluationSuite(
        cases: [
          AgentEvaluationCase(
            id:
                widget.existing?.evaluationSuite.cases.firstOrNull?.id ??
                'primary',
            prompt: _evaluationPromptController.text.trim(),
            intent: _allowedIntents.contains(TurnIntent.ask)
                ? TurnIntent.ask
                : _allowedIntents.first,
            requiredOutputContracts: _evaluationRequiresCitation
                ? {AgentOutputContract.summary, AgentOutputContract.evidence}
                : const {AgentOutputContract.summary},
            maxToolCalls: 0,
            requiresCitation: _evaluationRequiresCitation,
          ),
          ..._additionalEvaluationCases,
        ],
        minimumPassRate: widget.existing?.evaluationSuite.minimumPassRate ?? 1,
      ),
    );
    final errors = config.validate();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errors.first)));
      return;
    }
    try {
      await ref.read(agentManagerProvider.notifier).saveConfig(config);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final allToolNames = ToolRegistry.allTools
        .map((tool) => tool.name)
        .where(AgentManifest.supportedTools.contains)
        .toList();

    return Dialog(
      backgroundColor: tokens.bgMain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
        side: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                widget.existing != null ? 'Edit Agent' : 'New Agent',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.lg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.xl),

              // Scrollable form
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildField(
                        tokens,
                        'Name',
                        _nameController,
                        hint: 'e.g., Code Reviewer',
                      ),
                      const SizedBox(height: Spacing.lg),
                      _buildField(
                        tokens,
                        'Description',
                        _descController,
                        hint: 'What does this agent do?',
                      ),
                      const SizedBox(height: Spacing.lg),
                      _buildField(
                        tokens,
                        'System Prompt',
                        _promptController,
                        hint: 'Custom instructions for the agent...',
                        maxLines: 5,
                      ),
                      const SizedBox(height: Spacing.lg),
                      _buildField(
                        tokens,
                        'Version',
                        _revisionController,
                        hint: 'e.g., 1 or 1.1',
                      ),
                      const SizedBox(height: Spacing.lg),
                      _buildLabel(tokens, 'Activation evaluation'),
                      const SizedBox(height: Spacing.sm),
                      _buildField(
                        tokens,
                        'Test prompt',
                        _evaluationPromptController,
                        hint: 'A representative task this agent must handle',
                        maxLines: 3,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _evaluationRequiresCitation,
                        title: Text(
                          'Requires evidence citation',
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: FontSizes.xs,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _evaluationRequiresCitation = value ?? false;
                            if (_evaluationRequiresCitation) {
                              _outputContracts.add(
                                AgentOutputContract.evidence,
                              );
                            }
                          });
                        },
                      ),
                      Text(
                        'This fixture checks intent, output contract, citation rule, and tool limit before the agent can be enabled. Import packages can carry additional fixtures.',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xxs,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: Spacing.lg),

                      // Model dropdown
                      _buildLabel(tokens, 'Model'),
                      const SizedBox(height: Spacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.lg,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.inputBg,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: tokens.inputBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _model,
                            isExpanded: true,
                            dropdownColor: tokens.bgLighter,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FontSizes.sm,
                            ),
                            items: _models
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _model = v);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: Spacing.lg),

                      _buildLabel(tokens, 'Allowed Studio intents'),
                      const SizedBox(height: Spacing.sm),
                      Wrap(
                        spacing: Spacing.sm,
                        runSpacing: Spacing.sm,
                        children: TurnIntent.values
                            .map(
                              (intent) => FilterChip(
                                selected: _allowedIntents.contains(intent),
                                label: Text(_intentLabel(intent)),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _allowedIntents.add(intent);
                                    } else {
                                      _allowedIntents.remove(intent);
                                    }
                                  });
                                },
                                selectedColor: tokens.accent.withValues(
                                  alpha: 0.2,
                                ),
                                checkmarkColor: tokens.accent,
                                labelStyle: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: FontSizes.xs,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: Spacing.lg),

                      _buildLabel(tokens, 'Context policy'),
                      const SizedBox(height: Spacing.sm),
                      _buildDropdown<AgentContextPolicy>(
                        tokens: tokens,
                        value: _contextPolicy,
                        items: AgentContextPolicy.values
                            .map(
                              (policy) => DropdownMenuItem(
                                value: policy,
                                child: Text(_contextPolicyLabel(policy)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (policy) {
                          if (policy != null) {
                            setState(() => _contextPolicy = policy);
                          }
                        },
                      ),
                      if (_contextPolicy != AgentContextPolicy.projectOnly)
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.sm),
                          child: Text(
                            'This policy omits repository-reading and command tools. Only current-turn attachments and reviewable patch proposals remain available.',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: FontSizes.xs,
                              height: 1.35,
                            ),
                          ),
                        ),
                      const SizedBox(height: Spacing.lg),

                      _buildLabel(tokens, 'Required output contracts'),
                      const SizedBox(height: Spacing.sm),
                      Wrap(
                        spacing: Spacing.sm,
                        runSpacing: Spacing.sm,
                        children: AgentOutputContract.values
                            .map(
                              (contract) => FilterChip(
                                selected: _outputContracts.contains(contract),
                                label: Text(_outputContractLabel(contract)),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _outputContracts.add(contract);
                                    } else {
                                      _outputContracts.remove(contract);
                                    }
                                  });
                                },
                                selectedColor: tokens.accent.withValues(
                                  alpha: 0.2,
                                ),
                                checkmarkColor: tokens.accent,
                                labelStyle: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: FontSizes.xs,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: Spacing.lg),

                      _buildLabel(tokens, 'Execution limits'),
                      const SizedBox(height: Spacing.sm),
                      Wrap(
                        spacing: Spacing.md,
                        runSpacing: Spacing.sm,
                        children: [
                          _buildLimitDropdown<int>(
                            tokens: tokens,
                            label: 'Turns',
                            value: _maxTurns,
                            values: const [1, 2, 4, 6],
                            display: (value) => '$value',
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _maxTurns = value);
                              }
                            },
                          ),
                          _buildLimitDropdown<int>(
                            tokens: tokens,
                            label: 'Tool calls',
                            value: _maxToolCalls,
                            values: const [0, 4, 8, 12, 24],
                            display: (value) => '$value',
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _maxToolCalls = value);
                              }
                            },
                          ),
                          _buildLimitDropdown<Duration>(
                            tokens: tokens,
                            label: 'Wall time',
                            value: _maxWallTime,
                            values: const [
                              Duration(minutes: 1),
                              Duration(minutes: 5),
                              Duration(minutes: 10),
                              Duration(minutes: 30),
                            ],
                            display: (value) => '${value.inMinutes} min',
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _maxWallTime = value);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.lg),

                      // Tools
                      _buildLabel(tokens, 'Tools (empty = no tool access)'),
                      const SizedBox(height: Spacing.sm),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        decoration: BoxDecoration(
                          color: tokens.inputBg,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: tokens.inputBorder),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            vertical: Spacing.sm,
                          ),
                          children: allToolNames.map((tool) {
                            final selected = _selectedTools.contains(tool);
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (selected) {
                                    _selectedTools.remove(tool);
                                  } else {
                                    _selectedTools.add(tool);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Spacing.lg,
                                  vertical: Spacing.xs,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank,
                                      size: 16,
                                      color: selected
                                          ? tokens.accent
                                          : tokens.textMuted,
                                    ),
                                    const SizedBox(width: Spacing.md),
                                    Text(
                                      tool,
                                      style: TextStyle(
                                        color: tokens.textSecondary,
                                        fontSize: FontSizes.xs,
                                        fontFamily: 'JetBrains Mono',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: Spacing.lg),

                      Text(
                        'Tool actions always require the shared Studio review flow. Custom agents cannot auto-approve.',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: Spacing.xl),

                      // Triggers section
                      _buildLabel(tokens, 'Background Triggers'),
                      const SizedBox(height: Spacing.sm),
                      ..._triggers.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final trigger = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: Spacing.sm),
                          padding: const EdgeInsets.all(Spacing.md),
                          decoration: BoxDecoration(
                            color: tokens.inputBg,
                            borderRadius: BorderRadius.circular(Radii.md),
                            border: Border.all(color: tokens.inputBorder),
                          ),
                          child: Row(
                            children: [
                              Switch(
                                value: trigger.enabled,
                                onChanged: (v) {
                                  setState(() {
                                    _triggers[idx] = trigger.copyWith(
                                      enabled: v,
                                    );
                                  });
                                },
                                activeTrackColor: tokens.accent,
                              ),
                              const SizedBox(width: Spacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trigger.type.displayName,
                                      style: TextStyle(
                                        color: tokens.textPrimary,
                                        fontSize: FontSizes.xs,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (trigger.filePatterns.isNotEmpty)
                                      Text(
                                        trigger.filePatterns.join(', '),
                                        style: TextStyle(
                                          color: tokens.textMuted,
                                          fontSize: FontSizes.xxs,
                                          fontFamily: 'JetBrains Mono',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() => _triggers.removeAt(idx));
                                },
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: tokens.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      GestureDetector(
                        onTap: () => _showAddTriggerDialog(context, tokens),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            padding: const EdgeInsets.all(Spacing.md),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Radii.md),
                              border: Border.all(
                                color: tokens.accent.withValues(alpha: 0.3),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add, size: 14, color: tokens.accent),
                                const SizedBox(width: Spacing.sm),
                                Text(
                                  'Add Trigger',
                                  style: TextStyle(
                                    color: tokens.accent,
                                    fontSize: FontSizes.xs,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.xl),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textMuted,
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: Spacing.md),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddTriggerDialog(BuildContext context, ThemeTokens tokens) {
    AgentTriggerType selectedType = AgentTriggerType.onFileSave;
    final patternController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: tokens.bgMain,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
            side: BorderSide(color: tokens.border),
          ),
          title: Text(
            'Add Trigger',
            style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.lg),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                decoration: BoxDecoration(
                  color: tokens.inputBg,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: tokens.inputBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AgentTriggerType>(
                    value: selectedType,
                    isExpanded: true,
                    dropdownColor: tokens.bgLighter,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                    ),
                    items: AgentTriggerType.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedType = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              Text(
                selectedType.description,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
              if (selectedType == AgentTriggerType.onFileSave) ...[
                const SizedBox(height: Spacing.lg),
                TextField(
                  controller: patternController,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontFamily: 'JetBrains Mono',
                  ),
                  decoration: InputDecoration(
                    hintText: '**/*.dart, **/*.py (empty = all files)',
                    hintStyle: TextStyle(
                      color: tokens.textDisabled,
                      fontSize: FontSizes.xs,
                    ),
                    filled: true,
                    fillColor: tokens.inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.md),
                      borderSide: BorderSide(color: tokens.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.md),
                      borderSide: BorderSide(color: tokens.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.md),
                      borderSide: BorderSide(color: tokens.inputFocusBorder),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: tokens.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                final patterns = patternController.text
                    .split(',')
                    .map((p) => p.trim())
                    .where((p) => p.isNotEmpty)
                    .toList();
                setState(() {
                  _triggers.add(
                    AgentTrigger(type: selectedType, filePatterns: patterns),
                  );
                });
                Navigator.of(ctx).pop();
              },
              child: Text('Add', style: TextStyle(color: tokens.accent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required ThemeTokens tokens,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.inputBg,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.inputBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: tokens.bgLighter,
          style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.sm),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildLimitDropdown<T>({
    required ThemeTokens tokens,
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) display,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xxs),
          ),
          const SizedBox(height: Spacing.xs),
          _buildDropdown<T>(
            tokens: tokens,
            value: value,
            items: values
                .map(
                  (candidate) => DropdownMenuItem<T>(
                    value: candidate,
                    child: Text(display(candidate)),
                  ),
                )
                .toList(growable: false),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(ThemeTokens tokens, String label) {
    return Text(
      label,
      style: TextStyle(
        color: tokens.textMuted,
        fontSize: FontSizes.xs,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildField(
    ThemeTokens tokens,
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLabel(tokens, label),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.sm),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: tokens.textDisabled,
              fontSize: FontSizes.sm,
            ),
            filled: true,
            fillColor: tokens.inputBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(color: tokens.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(color: tokens.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              borderSide: BorderSide(color: tokens.inputFocusBorder),
            ),
          ),
        ),
      ],
    );
  }
}

String _intentLabel(TurnIntent intent) {
  return switch (intent) {
    TurnIntent.chat => 'Chat',
    TurnIntent.ask => 'Ask',
    TurnIntent.plan => 'Plan',
    TurnIntent.code => 'Code',
    TurnIntent.review => 'Review',
    TurnIntent.verify => 'Verify',
  };
}

String _contextPolicyLabel(AgentContextPolicy policy) {
  return switch (policy) {
    AgentContextPolicy.projectOnly => 'Project retrieval',
    AgentContextPolicy.selectedFiles => 'Selected files only',
    AgentContextPolicy.userProvidedOnly => 'User-provided only',
  };
}

String _outputContractLabel(AgentOutputContract contract) {
  return switch (contract) {
    AgentOutputContract.summary => 'Summary',
    AgentOutputContract.plan => 'Plan',
    AgentOutputContract.patchProposal => 'Patch proposal',
    AgentOutputContract.evidence => 'Evidence',
  };
}

/// Helper to show the dialog
Future<void> showAgentConfigDialog(
  BuildContext context, {
  AgentConfigModel? existing,
}) {
  return showDialog(
    context: context,
    builder: (_) => AgentConfigDialog(existing: existing),
  );
}
