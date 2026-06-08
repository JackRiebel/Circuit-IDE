import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/project_profile.dart';
import '../../models/work_item.dart';
import '../../state/chat_provider.dart';
import '../../state/layout_provider.dart';
import '../../state/project_profile_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/work_item_provider.dart';
import '../../theme/theme_tokens.dart';
import '../common/circuit_primitives.dart';

class ProjectCockpitPanel extends ConsumerStatefulWidget {
  const ProjectCockpitPanel({super.key});

  @override
  ConsumerState<ProjectCockpitPanel> createState() =>
      _ProjectCockpitPanelState();
}

class _ProjectCockpitPanelState extends ConsumerState<ProjectCockpitPanel> {
  final _promptController = TextEditingController();

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final profile = ref.watch(projectProfileProvider);
    final workItem = ref.watch(workItemProvider);

    if (!profile.hasWorkspace) {
      return _CockpitCard(
        child: _EmptyCockpit(
          onRefresh: () =>
              unawaited(ref.read(projectProfileProvider.notifier).refresh()),
        ),
      );
    }

    return _CockpitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(profile: profile),
          const SizedBox(height: Spacing.lg),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              CircuitStatusChip(
                icon: _readinessIcon(profile.readiness),
                label: _readinessLabel(profile.readiness),
                color: _readinessColor(tokens, profile.readiness),
              ),
              if (profile.gitBranch != null)
                CircuitStatusChip(
                  icon: Icons.account_tree_outlined,
                  label: profile.gitBranch!,
                ),
              CircuitStatusChip(
                icon: Icons.edit_outlined,
                label: '${profile.changedFiles} changes',
                color: profile.changedFiles > 0 ? tokens.warning : null,
              ),
            ],
          ),
          if (profile.error != null) ...[
            const SizedBox(height: Spacing.lg),
            _Notice(text: profile.error!, color: tokens.error),
          ],
          const SizedBox(height: Spacing.xl),
          _Recommendations(
            profile: profile,
            onRun: (recommendation) => _runRecommendation(recommendation),
          ),
          const SizedBox(height: Spacing.lg),
          _ProjectFacts(profile: profile),
          const SizedBox(height: Spacing.lg),
          _CommandList(profile: profile),
          const SizedBox(height: Spacing.lg),
          _WorkItemCard(
            controller: _promptController,
            item: workItem,
            onStart: _startWorkItem,
            onSend: () =>
                unawaited(ref.read(workItemProvider.notifier).sendToChat()),
            onVerify: () => unawaited(
              ref.read(workItemProvider.notifier).runVerification(),
            ),
            onCopy: _copyHandoff,
            onClear: () => ref.read(workItemProvider.notifier).clear(),
          ),
        ],
      ),
    );
  }

  void _startWorkItem() {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;
    ref.read(workItemProvider.notifier).start(text);
    _promptController.clear();
  }

  void _runRecommendation(ProjectRecommendation recommendation) {
    switch (recommendation.kind) {
      case ProjectRecommendationKind.runChecks:
        ref.read(workItemProvider.notifier).start('Run recommended checks');
        unawaited(ref.read(workItemProvider.notifier).runVerification());
        break;
      case ProjectRecommendationKind.explainProject:
        ref.read(chatPanelVisibleProvider.notifier).set(true);
        unawaited(
          ref
              .read(chatProvider.notifier)
              .sendMessage(
                'Explain this project using the project profile and visible context. '
                'Cover stack, entrypoints, architecture, and safest next steps.',
              ),
        );
        break;
      case ProjectRecommendationKind.summarizeChanges:
        ref.read(chatPanelVisibleProvider.notifier).set(true);
        unawaited(
          ref
              .read(chatProvider.notifier)
              .sendMessage(
                'Summarize the current working tree changes as a clean handoff. '
                'Include files changed, risks, and verification to run.',
              ),
        );
        break;
      case ProjectRecommendationKind.startWork:
        FocusScope.of(context).nextFocus();
        break;
    }
  }

  void _copyHandoff() {
    Clipboard.setData(
      ClipboardData(text: ref.read(workItemProvider.notifier).handoffSummary()),
    );
  }
}

class _CockpitCard extends ConsumerWidget {
  final Widget child;

  const _CockpitCard({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.surfacePanel,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: tokens.outlineSoft),
      ),
      child: child,
    );
  }
}

class _EmptyCockpit extends ConsumerWidget {
  final VoidCallback onRefresh;

