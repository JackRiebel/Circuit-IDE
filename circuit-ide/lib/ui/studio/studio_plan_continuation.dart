import '../../models/accepted_plan_context.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';

class StudioPlanContinuationSummary {
  final AcceptedPlanContext acceptedPlan;
  final List<PlanTargetProgress> remainingTargets;
  final int appliedCount;
  final int totalCount;

  const StudioPlanContinuationSummary({
    required this.acceptedPlan,
    required this.remainingTargets,
    required this.appliedCount,
    required this.totalCount,
  });

  String get summaryLabel {
    final remaining = remainingTargets.length;
    return '$remaining ${remaining == 1 ? 'target remains' : 'targets remain'}';
  }
}

StudioPlanContinuationSummary? studioPlanContinuationForPatch({
  required ProposedPatchSet patch,
  required Iterable<StudioThread> threads,
}) {
  if (patch.applyStatus != PatchApplyStatus.applied || patch.runId == null) {
    return null;
  }
  StudioTurn? matchingTurn;
  for (final thread in threads) {
    for (final turn in thread.turns) {
      if (turn.requestId == patch.runId) {
        matchingTurn = turn;
        break;
      }
    }
    if (matchingTurn != null) break;
  }
  final turn = matchingTurn;
  final context = turn?.acceptedPlanContext;
  if (turn == null || context == null || turn.planTargetProgress.isEmpty) {
    return null;
  }
  final contextTargets = context.plannedTargets.isNotEmpty
      ? context.plannedTargets
      : [
          for (final file in context.plannedFiles)
            PlannedFileTarget.fromDisplayString(file),
        ];
  if (contextTargets.isEmpty) return null;
  final remaining = turn.planTargetProgress
      .where(
        (target) =>
            target.state == PlanTargetProgressState.pending ||
            target.state == PlanTargetProgressState.proposed ||
            target.state == PlanTargetProgressState.conflict ||
            target.state == PlanTargetProgressState.blocked,
      )
      .toList(growable: false);
  if (remaining.isEmpty) return null;
  final remainingPaths = {
    for (final target in remaining) _normalizePlanPathForUi(target.path),
  };
  final remainingProgressByPath = {
    for (final target in remaining)
      _normalizePlanPathForUi(target.path): target,
  };
  final remainingTargets = contextTargets
      .where(
        (target) =>
            remainingPaths.contains(_normalizePlanPathForUi(target.path)),
      )
      .toList(growable: false);
  if (remainingTargets.isEmpty) return null;
  final acceptedPlan = context.copyWith(
    patchSetId: '${context.patchSetId}:next-batch',
    summary: [
      if (context.summary.trim().isNotEmpty) context.summary.trim(),
      'Continue the remaining accepted-plan batch only.',
    ].join('\n'),
    markdown: _continuationMarkdown(
      context,
      remainingTargets,
      remainingProgressByPath,
    ),
    plannedTargets: remainingTargets,
    plannedFiles: [for (final target in remainingTargets) target.displayString],
  );
  return StudioPlanContinuationSummary(
    acceptedPlan: acceptedPlan,
    remainingTargets: remaining,
    appliedCount: turn.planTargetProgress
        .where((target) => target.state == PlanTargetProgressState.applied)
        .length,
    totalCount: turn.planTargetProgress.length,
  );
}

StudioPlanContinuationSummary? studioPlanContinuationForTurn(StudioTurn turn) {
  final context = turn.acceptedPlanContext;
  if (context == null || turn.planTargetProgress.isEmpty) return null;
  final appliedCount = turn.planTargetProgress
      .where((target) => target.state == PlanTargetProgressState.applied)
      .length;
  if (appliedCount == 0) return null;
  final remaining = turn.planTargetProgress
      .where(
        (target) =>
            target.state == PlanTargetProgressState.pending ||
            target.state == PlanTargetProgressState.proposed ||
            target.state == PlanTargetProgressState.conflict ||
            target.state == PlanTargetProgressState.blocked,
      )
      .toList(growable: false);
  if (remaining.isEmpty) return null;
  final contextTargets = context.plannedTargets.isNotEmpty
      ? context.plannedTargets
      : [
          for (final file in context.plannedFiles)
            PlannedFileTarget.fromDisplayString(file),
        ];
  if (contextTargets.isEmpty) return null;
  final remainingPaths = {
    for (final target in remaining) _normalizePlanPathForUi(target.path),
  };
  final remainingProgressByPath = {
    for (final target in remaining)
      _normalizePlanPathForUi(target.path): target,
  };
  final remainingTargets = contextTargets
      .where(
        (target) =>
            remainingPaths.contains(_normalizePlanPathForUi(target.path)),
      )
      .toList(growable: false);
  if (remainingTargets.isEmpty) return null;
  final acceptedPlan = context.copyWith(
    patchSetId: '${context.patchSetId}:next-batch',
    summary: [
      if (context.summary.trim().isNotEmpty) context.summary.trim(),
      'Continue the remaining accepted-plan batch only.',
    ].join('\n'),
    markdown: _continuationMarkdown(
      context,
      remainingTargets,
      remainingProgressByPath,
    ),
    plannedTargets: remainingTargets,
    plannedFiles: [for (final target in remainingTargets) target.displayString],
  );
  return StudioPlanContinuationSummary(
    acceptedPlan: acceptedPlan,
    remainingTargets: remaining,
    appliedCount: appliedCount,
    totalCount: turn.planTargetProgress.length,
  );
}

String _normalizePlanPathForUi(String path) {
  return path.trim().replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
}

String _continuationMarkdown(
  AcceptedPlanContext context,
  List<PlannedFileTarget> remainingTargets,
  Map<String, PlanTargetProgress> remainingProgressByPath,
) {
  final title = context.title.trim().isEmpty
      ? 'Accepted Plan Continuation'
      : context.title.trim();
  final lines = <String>[
    '# Continue Accepted Plan',
    '',
    'Source plan: $title',
    '',
    'Only implement the remaining accepted-plan targets below. Do not re-propose or rewrite targets that were already applied.',
    '',
    '## Remaining targets',
    for (final target in remainingTargets)
      '- ${target.contractString}${_continuationTargetNote(target, remainingProgressByPath)}',
  ];
  if (context.verificationRequested) {
    lines.addAll([
      '',
      '## Verification',
      '- Preserve the original verification request for the completed plan. Verification should run later in an approved Verify turn.',
    ]);
  }
  return lines.join('\n');
}

String _continuationTargetNote(
  PlannedFileTarget target,
  Map<String, PlanTargetProgress> remainingProgressByPath,
) {
  final progress =
      remainingProgressByPath[_normalizePlanPathForUi(target.path)];
  if (progress == null) return '';
  final notes = <String>[
    switch (progress.state) {
      PlanTargetProgressState.pending => 'not started',
      PlanTargetProgressState.proposed => 'proposal exists but is not applied',
      PlanTargetProgressState.conflict =>
        'patch conflict needs rebase/revision',
      PlanTargetProgressState.blocked => 'blocked by missing context',
      PlanTargetProgressState.skipped => 'skipped',
      PlanTargetProgressState.applied => 'already applied',
    },
    if (progress.detail?.trim().isNotEmpty == true) progress.detail!.trim(),
  ];
  return ' (${notes.join('; ')})';
}
