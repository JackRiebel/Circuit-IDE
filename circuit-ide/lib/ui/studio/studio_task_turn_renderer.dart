import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/generated_artifact.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_source_artifact.dart';
import '../../models/studio_turn.dart';
import '../../models/turn_intent.dart';
import '../../state/studio_source_artifact_provider.dart';
import 'studio_message_sender.dart';
import 'studio_plan_continuation.dart';
import 'studio_task_artifact_cards.dart';
import 'studio_task_patch_summary.dart';
import 'studio_task_plan_continuation_card.dart';
import 'studio_task_plan_draft.dart';
import 'studio_task_plan_summary.dart';
import 'studio_task_transcript_chrome.dart';
import 'studio_task_transcript_messages.dart';
import 'studio_task_transcript_status.dart';

/// Builds one persisted Studio turn from its durable events and artifacts.
///
/// Transcript scrolling and selection stay in [StudioTaskView]; this renderer
/// owns the presentation policy for turn evidence so plans, artifacts,
/// approvals, recovery, and final outcomes evolve independently.
abstract final class StudioTaskTurnRenderer {
  static Widget build(
    BuildContext context,
    WidgetRef ref,
    StudioTurn turn,
    ProposedPatchSet? turnPatch, {
    required String? taskId,
  }) {
    final widgets = <Widget>[];
    var patchAdded = false;
    var artifactCardsAdded = false;
    final generatedArtifacts = ref.watch(
      studioSourceArtifactProvider.select(
        (state) => state.artifacts
            .where(
              (artifact) =>
                  artifact.kind == StudioSourceArtifactKind.generatedArtifact &&
                  artifact.requestId == turn.requestId,
            )
            .toList(growable: false),
      ),
    );
    final events = turn.events.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final visibleUserMessage = events
        .where(
          (event) =>
              event.type == StudioTurnEventType.userMessage &&
              event.transcriptVisible &&
              (event.content ?? event.detail).trim().isNotEmpty,
        )
        .firstOrNull;
    if (visibleUserMessage != null) {
      widgets.add(
        StudioTaskChatTranscriptLine(
          isUser: true,
          text: visibleUserMessage.content ?? visibleUserMessage.detail,
        ),
      );
    } else if (_shouldRenderFallbackPrompt(turn, events)) {
      widgets.add(
        StudioTaskChatTranscriptLine(isUser: true, text: turn.displayPrompt),
      );
    }
    for (final event in events) {
      switch (event.type) {
        case StudioTurnEventType.userMessage:
          break;
        case StudioTurnEventType.context:
          // Routine context details stay in the progress drawer. Keeping them
          // out of chat prevents every request from becoming a stack of bars.
          break;
        case StudioTurnEventType.progress:
          if (turnPatch != null &&
              (event.title == 'Plan ready for review' ||
                  event.title == 'Patch ready')) {
            break;
          }
          break;
        case StudioTurnEventType.tool:
          break;
        case StudioTurnEventType.approvalRequest:
          widgets.add(StudioTurnApprovalCard(event: event));
        case StudioTurnEventType.assistantMessage:
          final assistantContent = (event.content ?? '').trim();
          final duplicatePlanContent =
              turnPatch != null &&
              _isDuplicatePlanAssistantContent(assistantContent, turnPatch);
          final displayContent = _assistantContentForArtifacts(
            assistantContent,
            generatedArtifacts,
          );
          if (displayContent.isNotEmpty && !duplicatePlanContent) {
            widgets.add(
              StudioTaskChatTranscriptLine(isUser: false, text: displayContent),
            );
          }
          if (generatedArtifacts.isNotEmpty && !artifactCardsAdded) {
            widgets.add(
              StudioGeneratedArtifactStack(artifacts: generatedArtifacts),
            );
            artifactCardsAdded = true;
          }
          if (turnPatch != null && !patchAdded) {
            widgets.add(_reviewArtifactCard(turnPatch));
            patchAdded = true;
          }
        case StudioTurnEventType.error:
          widgets.add(
            StudioTaskTranscriptEvent(
              icon: StudioIcons.errorOutline,
              title: event.title,
              detail: event.detail,
            ),
          );
        case StudioTurnEventType.completionSummary:
          if (_isGenericReadySummary(event)) break;
          widgets.add(
            StudioTaskTranscriptEvent(
              icon: StudioIcons.checkCircleOutline,
              title: event.title,
              detail: event.detail,
            ),
          );
      }
    }
    final hasFinalAssistant = events.any(
      (event) => event.type == StudioTurnEventType.assistantMessage,
    );
    if (!hasFinalAssistant && turn.assistantDraft.trim().isNotEmpty) {
      final draftContent = _assistantContentForArtifacts(
        turn.assistantDraft,
        generatedArtifacts,
      );
      if (turn.intent == TurnIntent.plan) {
        widgets.add(StudioPlanDraftCard(markdown: turn.assistantDraft));
      } else if (draftContent.isNotEmpty) {
        widgets.add(
          StudioTaskChatTranscriptLine(
            isUser: false,
            text: draftContent,
            isStreaming: turn.status == StudioTurnStatus.streaming,
          ),
        );
      }
    }
    if (generatedArtifacts.isNotEmpty && !artifactCardsAdded) {
      widgets.add(StudioGeneratedArtifactStack(artifacts: generatedArtifacts));
    }
    if (turnPatch != null && !patchAdded) {
      widgets.add(_reviewArtifactCard(turnPatch));
    } else if (turnPatch == null) {
      final continuation = studioPlanContinuationForTurn(turn);
      if (continuation != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: StudioPlanContinuationCard(
              continuation: continuation,
              onContinue: () => implementAcceptedPlanFromStudio(
                ref,
                continuation.acceptedPlan,
                taskId: taskId,
                finishTask: taskId != null,
                displayText: 'Continuing approved plan',
              ),
            ),
          ),
        );
      }
    }
    final recovery = turn.recoveryCheckpoint;
    if (turn.status == StudioTurnStatus.interrupted && recovery != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: StudioTaskRecoveryCard(turn: turn, taskId: taskId),
        ),
      );
    }
    final outcome = turn.finalOutcome;
    if (outcome != null) {
      widgets.add(
        StudioTaskTranscriptEvent(
          icon: switch (outcome) {
            StudioTurnOutcome.failed ||
            StudioTurnOutcome.blocked => StudioIcons.errorOutline,
            StudioTurnOutcome.cancelled => StudioIcons.cancelOutlined,
            _ => StudioIcons.taskAltOutlined,
          },
          title: studioTurnOutcomeTitle(outcome),
          detail: _finalOutcomeDetail(turn, outcome),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  static Widget _reviewArtifactCard(ProposedPatchSet patch) {
    return patch.isPlanOnly
        ? StudioPlanSummaryCard(patch: patch)
        : StudioPatchSummaryCard(patch: patch);
  }

  static String _assistantContentForArtifacts(
    String content,
    List<StudioSourceArtifact> artifacts,
  ) {
    final trimmed = content.trim();
    if (trimmed.isEmpty || artifacts.isEmpty) return trimmed;
    if (!_shouldCollapseArtifactAssistantContent(trimmed)) return trimmed;
    final intro = _artifactResponseIntro(trimmed);
    final generatedArtifacts = artifacts
        .map(GeneratedArtifact.fromSourceArtifact)
        .nonNulls
        .toList(growable: false);
    final artifact = generatedArtifacts.isNotEmpty
        ? generatedArtifacts.first
        : null;
    final fileName = artifact?.fileName ?? artifacts.first.title;
    final summary = generatedArtifacts.length > 1
        ? 'Created ${generatedArtifacts.length} file artifacts.'
        : artifact?.summary ?? 'Created a file artifact.';
    return [
      if (intro.isNotEmpty) intro,
      '$summary See `$fileName` below.',
    ].join('\n\n');
  }

  static bool _shouldCollapseArtifactAssistantContent(String content) {
    if (_containsLargeMarkdownTable(content)) return true;
    final lines = content.split('\n');
    final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty).length;
    if (content.length >= 1800 && nonEmptyLines >= 16) return true;
    if (nonEmptyLines >= 34) return true;
    final headingCount = lines
        .where((line) => line.trimLeft().startsWith(RegExp(r'#{2,6}\s')))
        .length;
    final bulletCount = lines
        .where((line) => line.trimLeft().startsWith(RegExp(r'[-*]\s+')))
        .length;
    return content.length >= 1400 && headingCount >= 2 && bulletCount >= 6;
  }

  static String _artifactResponseIntro(String content) {
    final introLines = <String>[];
    var nonEmptyLines = 0;
    for (final line in content.split('\n')) {
      final value = line.trim();
      if (value.contains('|') ||
          value.startsWith('```') ||
          value.startsWith(RegExp(r'#{2,6}\s')) ||
          value.startsWith(RegExp(r'[-*]\s+'))) {
        break;
      }
      introLines.add(line);
      if (value.isNotEmpty) nonEmptyLines++;
      if (nonEmptyLines >= 4 || introLines.join('\n').length >= 560) break;
    }
    final intro = introLines.join('\n').trim();
    if (intro.length <= 640) return intro;
    return '${intro.substring(0, 640).trimRight()}...';
  }

  static bool _containsLargeMarkdownTable(String content) {
    var tableRows = 0;
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.contains('|') && trimmed.split('|').length >= 3) {
        tableRows++;
        if (tableRows >= 5) return true;
      } else if (tableRows > 0) {
        tableRows = 0;
      }
    }
    return false;
  }

  static bool _isDuplicatePlanAssistantContent(
    String assistantContent,
    ProposedPatchSet patch,
  ) {
    if (!patch.isPlanOnly || assistantContent.length < 180) return false;
    final planMarkdown = (patch.planMarkdown ?? '').trim();
    if (planMarkdown.isEmpty) return false;
    final normalizedAssistant = _normalizePlanTextForComparison(
      assistantContent,
    );
    final normalizedPlan = _normalizePlanTextForComparison(planMarkdown);
    if (normalizedAssistant.isEmpty || normalizedPlan.isEmpty) return false;
    if (normalizedAssistant == normalizedPlan) return true;
    final assistantLooksLikePlan =
        RegExp(r'(^|\n)\s{0,4}([-*]|\d+[.)])\s+').hasMatch(assistantContent) ||
        RegExp(r'^\s*#{1,6}\s+', multiLine: true).hasMatch(assistantContent);
    return assistantLooksLikePlan &&
        normalizedAssistant.length > 220 &&
        normalizedPlan.contains(normalizedAssistant);
  }

  static String _normalizePlanTextForComparison(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[`*_>#-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isGenericReadySummary(StudioTurnEvent event) {
    final title = event.title.trim().toLowerCase();
    final detail = event.detail.trim().toLowerCase();
    return title == 'ready for next prompt' &&
        (detail.isEmpty || detail == 'ready for the next prompt.');
  }

  static bool _shouldRenderFallbackPrompt(
    StudioTurn turn,
    List<StudioTurnEvent> events,
  ) {
    if (events.any((event) => event.type == StudioTurnEventType.userMessage)) {
      return false;
    }
    if (turn.acceptedPlanState != AcceptedPlanState.none ||
        turn.acceptedPlanContext != null) {
      return false;
    }
    final prompt = turn.displayPrompt.trim();
    if (prompt.isEmpty) return false;
    final lower = prompt.toLowerCase();
    const internalPrefixes = [
      'implement this approved plan',
      'use the accepted plan context',
      'running verification',
      'run verification',
      'verify the applied patch',
    ];
    return !internalPrefixes.any(lower.startsWith);
  }

  static String _finalOutcomeDetail(
    StudioTurn turn,
    StudioTurnOutcome outcome,
  ) {
    return switch (outcome) {
      StudioTurnOutcome.answered => 'Response recorded in this transcript.',
      StudioTurnOutcome.createdArtifact =>
        '${turn.toolResults.expand((result) => result.artifacts).length} artifact${turn.toolResults.expand((result) => result.artifacts).length == 1 ? '' : 's'} recorded. Review the artifact card above.',
      StudioTurnOutcome.preparedChanges =>
        'Changes are ready for review. Approve or revise the proposal above.',
      StudioTurnOutcome.appliedChanges =>
        turn.planTargetProgress.isEmpty
            ? 'Changes were applied. Review the patch or run verification next.'
            : '${turn.planTargetProgress.where((target) => target.state == PlanTargetProgressState.applied).length} planned target${turn.planTargetProgress.where((target) => target.state == PlanTargetProgressState.applied).length == 1 ? '' : 's'} applied. Review the patch or run verification next.',
      StudioTurnOutcome.verified =>
        'Verification completed. Review the command evidence above.',
      StudioTurnOutcome.blocked =>
        'A policy or approval blocked this task. Review the error and retry when ready.',
      StudioTurnOutcome.failed =>
        'The task stopped before completion. Review the error and retry when ready.',
      StudioTurnOutcome.cancelled =>
        'The request was cancelled. Start a new turn to retry.',
    };
  }
}