  const _EmptyCockpit({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.space_dashboard_outlined,
              color: tokens.accent,
              size: 18,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                'Project Cockpit',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.lg,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        Text(
          'Open a folder to build a project profile with stack, checks, map status, and guided work.',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.sm,
            height: 1.35,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Refresh'),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  final ProjectProfile profile;

  const _Header({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final rootName = p.basename(profile.rootPath ?? 'Project');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tokens.surfacePressed,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Icon(Icons.space_dashboard_outlined, color: tokens.accent),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rootName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.lg,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _stackLabel(profile),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        CircuitIconButton(
          icon: Icons.refresh,
          tooltip: 'Refresh project profile',
          onPressed: () =>
              unawaited(ref.read(projectProfileProvider.notifier).refresh()),
        ),
      ],
    );
  }
}

class _Recommendations extends ConsumerWidget {
  final ProjectProfile profile;
  final ValueChanged<ProjectRecommendation> onRun;

  const _Recommendations({required this.profile, required this.onRun});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final recommendations = profile.recommendations.take(3).toList();
    if (recommendations.isEmpty) return const SizedBox.shrink();
    return CircuitDisclosureRow(
      icon: Icons.tips_and_updates_outlined,
      title: 'Next Actions',
      subtitle: '${recommendations.length} recommended',
      initiallyExpanded: true,
      children: [
        for (final recommendation in recommendations)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: InkWell(
              onTap: () => onRun(recommendation),
              borderRadius: BorderRadius.circular(Radii.md),
              child: Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: tokens.surfaceInset,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: tokens.outlineSoft),
                ),
                child: Row(
                  children: [
                    Icon(
                      _recommendationIcon(recommendation.kind),
                      color: tokens.accent,
                      size: 16,
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recommendation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FontSizes.sm,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            recommendation.description,
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
                    Icon(
                      Icons.arrow_forward_ios,
                      color: tokens.textMuted,
                      size: 12,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProjectFacts extends ConsumerWidget {
  final ProjectProfile profile;

  const _ProjectFacts({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final enabledFeatures = profile.detectedFeatures.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .take(6)
        .toList();
    return CircuitDisclosureRow(
      icon: Icons.schema_outlined,
      title: 'Project Profile',
      subtitle: '${profile.entrypoints.length} entrypoints',
      initiallyExpanded: true,
      children: [
        _FactRow(label: 'Stack', value: _stackLabel(profile)),
        _FactRow(
          label: 'Entrypoints',
          value: profile.entrypoints.isEmpty
              ? 'Not detected yet'
              : profile.entrypoints.join(', '),
        ),
        _FactRow(
          label: 'Features',
          value: enabledFeatures.isEmpty
              ? 'No framework signals yet'
              : enabledFeatures.join(', '),
        ),
        if (profile.refreshedAt != null)
          _FactRow(label: 'Refreshed', value: _timeLabel(profile.refreshedAt!)),
        if (profile.recentRuns.isNotEmpty) ...[
          const SizedBox(height: Spacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Recent Runs',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          for (final run in profile.recentRuns.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: _MiniRunRow(
                label: run.title ?? run.kind.name,
                status: run.status.name,
              ),
            ),
        ],
      ],
    );
  }
}

class _CommandList extends ConsumerWidget {
  final ProjectProfile profile;

  const _CommandList({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = profile.commands
        .where((command) => command.enabled)
        .take(4);
    if (commands.isEmpty) return const SizedBox.shrink();
    return CircuitDisclosureRow(
      icon: Icons.playlist_add_check_outlined,
      title: 'Recommended Checks',
      subtitle: '${commands.length} ready',
      children: [
        for (final command in commands)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _CommandRow(command: command),
          ),
      ],
    );
  }
}

class _CommandRow extends ConsumerWidget {
  final ProjectCommand command;

  const _CommandRow({required this.command});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceInset,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.outlineSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal, color: tokens.textMuted, size: 15),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  command.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    fontFamily: EditorDefaults.fallbackFontFamily,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkItemCard extends ConsumerWidget {
  final TextEditingController controller;
  final WorkItem? item;
  final VoidCallback onStart;
  final VoidCallback onSend;
  final VoidCallback onVerify;
  final VoidCallback onCopy;
  final VoidCallback onClear;

  const _WorkItemCard({
    required this.controller,
    required this.item,
    required this.onStart,
    required this.onSend,
    required this.onVerify,
    required this.onCopy,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return CircuitDisclosureRow(
      icon: Icons.task_alt_outlined,
      title: 'Guided Work Item',
      subtitle: item == null ? 'Ready to start' : item!.status.name,
      initiallyExpanded: true,
      children: [
        if (item == null) ...[
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(color: tokens.textPrimary, fontSize: FontSizes.sm),
            decoration: InputDecoration(
              hintText: 'Describe the change or investigation...',
              hintStyle: TextStyle(color: tokens.textMuted),
            ),
            onSubmitted: (_) => onStart(),
          ),
          const SizedBox(height: Spacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.add_task, size: 16),
              label: const Text('Start'),
            ),
          ),
        ] else ...[
          _WorkItemSummary(item: item!),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: _canSend(item!) ? onSend : null,
                icon: const Icon(Icons.send_outlined, size: 16),
                label: const Text('Send'),
              ),
              OutlinedButton.icon(
                onPressed: _canVerify(item!) ? onVerify : null,
                icon: const Icon(Icons.playlist_add_check, size: 16),
                label: const Text('Checks'),
              ),
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Handoff'),
              ),
              IconButton(
                tooltip: 'Clear work item',
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ],
      ],
    );
  }

  bool _canSend(WorkItem item) {
    return item.status == WorkItemStatus.ready ||
        item.status == WorkItemStatus.failed;
  }

  bool _canVerify(WorkItem item) {
    return item.verificationCommands.any((command) => command.enabled) &&
        item.status != WorkItemStatus.running &&
        item.status != WorkItemStatus.verifying;
  }
}

class _WorkItemSummary extends ConsumerWidget {
  final WorkItem item;

  const _WorkItemSummary({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.prompt,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: FontSizes.sm,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: Spacing.md),
        for (final step in item.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _StepRow(step: step),
          ),
        if (item.verificationResults.isNotEmpty) ...[
          const SizedBox(height: Spacing.sm),
          for (final result in item.verificationResults)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: _VerificationRow(result: result),
            ),
        ],
      ],
    );
  }
}

class _StepRow extends ConsumerWidget {
  final WorkItemStep step;

  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = step.error != null
        ? tokens.error
        : step.completed
        ? tokens.success
        : step.running
        ? tokens.warning
        : tokens.textMuted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          step.completed
              ? Icons.check_circle
              : step.running
              ? Icons.timelapse
              : Icons.radio_button_unchecked,
          color: color,
          size: 15,
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                step.error ?? step.result ?? step.detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerificationRow extends ConsumerWidget {
  final VerificationResultSummary result;

  const _VerificationRow({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return _Notice(
      text:
          '${result.command}: ${result.statusLabel} (${result.duration.inSeconds}s)',
      color: result.passed ? tokens.success : tokens.error,
    );
  }
}

class _FactRow extends ConsumerWidget {
  final String label;
  final String value;

  const _FactRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniRunRow extends ConsumerWidget {
  final String label;
  final String status;

  const _MiniRunRow({required this.label, required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Row(
      children: [
        Icon(Icons.timeline_outlined, color: tokens.textMuted, size: 14),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
            ),
          ),
        ),
        Text(
          status,
          style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xxs),
        ),
      ],
    );
  }
}

class _Notice extends ConsumerWidget {
  final String text;
  final Color color;

  const _Notice({required this.text, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: FontSizes.xs,
          height: 1.3,
        ),
      ),
    );
  }
}

