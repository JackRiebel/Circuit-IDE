import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'studio_message_sender.dart';
import 'studio_task_plan_primitives.dart';
import 'studio_task_plan_progress_chip.dart';

class StudioPlanSummaryCard extends ConsumerStatefulWidget {
  final ProposedPatchSet patch;

  const StudioPlanSummaryCard({super.key, required this.patch});

  @override
  ConsumerState<StudioPlanSummaryCard> createState() => _PlanSummaryCardState();
}

class _PlanSummaryCardState extends ConsumerState<StudioPlanSummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final patch = widget.patch;
    final targetProgress = ref
        .watch(
          studioThreadProvider.select(
            (state) =>
                _PlanProgressSnapshot.forPatch(state.selectedThread, patch),
          ),
        )
        .targets;
    final accepted = patch.approvalStatus == PatchApprovalStatus.approved;
    final markdown = (patch.planMarkdown ?? patch.comparisonSummary ?? '')
        .trim();
    final title = _planCardTitle(patch, markdown);
    final appliedTargetCount = targetProgress
        .where((target) => target.state == PlanTargetProgressState.applied)
        .length;
    final terminalTargetCount = targetProgress
        .where(
          (target) =>
              target.state == PlanTargetProgressState.applied ||
              target.state == PlanTargetProgressState.skipped,
        )
        .length;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: StudioLayoutContract.reviewWidth,
        ),
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: tokens.studioCard.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Plan',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  StudioPlanIconAction(
                    icon: StudioIcons.contentCopyOutlined,
                    tooltip: 'Copy plan',
                    onPressed: markdown.isEmpty
                        ? null
                        : () =>
                              Clipboard.setData(ClipboardData(text: markdown)),
                  ),
                  StudioPlanIconAction(
                    icon: StudioIcons.thumbUpAltOutlined,
                    tooltip: 'Useful',
                    onPressed: () {},
                  ),
                  StudioPlanIconAction(
                    icon: StudioIcons.thumbDownAltOutlined,
                    tooltip: 'Not useful',
                    onPressed: () {},
                  ),
                  StudioPlanIconAction(
                    icon: _expanded
                        ? StudioIcons.keyboardArrowUp
                        : StudioIcons.keyboardArrowDown,
                    tooltip: _expanded ? 'Collapse plan' : 'Expand plan',
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                title,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.xxl,
                  height: 1.12,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (targetProgress.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      terminalTargetCount == targetProgress.length
                          ? 'Plan progress: all ${targetProgress.length} targets complete'
                          : 'Plan progress: $appliedTargetCount/${targetProgress.length} targets applied',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final target in targetProgress.take(8))
                          StudioPlanProgressTargetChip(target: target),
                        if (targetProgress.length > 8)
                          StudioPlanMoreChip(count: targetProgress.length - 8),
                      ],
                    ),
                  ],
                ),
              )
            else if (patch.effectivePlannedTargets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final target in patch.effectivePlannedTargets.take(8))
                      StudioPlanTargetChip(target: target),
                    if (patch.effectivePlannedTargets.length > 8)
                      StudioPlanMoreChip(
                        count: patch.effectivePlannedTargets.length - 8,
                      ),
                  ],
                ),
              ),
            if (markdown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: StudioPlanCardBody(
                  markdown: markdown,
                  expanded: _expanded,
                ),
              ),
            if (!_expanded && markdown.isNotEmpty)
              Transform.translate(
                offset: const Offset(0, -2),
                child: Center(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      backgroundColor: tokens.textPrimary,
                      foregroundColor: tokens.bgDark,
                      textStyle: const TextStyle(
                        fontSize: FontSizes.xs,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () => setState(() => _expanded = true),
                    child: const Text('Expand plan'),
                  ),
                ),
              )
            else if (_expanded && markdown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    style: _planTextActionStyle(tokens),
                    onPressed: () => setState(() => _expanded = false),
                    child: const Text('Collapse plan'),
                  ),
                ),
              ),
            Container(
              margin: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                color: tokens.surfacePanel.withValues(alpha: 0.28),
                border: Border(
                  top: BorderSide(
                    color: tokens.studioDivider.withValues(alpha: 0.42),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: accepted
                  ? Row(
                      children: [
                        Icon(
                          StudioIcons.checkCircleOutline,
                          color: tokens.success.withValues(alpha: 0.92),
                          size: 16,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Plan accepted. Implementation started.',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: FontSizes.sm,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          style: _planTextActionStyle(tokens),
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          child: Text(_expanded ? 'Hide plan' : 'View plan'),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Implement this plan?',
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FontSizes.sm,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        StudioPlanChoiceButton(
                          index: '1',
                          label: 'Yes, implement this plan',
                          enabled: true,
                          onPressed: () => _implementPlan(ref),
                        ),
                        const SizedBox(height: 6),
                        StudioPlanChoiceButton(
                          index: null,
                          icon: StudioIcons.editOutlined,
                          label: 'No, and tell Circuit what to do differently',
                          enabled: true,
                          onPressed: () => _revisePlan(ref),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              style: _planTextActionStyle(tokens),
                              onPressed: () => ref
                                  .read(patchProposalProvider.notifier)
                                  .reject(widget.patch.id),
                              child: const Text('Dismiss'),
                            ),
                            const SizedBox(width: Spacing.sm),
                            FilledButton(
                              style: _planPrimaryActionStyle(tokens),
                              onPressed: () => _implementPlan(ref),
                              child: const Text('Submit'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _implementPlan(WidgetRef ref) {
    unawaited(
      implementPlanFromStudio(
        ref,
        widget.patch,
        taskId: widget.patch.agentTaskId,
        finishTask: widget.patch.agentTaskId != null,
      ),
    );
  }

  void _revisePlan(WidgetRef ref) {
    final shellNotifier = ref.read(studioShellProvider.notifier);
    ref
        .read(patchProposalProvider.notifier)
        .requestRevision(
          PatchProposalRevisionRequest(
            patchSetId: widget.patch.id,
            prompt: 'Revise this plan. Change: ',
          ),
        );
    shellNotifier.setPlanModeEnabled(true);
    shellNotifier.setComposerText('Revise this plan. Change: ');
  }
}

List<PlanTargetProgress> _planProgressForPatch(
  StudioThread? thread,
  ProposedPatchSet patch,
) {
  if (thread == null) return const [];
  final matchingTurns = thread.turns.where((turn) {
    final context = turn.acceptedPlanContext;
    return context?.patchSetId == patch.id &&
        turn.planTargetProgress.isNotEmpty;
  }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  if (matchingTurns.isEmpty) return const [];
  return matchingTurns.first.planTargetProgress;
}

class _PlanProgressSnapshot {
  final List<PlanTargetProgress> targets;
  final int _fingerprint;

  const _PlanProgressSnapshot(this.targets, this._fingerprint);

  factory _PlanProgressSnapshot.forPatch(
    StudioThread? thread,
    ProposedPatchSet patch,
  ) {
    final targets = _planProgressForPatch(thread, patch);
    return _PlanProgressSnapshot(targets, _planTargetFingerprint(targets));
  }

  @override
  bool operator ==(Object other) {
    return other is _PlanProgressSnapshot && _fingerprint == other._fingerprint;
  }

  @override
  int get hashCode => _fingerprint;
}

int _planTargetFingerprint(List<PlanTargetProgress> targets) {
  return Object.hashAll(
    targets.map(
      (target) =>
          Object.hash(target.path, target.intent, target.state, target.detail),
    ),
  );
}

String _planCardTitle(ProposedPatchSet patch, String markdown) {
  final title = patch.title.trim();
  if (title.isNotEmpty && title.toLowerCase() != 'plan') return title;
  final heading = RegExp(
    r'^\s{0,3}#{1,3}\s+(.+?)\s*$',
    multiLine: true,
  ).firstMatch(markdown)?.group(1);
  if (heading != null && heading.trim().isNotEmpty) {
    return heading.trim();
  }
  return 'Implementation Plan';
}

ButtonStyle _planPrimaryActionStyle(ThemeTokens tokens) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

ButtonStyle _planTextActionStyle(ThemeTokens tokens) {
  return TextButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    visualDensity: VisualDensity.compact,
    foregroundColor: tokens.textSecondary,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}
