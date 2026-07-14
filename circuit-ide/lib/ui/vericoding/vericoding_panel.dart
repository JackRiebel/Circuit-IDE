import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/vericoding_models.dart';
import '../../services/project_detector.dart';
import '../../state/theme_provider.dart';
import '../../state/vericoding_provider.dart';
import '../common/toggle_switch.dart';
import 'check_result_card.dart';
import 'vericode_config_dialog.dart';

class VericodingPanel extends ConsumerWidget {
  const VericodingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final vstate = ref.watch(vericodingProvider);

    if (vstate.isLoading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
      );
    }

    return Column(
      children: [
        // Header bar
        _HeaderBar(vstate: vstate),

        // Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              // Status summary card
              _StatusCard(vstate: vstate),
              const SizedBox(height: Spacing.lg),

              // Detected project info
              if (vstate.detectedProjectType != null)
                _DetectedProjectBadge(
                  projectType: vstate.detectedProjectType!,
                  features: vstate.detectedFeatures,
                ),
              if (vstate.detectedProjectType != null)
                const SizedBox(height: Spacing.md),

              // Config section — check list with toggles
              _CheckListSection(config: vstate.config),

              // Current run
              if (vstate.currentRun != null) ...[
                const SizedBox(height: Spacing.lg),
                _CurrentRunSection(run: vstate.currentRun!),
              ],

              // History
              if (vstate.history.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                _HistorySection(history: vstate.history),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderBar extends ConsumerWidget {
  final VericodeState vstate;

  const _HeaderBar({required this.vstate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final run = vstate.currentRun;
    final isRunning =
        run != null &&
        (run.status == VericodeRunStatus.runningChecks ||
            run.status == VericodeRunStatus.fixing ||
            run.status == VericodeRunStatus.rerunning ||
            run.status == VericodeRunStatus.analyzingFailures);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // Enabled toggle
          ToggleSwitch(
            value: vstate.config.enabled,
            onChanged: (v) {
              ref
                  .read(vericodingProvider.notifier)
                  .updateConfig(vstate.config.copyWith(enabled: v));
            },
            width: 34,
            height: 18,
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            vstate.config.enabled ? 'Enabled' : 'Disabled',
            style: TextStyle(
              color: vstate.config.enabled
                  ? tokens.textPrimary
                  : tokens.textMuted,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),

          // Run / Cancel button
          if (isRunning)
            _CompactButton(
              icon: Icons.stop_rounded,
              label: 'Cancel',
              color: tokens.error,
              onTap: () => ref.read(vericodingProvider.notifier).cancel(),
            )
          else
            _CompactButton(
              icon: Icons.play_arrow_rounded,
              label: 'Verify',
              color: tokens.success,
              onTap: vstate.config.enabled
                  ? () => ref.read(vericodingProvider.notifier).verify()
                  : null,
            ),

          const SizedBox(width: Spacing.xs),

          // Auto-detect button
          Tooltip(
            message: 'Auto-detect project checks',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () =>
                    ref.read(vericodingProvider.notifier).autoDetectChecks(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.auto_fix_high,
                    size: 15,
                    color: tokens.textMuted,
                  ),
                ),
              ),
            ),
          ),

          // Config gear
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => const VericodeConfigDialog(),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.tune_outlined,
                  size: 15,
                  color: tokens.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactButton extends ConsumerStatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _CompactButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  ConsumerState<_CompactButton> createState() => _CompactButtonState();
}

class _CompactButtonState extends ConsumerState<_CompactButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final enabled = widget.onTap != null;
    final color = enabled ? widget.color : tokens.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _isHovered && enabled
                ? color.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: color.withValues(alpha: enabled ? 0.4 : 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: color),
              const SizedBox(width: 3),
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: FontSizes.xxs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends ConsumerWidget {
  final VericodeState vstate;

  const _StatusCard({required this.vstate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final run = vstate.currentRun;
    final status = run?.status ?? VericodeRunStatus.idle;

    final (label, color, icon) = switch (status) {
      VericodeRunStatus.idle => (
        'Ready',
        tokens.textMuted,
        Icons.circle_outlined,
      ),
      VericodeRunStatus.runningChecks => (
        'Running checks...',
        tokens.warning,
        Icons.sync,
      ),
      VericodeRunStatus.analyzingFailures => (
        'Analyzing failures...',
        tokens.warning,
        Icons.analytics_outlined,
      ),
      VericodeRunStatus.fixing => (
        'AI fixing...',
        tokens.accent,
        Icons.auto_fix_high,
      ),
      VericodeRunStatus.rerunning => (
        'Re-running checks...',
        tokens.warning,
        Icons.refresh,
      ),
      VericodeRunStatus.passed => (
        'All checks passed',
        tokens.success,
        Icons.check_circle,
      ),
      VericodeRunStatus.failed => ('Checks failed', tokens.error, Icons.cancel),
    };

    final isActive =
        status == VericodeRunStatus.runningChecks ||
        status == VericodeRunStatus.fixing ||
        status == VericodeRunStatus.rerunning ||
        status == VericodeRunStatus.analyzingFailures;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          if (isActive)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (run != null && run.attempts.isNotEmpty)
            Text(
              'Attempt ${run.attempts.length}/${run.maxRetries}',
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: FontSizes.xxs,
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckListSection extends ConsumerWidget {
  final VericodeConfig config;

  const _CheckListSection({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            Text(
              '${config.checks.where((c) => c.enabled).length}/${config.checks.length} active',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        ...config.checks.map(
          (check) => _CheckToggleRow(
            check: check,
            onToggle: (enabled) {
              final checks = config.checks.map((c) {
                if (c.id == check.id) return c.copyWith(enabled: enabled);
                return c;
              }).toList();
              ref
                  .read(vericodingProvider.notifier)
                  .updateConfig(config.copyWith(checks: checks));
            },
          ),
        ),
        if (config.checks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.playlist_add_outlined,
                    size: 24,
                    color: tokens.textMuted.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'No checks configured',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'Tap the gear icon to add checks',
                    style: TextStyle(
                      color: tokens.textMuted.withValues(alpha: 0.6),
                      fontSize: FontSizes.xxs,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CheckToggleRow extends ConsumerWidget {
  final VericodeCheck check;
  final ValueChanged<bool> onToggle;

  const _CheckToggleRow({required this.check, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        decoration: BoxDecoration(
          color: check.enabled ? tokens.bgLighter : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          children: [
            ToggleSwitch(
              value: check.enabled,
              onChanged: onToggle,
              width: 30,
              height: 16,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                check.name,
                style: TextStyle(
                  color: check.enabled ? tokens.textPrimary : tokens.textMuted,
                  fontSize: FontSizes.xs,
                ),
              ),
            ),
            Text(
              check.command,
              style: TextStyle(
                color: tokens.textMuted.withValues(alpha: 0.6),
                fontSize: 9,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentRunSection extends ConsumerWidget {
  final VericodeRun run;

  const _CurrentRunSection({required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RESULTS',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xxs,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: Spacing.sm),

        // Results cards
        ...run.currentResults.map((result) => CheckResultCard(result: result)),

        if (run.status == VericodeRunStatus.fixing)
          Container(
            margin: const EdgeInsets.only(top: Spacing.xs),
            padding: const EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: tokens.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  'AI is fixing issues...',
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: FontSizes.xxs,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HistorySection extends ConsumerWidget {
  final List<VericodeRun> history;

  const _HistorySection({required this.history});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HISTORY',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xxs,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        ...history.take(5).map((run) => _HistoryRow(run: run)),
      ],
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  final VericodeRun run;

  const _HistoryRow({required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final passed = run.status == VericodeRunStatus.passed;
    final elapsed = run.completedAt?.difference(run.startedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.cancel,
            size: 12,
            color: passed ? tokens.success : tokens.error,
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            passed ? 'Passed' : 'Failed',
            style: TextStyle(
              color: passed ? tokens.success : tokens.error,
              fontSize: FontSizes.xxs,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (run.attempts.isNotEmpty) ...[
            const SizedBox(width: Spacing.sm),
            Text(
              '${run.attempts.length} attempt${run.attempts.length > 1 ? 's' : ''}',
              style: TextStyle(color: tokens.textMuted, fontSize: 9),
            ),
          ],
          const Spacer(),
          if (elapsed != null)
            Text(
              _formatDuration(elapsed),
              style: TextStyle(color: tokens.textMuted, fontSize: 9),
            ),
          if (run.triggerSource != null && run.triggerSource!.isNotEmpty) ...[
            const SizedBox(width: Spacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: tokens.bgLight,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Text(
                run.triggerSource!,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 9,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}

class _DetectedProjectBadge extends ConsumerWidget {
  final ProjectType projectType;
  final Map<String, bool> features;

  const _DetectedProjectBadge({
    required this.projectType,
    required this.features,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    final enabledFeatures = features.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    return Container(
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: tokens.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconForProjectType(projectType),
                size: 13,
                color: tokens.accent,
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                'Detected: ${projectType.label}',
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (enabledFeatures.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: enabledFeatures
                  .map(
                    (f) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.bgLighter,
                        borderRadius: BorderRadius.circular(Radii.xs),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 9,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForProjectType(ProjectType type) {
    return switch (type) {
      ProjectType.flutter => Icons.flutter_dash,
      ProjectType.dart => Icons.code,
      ProjectType.node || ProjectType.typescript => Icons.javascript,
      ProjectType.python => Icons.data_object,
      ProjectType.rust => Icons.settings,
      ProjectType.go => Icons.speed,
      ProjectType.java || ProjectType.kotlin => Icons.coffee,
      ProjectType.csharp => Icons.window,
      ProjectType.ruby => Icons.diamond_outlined,
      ProjectType.swift => Icons.apple,
      ProjectType.cpp => Icons.memory,
      ProjectType.unknown => Icons.help_outline,
    };
  }
}