String _stackLabel(ProjectProfile profile) {
  if (profile.projectTypes.isEmpty) return profile.primaryType.label;
  return profile.projectTypes.map((type) => type.label).join(' + ');
}

String _readinessLabel(ProjectReadiness readiness) {
  return switch (readiness) {
    ProjectReadiness.noWorkspace => 'No workspace',
    ProjectReadiness.loading => 'Profiling',
    ProjectReadiness.ready => 'Ready',
    ProjectReadiness.degraded => 'Degraded',
    ProjectReadiness.error => 'Needs attention',
  };
}

IconData _readinessIcon(ProjectReadiness readiness) {
  return switch (readiness) {
    ProjectReadiness.noWorkspace => Icons.folder_off_outlined,
    ProjectReadiness.loading => Icons.timelapse,
    ProjectReadiness.ready => Icons.check_circle_outline,
    ProjectReadiness.degraded => Icons.info_outline,
    ProjectReadiness.error => Icons.error_outline,
  };
}

Color _readinessColor(ThemeTokens tokens, ProjectReadiness readiness) {
  return switch (readiness) {
    ProjectReadiness.ready => tokens.success,
    ProjectReadiness.loading => tokens.warning,
    ProjectReadiness.degraded => tokens.warning,
    ProjectReadiness.error => tokens.error,
    ProjectReadiness.noWorkspace => tokens.textMuted,
  };
}

IconData _recommendationIcon(ProjectRecommendationKind kind) {
  return switch (kind) {
    ProjectRecommendationKind.runChecks => Icons.playlist_add_check_outlined,
    ProjectRecommendationKind.explainProject => Icons.psychology_outlined,
    ProjectRecommendationKind.summarizeChanges => Icons.summarize_outlined,
    ProjectRecommendationKind.startWork => Icons.add_task_outlined,
  };
}

String _timeLabel(DateTime value) {
  final now = DateTime.now();
  final delta = now.difference(value);
  if (delta.inMinutes < 1) return 'Just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}
