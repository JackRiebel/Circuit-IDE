import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/vericoding_models.dart';
import '../../services/project_detector.dart';
import '../../state/file_tree_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/vericoding_provider.dart';
import '../common/toggle_switch.dart';

const _uuid = Uuid();

class VericodeConfigDialog extends ConsumerStatefulWidget {
  const VericodeConfigDialog({super.key});

  @override
  ConsumerState<VericodeConfigDialog> createState() =>
      _VericodeConfigDialogState();
}

class _VericodeConfigDialogState extends ConsumerState<VericodeConfigDialog> {
  late VericodeConfig _config;

  @override
  void initState() {
    super.initState();
    _config = ref.read(vericodingProvider).config;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);

    return Dialog(
      backgroundColor: tokens.bgMain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(Spacing.xl),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: tokens.border.withValues(alpha: 0.3)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined, size: 20, color: tokens.accent),
                  const SizedBox(width: Spacing.md),
                  Text(
                    'Vericoding Configuration',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.lg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: tokens.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 16,
                  ),
                ],
              ),
            ),

            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(Spacing.xl),
                children: [
                  // Global toggles
                  _SwitchRow(
                    label: 'Enabled',
                    value: _config.enabled,
                    onChanged: (v) =>
                        setState(() => _config = _config.copyWith(enabled: v)),
                    tokens: tokens,
                  ),
                  const SizedBox(height: Spacing.md),
                  _SwitchRow(
                    label: 'Auto-run after AI edits',
                    value: _config.autoRunAfterEdit,
                    onChanged: (v) => setState(
                        () => _config = _config.copyWith(autoRunAfterEdit: v)),
                    tokens: tokens,
                  ),
                  const SizedBox(height: Spacing.md),

                  // Max retries
                  Row(
                    children: [
                      Text(
                        'Max fix attempts',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: FontSizes.sm,
                        ),
                      ),
                      const Spacer(),
                      DropdownButton<int>(
                        value: _config.maxRetries,
                        dropdownColor: tokens.bgLighter,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: FontSizes.sm,
                        ),
                        underline: const SizedBox.shrink(),
                        items: [1, 2, 3, 5]
                            .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text('$v'),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(
                                () => _config = _config.copyWith(maxRetries: v));
                          }
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: Spacing.xl),
                  Divider(color: tokens.border.withValues(alpha: 0.3)),
                  const SizedBox(height: Spacing.lg),

                  // Checks list
                  Row(
                    children: [
                      Text(
                        'CHECKS',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xxs,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _autoDetect,
                        icon: Icon(Icons.auto_fix_high,
                            size: 14, color: tokens.warning),
                        label: Text(
                          'Auto-detect',
                          style: TextStyle(
                            color: tokens.warning,
                            fontSize: FontSizes.xs,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addCheck,
                        icon: Icon(Icons.add, size: 14, color: tokens.accent),
                        label: Text(
                          'Add Check',
                          style: TextStyle(
                            color: tokens.accent,
                            fontSize: FontSizes.xs,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),

                  ..._config.checks.asMap().entries.map((entry) {
                    final check = entry.value;
                    return _CheckRow(
                      check: check,
                      tokens: tokens,
                      onToggle: (enabled) {
                        final checks = List<VericodeCheck>.from(_config.checks);
                        checks[entry.key] = check.copyWith(enabled: enabled);
                        setState(
                            () => _config = _config.copyWith(checks: checks));
                      },
                      onDelete: () {
                        final checks = List<VericodeCheck>.from(_config.checks)
                          ..removeAt(entry.key);
                        setState(
                            () => _config = _config.copyWith(checks: checks));
                      },
                    );
                  }),
                ],
              ),
            ),

            // Footer buttons
            Container(
              padding: const EdgeInsets.all(Spacing.xl),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: tokens.border.withValues(alpha: 0.3)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                          color: tokens.textMuted, fontSize: FontSizes.sm),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  FilledButton(
                    onPressed: () {
                      ref
                          .read(vericodingProvider.notifier)
                          .updateConfig(_config);
                      Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.accent,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _autoDetect() async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;

    final detector = ProjectDetector(rootPath: rootPath);
    final result = await detector.detect();

    if (result.suggestedChecks.isNotEmpty) {
      setState(() {
        _config = _config.copyWith(checks: result.suggestedChecks);
      });
    }
  }

  void _addCheck() {
    final checks = List<VericodeCheck>.from(_config.checks);
    checks.add(VericodeCheck(
      id: _uuid.v4().substring(0, 8),
      name: 'Custom Check',
      command: 'echo "hello"',
      type: VericodeCheckType.customCommand,
      enabled: true,
      order: checks.length,
    ));
    setState(() => _config = _config.copyWith(checks: checks));
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final dynamic tokens;

  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: FontSizes.sm,
            ),
          ),
          const Spacer(),
          ToggleSwitch(
            value: value,
            onChanged: onChanged,
            width: 36,
            height: 20,
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final VericodeCheck check;
  final dynamic tokens;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _CheckRow({
    required this.check,
    required this.tokens,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.border.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          ToggleSwitch(
            value: check.enabled,
            onChanged: onToggle,
            width: 34,
            height: 18,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.name,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  check.command,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 16, color: tokens.error),
            onPressed: onDelete,
            splashRadius: 14,
          ),
        ],
      ),
    );
  }
}
