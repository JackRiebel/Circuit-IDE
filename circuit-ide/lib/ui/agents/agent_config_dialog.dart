import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/design_tokens.dart';
import '../../agent/tools/tool_registry.dart';
import '../../models/agent_config_model.dart';
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
  late String _model;
  late bool _autoApprove;
  late Set<String> _selectedTools;

  static const _models = [
    'gpt-4.1',
    'gpt-4.1-mini',
    'gpt-4.1-nano',
    'claude-sonnet-4-20250514',
    'claude-haiku-4-5-20251001',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _descController = TextEditingController(text: e?.description ?? '');
    _promptController = TextEditingController(text: e?.systemPrompt ?? '');
    _model = e?.model ?? 'gpt-4o';
    _autoApprove = e?.autoApprove ?? false;
    _selectedTools = Set.from(e?.allowedTools ?? {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final config = AgentConfigModel(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: name,
      description: _descController.text.trim(),
      systemPrompt: _promptController.text.trim(),
      allowedTools: _selectedTools,
      model: _model,
      autoApprove: _autoApprove,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );

    ref.read(agentManagerProvider.notifier).saveConfig(config);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final allToolNames = ToolRegistry.allTools.map((t) => t.name).toList();

    return Dialog(
      backgroundColor: tokens.bgMain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
        side: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
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
                      _buildField(tokens, 'Name', _nameController,
                          hint: 'e.g., Code Reviewer'),
                      const SizedBox(height: Spacing.lg),
                      _buildField(tokens, 'Description', _descController,
                          hint: 'What does this agent do?'),
                      const SizedBox(height: Spacing.lg),
                      _buildField(
                          tokens, 'System Prompt', _promptController,
                          hint:
                              'Custom instructions for the agent...',
                          maxLines: 5),
                      const SizedBox(height: Spacing.lg),

                      // Model dropdown
                      _buildLabel(tokens, 'Model'),
                      const SizedBox(height: Spacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.lg),
                        decoration: BoxDecoration(
                          color: tokens.inputBg,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(
                              color: tokens.inputBorder),
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
                                .map((m) => DropdownMenuItem(
                                    value: m, child: Text(m)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _model = v);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: Spacing.lg),

                      // Tools
                      _buildLabel(tokens, 'Tools (empty = all)'),
                      const SizedBox(height: Spacing.sm),
                      Container(
                        constraints:
                            const BoxConstraints(maxHeight: 120),
                        decoration: BoxDecoration(
                          color: tokens.inputBg,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(
                              color: tokens.inputBorder),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                              vertical: Spacing.sm),
                          children: allToolNames.map((tool) {
                            final selected =
                                _selectedTools.contains(tool);
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
                                          : Icons
                                              .check_box_outline_blank,
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

                      // Auto-approve toggle
                      Row(
                        children: [
                          Switch(
                            value: _autoApprove,
                            onChanged: (v) =>
                                setState(() => _autoApprove = v),
                            activeTrackColor: tokens.accent,
                          ),
                          const SizedBox(width: Spacing.md),
                          Text(
                            'Auto-approve tool calls',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: FontSizes.sm,
                            ),
                          ),
                        ],
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
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.sm,
          ),
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
