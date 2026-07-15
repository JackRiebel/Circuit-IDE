import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reviewed_edit.dart';
import '../models/studio_request_lifecycle.dart';
import '../models/studio_turn.dart';
import '../models/tool_call_info.dart';
import '../models/turn_intent.dart';
import 'patch_proposal_provider.dart';
import 'studio_thread_provider.dart';
import 'studio_turn_provider.dart';

class StudioRequestPatchProposalHandler {
  final Ref _ref;

  const StudioRequestPatchProposalHandler(this._ref);

  void createPatchPlan(StudioRequestLifecycleEntry entry, ToolCallInfo tool) {
    final args = tool.arguments;
    final planMode = entry.intent == TurnIntent.plan;
    final title = args['title'] as String? ?? 'Implementation plan';
    final summary = args['summary'] as String? ?? '';
    final planMarkdown =
        args['plan_markdown'] as String? ??
        args['planMarkdown'] as String? ??
        summary;
    final files = (args['files'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final edits = <ProposedFileEdit>[];
    final plannedFiles = <String>[];
    final plannedTargets = <PlannedFileTarget>[];
    for (final file in files) {
      final path = file['path'] as String?;
      if (path == null || path.trim().isEmpty) continue;
      final intent = file['intent'] as String? ?? '';
      final operation = (file['operation'] as String? ?? 'create')
          .toLowerCase();
      final editType = switch (operation) {
        'delete' => ProposedFileEditType.delete,
        'modify' || 'update' => ProposedFileEditType.modify,
        _ => ProposedFileEditType.create,
      };
      final plannedTarget = PlannedFileTarget(
        path: path,
        intent: intent,
        operation: editType,
      );
      plannedTargets.add(plannedTarget);
      plannedFiles.add(plannedTarget.displayString);
      if (planMode) continue;
      final content = file['content'] as String? ?? file['after'] as String?;
      if (content == null && operation != 'delete') continue;
      edits.add(
        ProposedFileEdit(
          path: path,
          type: editType,
          before: file['before'] as String?,
          after: content,
          unifiedDiff: file['unified_diff'] as String?,
        ),
      );
    }
    final patch = _ref
        .read(patchProposalProvider.notifier)
        .propose(
          title: title,
          edits: edits,
          planMarkdown: planMarkdown,
          plannedFiles: plannedFiles,
          plannedTargets: plannedTargets,
          agentTaskId: entry.taskId,
          runId: entry.requestId,
          comparisonSummary: summary.trim().isEmpty ? planMarkdown : summary,
          verificationRequested:
              _verificationRequestedFor(entry.requestId) ||
              _proposalRequestsVerification(args, planMarkdown),
          verificationSuggestions: _proposalVerificationSteps(args),
        );
    _ref
        .read(studioTurnProvider.notifier)
        .replaceAssistantDraft(entry.requestId, '');
    _ref
        .read(studioTurnProvider.notifier)
        .markProgress(
          entry.requestId,
          title: patch.isPlanOnly ? 'Plan ready for review' : 'Patch ready',
          detail: patch.isPlanOnly
              ? 'Review the plan, then approve, revise, or reject it.'
              : '${patch.fileCount} files proposed.',
          transcriptVisible: true,
        );
    if (!patch.isPlanOnly && patch.edits.isNotEmpty) {
      _ref
          .read(studioTurnProvider.notifier)
          .updatePlanTargetProgress(
            entry.requestId,
            patchSetId: patch.id,
            paths: patch.edits.map((edit) => edit.path),
            targetState: PlanTargetProgressState.proposed,
            detail: 'Concrete patch proposed.',
          );
    }
  }

  bool _verificationRequestedFor(String requestId) {
    final turnRef = _ref.read(studioTurnProvider).refForRequest(requestId);
    if (turnRef == null) return false;
    final thread = _ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    final turn = thread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
    if (turn == null) return false;
    if (IntentClassifier.requestsVerification(turn.modelPrompt)) return true;
    if (turn.acceptedPlanState != AcceptedPlanState.none) {
      if (turn.acceptedPlanContext?.verificationRequested ?? false) {
        return true;
      }
      if (turn.events.any(
        (event) =>
            event.title == 'Accepted plan verification requested' ||
            event.detail.toLowerCase().contains(
              'accepted plan asked for verification',
            ),
      )) {
        return true;
      }
      final lowerPrompt = turn.modelPrompt.toLowerCase();
      return lowerPrompt.contains('verificationrequested: true') ||
          IntentClassifier.requestsVerification(lowerPrompt);
    }
    return false;
  }

  bool _proposalRequestsVerification(
    Map<String, dynamic> args,
    String planMarkdown,
  ) {
    final verification =
        args['verification_steps'] ?? args['verificationSteps'];
    if (verification is List &&
        verification.any((item) => item is String && item.trim().isNotEmpty)) {
      return true;
    }
    if (verification is String && verification.trim().isNotEmpty) return true;
    return RegExp(
      r'(^|\n)\s{0,3}#{1,6}\s*(verification|validation|test plan|checks?)\b',
      caseSensitive: false,
    ).hasMatch(planMarkdown);
  }

  List<String> _proposalVerificationSteps(Map<String, dynamic> args) {
    final verification =
        args['verification_steps'] ?? args['verificationSteps'];
    if (verification is! List) return const [];
    return verification
        .whereType<String>()
        .map((step) => step.trim())
        .where((step) => step.isNotEmpty)
        .toSet()
        .take(5)
        .toList(growable: false);
  }
}
