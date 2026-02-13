import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_config_model.dart';
import '../../state/agent_manager_provider.dart';
import '../../state/theme_provider.dart';

class AgentRunDialog extends ConsumerStatefulWidget {
  final AgentConfigModel config;

  const AgentRunDialog({super.key, required this.config});

  @override
  ConsumerState<AgentRunDialog> createState() => _AgentRunDialogState();
}

class _AgentRunDialogState extends ConsumerState<AgentRunDialog> {
  final _taskController = TextEditingController();
  final _selectedConfigs = <String>{};
  bool _multiMode = false;

  @override
  void initState() {
    super.initState();
    _selectedConfigs.add(widget.config.id);
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  void _run() {
    final task = _taskController.text.trim();
    if (task.isEmpty) return;

    final notifier = ref.read(agentManagerProvider.notifier);
    if (_multiMode && _selectedConfigs.length > 1) {
      notifier.spawnMultiple(
        _selectedConfigs.map((id) => (id, task)).toList(),
      );
    } else {
      notifier.spawnAgent(widget.config.id, task);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final configs = ref.watch(agentManagerProvider).configs;

    return Dialog(
      backgroundColor: tokens.bgMain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
        side: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Run Agent',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.lg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                widget.config.name,
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: FontSizes.sm,
                ),
              ),
              const SizedBox(height: Spacing.xl),

              // Task description
              Text(
                'Task',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: _taskController,
                maxLines: 3,
                autofocus: true,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                ),
                decoration: InputDecoration(
                  hintText: 'Describe the task for this agent...',
                  hintStyle: TextStyle(
                    color: tokens.textDisabled,
                    fontSize: FontSizes.sm,
                  ),
                  filled: true,
                  fillColor: tokens.inputBg,
                  contentPadding: const EdgeInsets.all(Spacing.lg),
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
                    borderSide:
                        BorderSide(color: tokens.inputFocusBorder),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),

              // Multi-agent toggle
              if (configs.length > 1) ...[
                Row(
                  children: [
                    Switch(
                      value: _multiMode,
                      onChanged: (v) => setState(() => _multiMode = v),
                      activeTrackColor: tokens.accent,
                    ),
                    const SizedBox(width: Spacing.md),
                    Text(
                      'Run multiple agents',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.sm,
                      ),
                    ),
                  ],
                ),
                if (_multiMode) ...[
                  const SizedBox(height: Spacing.md),
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
                          vertical: Spacing.sm),
                      children: configs.map((c) {
                        final selected =
                            _selectedConfigs.contains(c.id);
                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedConfigs.remove(c.id);
                              } else {
                                _selectedConfigs.add(c.id);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.lg,
                              vertical: Spacing.sm,
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
                                  c.name,
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: FontSizes.sm,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal: Spacing.md,
                                    vertical: Spacing.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tokens.bgLighter,
                                    borderRadius:
                                        BorderRadius.circular(
                                            Radii.sm),
                                  ),
                                  child: Text(
                                    c.model,
                                    style: TextStyle(
                                      color: tokens.textMuted,
                                      fontSize: FontSizes.xxs,
                                      fontFamily: 'JetBrains Mono',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.lg),
              ],

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
                  ElevatedButton.icon(
                    onPressed: _run,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(_multiMode &&
                            _selectedConfigs.length > 1
                        ? 'Run ${_selectedConfigs.length} Agents'
                        : 'Run'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showAgentRunDialog(
  BuildContext context, {
  required AgentConfigModel config,
}) {
  return showDialog(
    context: context,
    builder: (_) => AgentRunDialog(config: config),
  );
}
