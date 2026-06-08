import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/command_run.dart';
import '../../models/context_pack.dart';
import '../../models/project_profile.dart';
import '../../models/reviewed_edit.dart';
import '../../models/suggested_learning.dart';
import '../../models/work_item.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/chat_provider.dart';
import '../../state/command_run_provider.dart';
import '../../state/context_pack_provider.dart';
import '../../state/layout_provider.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/project_profile_provider.dart';
import '../../state/suggested_learning_provider.dart';
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
    final agentWorkspace = ref.watch(agentWorkspaceProvider);
    final workItem = ref.watch(workItemProvider);
    final contextPack = ref.watch(contextPackProvider);
    final patchProposal = ref.watch(patchProposalProvider);
    final commandRuns = ref.watch(commandRunProvider);
    final workHistory = ref.watch(workItemHistoryProvider);
    final learningSuggestions = ref.watch(suggestedLearningProvider).pending;

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
          _AgentWorkspaceCard(
            workspace: agentWorkspace,
            onStart: _startParallelTask,
          ),
          const SizedBox(height: Spacing.lg),
          _ProjectFacts(profile: profile),
          const SizedBox(height: Spacing.lg),
          if (contextPack != null) ...[
            _ContextPackCard(pack: contextPack),
            const SizedBox(height: Spacing.lg),
          ],
          if (patchProposal.active != null) ...[
            _PatchProposalCard(patchSet: patchProposal.active!),
            const SizedBox(height: Spacing.lg),
          ],
          if (commandRuns.isNotEmpty) ...[
            _CommandRunsCard(commandRuns: commandRuns.values.toList()),
            const SizedBox(height: Spacing.lg),
          ],
          if (learningSuggestions.isNotEmpty) ...[
            _LearningSuggestionsCard(suggestions: learningSuggestions),
            const SizedBox(height: Spacing.lg),
          ],
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
          if (workHistory.items.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            _WorkItemHistoryCard(items: workHistory.items),
          ],
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

  void _startParallelTask({
    AgentTaskProfile profile = AgentTaskProfile.investigate,
  }) {
    final text = _promptController.text.trim();
    final goal = text.isEmpty
        ? 'Investigate this project and propose the safest next coding step.'
        : text;
    ref
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: goal, profile: profile);
    if (text.isNotEmpty) _promptController.clear();
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

class _AgentWorkspaceCard extends ConsumerWidget {
  final AgentWorkspaceState workspace;
  final void Function({AgentTaskProfile profile}) onStart;

  const _AgentWorkspaceCard({required this.workspace, required this.onStart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final tasks = workspace.activeTasks.isEmpty
        ? workspace.recentTasks.take(3).toList()
        : workspace.activeTasks;
    return CircuitDisclosureRow(
      icon: Icons.supervised_user_circle_outlined,
      title: 'Agent Workspace',
      subtitle: workspace.activeTasks.isEmpty
          ? 'No active supervised tasks'
          : '${workspace.activeTasks.length} active',
      initiallyExpanded: true,
      children: [
        if (workspace.message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _Notice(text: workspace.message!, color: tokens.accent),
          ),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: Text(
              'Start supervised tasks to investigate, plan, patch, verify, or prepare a handoff in parallel.',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                height: 1.35,
              ),
            ),
          )
        else
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: _AgentTaskRow(task: task),
            ),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            FilledButton.icon(
              onPressed: () => onStart(profile: AgentTaskProfile.investigate),
              icon: const Icon(Icons.play_arrow_outlined, size: 16),
              label: const Text('Start Parallel Task'),
            ),
            OutlinedButton.icon(
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text: ref
                      .read(agentWorkspaceProvider.notifier)
                      .compareProposals(),
                ),
              ),
              icon: const Icon(Icons.compare_arrows, size: 16),
              label: const Text('Compare'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AgentTaskRow extends ConsumerWidget {
  final AgentTask task;

  const _AgentTaskRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final spec = AgentTaskProfileSpec.forProfile(task.profile);
    final color = switch (task.status) {
      AgentTaskStatus.completed => tokens.success,
      AgentTaskStatus.failed => tokens.error,
      AgentTaskStatus.cancelled => tokens.textMuted,
      AgentTaskStatus.waitingForApproval => tokens.warning,
      AgentTaskStatus.queued || AgentTaskStatus.running => tokens.accent,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () =>
          ref.read(agentWorkspaceProvider.notifier).selectTask(task.id),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: tokens.surfaceInset,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: tokens.outlineSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    task.mascotAlias.characters.first,
                    style: TextStyle(
                      color: color,
                      fontSize: FontSizes.xs,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    '${task.mascotAlias} · ${spec.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                CircuitStatusChip(
                  icon: _taskStatusIcon(task.status),
                  label: task.status.name,
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              task.goal,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                height: 1.3,
              ),
            ),
            if (task.artifacts.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (final artifact in task.artifacts.take(4))
                    CircuitStatusChip(
                      icon: _artifactIcon(artifact.type),
                      label: artifact.title,
                    ),
                ],
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                _SmallTextButton(
                  icon: Icons.copy,
                  label: 'Diagnostics',
                  onTap: () => Clipboard.setData(
                    ClipboardData(
                      text: ref
                          .read(agentWorkspaceProvider.notifier)
                          .diagnosticsFor(task.id),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                if (task.status == AgentTaskStatus.running ||
                    task.status == AgentTaskStatus.queued ||
                    task.status == AgentTaskStatus.waitingForApproval)
                  _SmallTextButton(
                    icon: Icons.stop_circle_outlined,
                    label: 'Cancel',
                    onTap: () => ref
                        .read(agentWorkspaceProvider.notifier)
                        .cancelTask(task.id),
                  ),
              ],
            ),
          ],
        ),
      ),
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

class _ContextPackCard extends ConsumerWidget {
  final ContextPack pack;

  const _ContextPackCard({required this.pack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return CircuitDisclosureRow(
      icon: Icons.dataset_linked_outlined,
      title: 'Context Pack',
      subtitle:
          '${pack.visibleItems.length} items · ~${pack.estimatedTokens} tokens',
      initiallyExpanded: true,
      children: [
        for (final item in pack.allItems)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: pack.removedItemIds.contains(item.id)
                    ? tokens.surfaceBase
                    : tokens.surfaceInset,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: tokens.outlineSoft),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _contextIcon(item.type),
                    color: tokens.textMuted,
                    size: 15,
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FontSizes.sm,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          item.detail,
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
                  if (item.removable)
                    CircuitIconButton(
                      icon: pack.removedItemIds.contains(item.id)
                          ? Icons.undo
                          : Icons.close,
                      tooltip: pack.removedItemIds.contains(item.id)
                          ? 'Restore context item'
                          : 'Remove context item',
                      onPressed: () {
                        final notifier = ref.read(contextPackProvider.notifier);
                        if (pack.removedItemIds.contains(item.id)) {
                          notifier.restoreItem(item.id);
                        } else {
                          notifier.removeItem(item.id);
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PatchProposalCard extends ConsumerWidget {
  final ProposedPatchSet patchSet;

  const _PatchProposalCard({required this.patchSet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final isApplying = ref.watch(patchProposalProvider).isApplying;
    return CircuitDisclosureRow(
      icon: Icons.rate_review_outlined,
      title: 'Patch Review',
      subtitle: '${patchSet.fileCount} files · ${patchSet.approvalStatus.name}',
      initiallyExpanded: true,
      children: [
        for (final edit in patchSet.edits)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _PatchFileRow(edit: edit),
          ),
        if (patchSet.conflictMessage != null)
          _Notice(text: patchSet.conflictMessage!, color: tokens.error),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            FilledButton.icon(
              onPressed: isApplying
                  ? null
                  : () => unawaited(
                      ref.read(patchProposalProvider.notifier).applyActive(),
                    ),
              icon: const Icon(Icons.check, size: 16),
              label: Text(isApplying ? 'Applying' : 'Approve'),
            ),
            OutlinedButton.icon(
              onPressed: isApplying
                  ? null
                  : () =>
                        ref.read(patchProposalProvider.notifier).rejectActive(),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Reject'),
            ),
            OutlinedButton.icon(
              onPressed: isApplying
                  ? null
                  : () => ref
                        .read(patchProposalProvider.notifier)
                        .requestRevision(
                          PatchProposalRevisionRequest(
                            patchSetId: patchSet.id,
                            prompt: 'Revise the patch based on user feedback.',
                          ),
                        ),
              icon: const Icon(Icons.edit_note, size: 16),
              label: const Text('Revise'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PatchFileRow extends ConsumerWidget {
  final ProposedFileEdit edit;

  const _PatchFileRow({required this.edit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final additions = edit.after?.split('\n').length ?? 0;
    final deletions = edit.before?.split('\n').length ?? 0;
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceInset,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.outlineSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: tokens.textMuted, size: 15),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              edit.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.sm,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '+$additions / -$deletions',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xxs,
              fontFamily: EditorDefaults.fallbackFontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandRunsCard extends ConsumerWidget {
  final List<CommandRun> commandRuns;

  const _CommandRunsCard({required this.commandRuns});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = commandRuns
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return CircuitDisclosureRow(
      icon: Icons.terminal_outlined,
      title: 'Command Output',
      subtitle: '${runs.length} runs',
      children: [
        for (final run in runs.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _CommandRunRow(run: run),
          ),
      ],
    );
  }
}

class _CommandRunRow extends ConsumerWidget {
  final CommandRun run;

  const _CommandRunRow({required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = switch (run.status) {
      CommandRunStatus.succeeded => tokens.success,
      CommandRunStatus.failed ||
      CommandRunStatus.timedOut ||
      CommandRunStatus.blocked => tokens.error,
      CommandRunStatus.cancelled => tokens.textMuted,
      CommandRunStatus.queued || CommandRunStatus.running => tokens.warning,
    };
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceInset,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, color: color, size: 8),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  run.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.xs,
                    fontFamily: EditorDefaults.fallbackFontFamily,
                  ),
                ),
              ),
              CircuitIconButton(
                icon: Icons.copy,
                tooltip: 'Copy command output',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: run.combinedOutput)),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            run.combinedOutput,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              fontFamily: EditorDefaults.fallbackFontFamily,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _LearningSuggestionsCard extends ConsumerWidget {
  final List<SuggestedLearning> suggestions;

  const _LearningSuggestionsCard({required this.suggestions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CircuitDisclosureRow(
      icon: Icons.lightbulb_outline,
      title: 'Suggested Learnings',
      subtitle: '${suggestions.length} pending',
      initiallyExpanded: true,
      children: [
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _LearningSuggestionRow(suggestion: suggestion),
          ),
      ],
    );
  }
}

class _LearningSuggestionRow extends ConsumerWidget {
  final SuggestedLearning suggestion;

  const _LearningSuggestionRow({required this.suggestion});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                suggestion.type == SuggestedLearningType.memory
                    ? Icons.psychology_alt_outlined
                    : Icons.rule_outlined,
                color: tokens.textMuted,
                size: 15,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  suggestion.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            suggestion.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              height: 1.25,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => unawaited(
                  ref
                      .read(suggestedLearningProvider.notifier)
                      .approve(suggestion.id),
                ),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(suggestedLearningProvider.notifier)
                    .reject(suggestion.id),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkItemHistoryCard extends ConsumerWidget {
  final List<WorkItem> items;

  const _WorkItemHistoryCard({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CircuitDisclosureRow(
      icon: Icons.history,
      title: 'Recent Work',
      subtitle: '${items.length} saved',
      children: [
        for (final item in items.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _MiniRunRow(label: item.prompt, status: item.status.name),
          ),
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

class _SmallTextButton extends ConsumerWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SmallTextButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        decoration: BoxDecoration(
          color: tokens.surfaceHover,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: tokens.outlineSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: tokens.textSecondary, size: 12),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xxs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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

IconData _contextIcon(ContextPackItemType type) {
  return switch (type) {
    ContextPackItemType.projectProfile => Icons.schema_outlined,
    ContextPackItemType.activeFile => Icons.description_outlined,
    ContextPackItemType.selection => Icons.highlight_alt_outlined,
    ContextPackItemType.mentionedFile => Icons.attach_file,
    ContextPackItemType.gitDiff => Icons.difference_outlined,
    ContextPackItemType.diagnostics => Icons.bug_report_outlined,
    ContextPackItemType.terminal => Icons.terminal_outlined,
    ContextPackItemType.instruction => Icons.menu_book_outlined,
    ContextPackItemType.rule => Icons.rule_outlined,
    ContextPackItemType.memory => Icons.psychology_alt_outlined,
  };
}

IconData _taskStatusIcon(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.queued => Icons.pending_outlined,
    AgentTaskStatus.running => Icons.play_circle_outline,
    AgentTaskStatus.waitingForApproval => Icons.rate_review_outlined,
    AgentTaskStatus.completed => Icons.check_circle_outline,
    AgentTaskStatus.failed => Icons.error_outline,
    AgentTaskStatus.cancelled => Icons.cancel_outlined,
  };
}

IconData _artifactIcon(AgentTaskArtifactType type) {
  return switch (type) {
    AgentTaskArtifactType.contextPack => Icons.dataset_linked_outlined,
    AgentTaskArtifactType.patchProposal => Icons.rate_review_outlined,
    AgentTaskArtifactType.commandRun => Icons.terminal_outlined,
    AgentTaskArtifactType.checkpoint => Icons.restore_outlined,
    AgentTaskArtifactType.verification => Icons.playlist_add_check_outlined,
    AgentTaskArtifactType.diagnostic => Icons.fact_check_outlined,
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
