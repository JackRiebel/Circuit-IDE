import '../../enums/message_role.dart';
import '../../models/chat_message.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';

/// Builds the exact conversation history exposed to a general Studio turn.
///
/// Accepted-plan implementation prompts and hidden system continuations are
/// intentionally excluded, so a model never mistakes an orchestration prompt
/// for a user-authored request.
List<ChatMessage> studioModelHistoryForThread(StudioThread thread) {
  return _modelHistoryFromTurns(
    thread.turns,
    conversationCompactions: thread.conversationCompactions,
  );
}

List<ChatMessage> _modelHistoryFromTurns(
  List<StudioTurn> turns, {
  List<StudioConversationCompaction> conversationCompactions = const [],
}) {
  final sortedTurns = turns.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final activeCompactions = conversationCompactions
      .where((compaction) => !compaction.restored)
      .toList(growable: false);
  final compactedTurnIds = {
    for (final compaction in activeCompactions) ...compaction.sourceTurnIds,
  };
  final compactionStarts = <String, StudioConversationCompaction>{
    for (final compaction in activeCompactions)
      if (compaction.sourceTurnIds.isNotEmpty)
        compaction.sourceTurnIds.first: compaction,
  };
  final history = <ChatMessage>[];
  for (final turn in sortedTurns) {
    final compaction = compactionStarts[turn.id];
    if (compaction != null) {
      history.add(
        ChatMessage(
          id: 'conversation-compaction-${compaction.id}',
          role: MessageRole.system,
          content: '[read-only conversation compaction]\n${compaction.summary}',
          timestamp: turn.createdAt,
        ),
      );
    }
    if (compactedTurnIds.contains(turn.id)) continue;
    final prompt = turn.displayPrompt.trim();
    if (prompt.isNotEmpty && _turnHasVisibleUserMessage(turn)) {
      history.add(
        ChatMessage(
          id: turn.userMessageId,
          role: MessageRole.user,
          content: prompt,
          timestamp: turn.createdAt,
        ),
      );
    }

    final assistantEvent = _assistantHistoryEvent(turn);
    final assistantContent = assistantEvent?.content?.trim().isNotEmpty == true
        ? assistantEvent!.content!.trim()
        : assistantEvent?.detail.trim() ?? _turnFailureHistoryDetail(turn);
    if (assistantContent.isNotEmpty) {
      history.add(
        ChatMessage(
          id: assistantEvent?.id ?? 'failure-${turn.id}',
          role: MessageRole.assistant,
          content: assistantContent,
          timestamp:
              assistantEvent?.timestamp ?? turn.completedAt ?? turn.updatedAt,
        ),
      );
    }
  }
  return history;
}

bool _turnHasVisibleUserMessage(StudioTurn turn) {
  if (turn.acceptedPlanContext != null ||
      turn.acceptedPlanState != AcceptedPlanState.none) {
    return false;
  }
  final userEvents = turn.events
      .where((event) => event.type == StudioTurnEventType.userMessage)
      .toList(growable: false);
  if (userEvents.isEmpty) return true;
  return userEvents.any((event) => event.transcriptVisible);
}

String _turnFailureHistoryDetail(StudioTurn turn) {
  if (turn.status != StudioTurnStatus.failed &&
      turn.status != StudioTurnStatus.cancelled &&
      turn.status != StudioTurnStatus.interrupted) {
    return '';
  }
  return turn.lastError?.trim() ?? '';
}

StudioTurnEvent? _assistantHistoryEvent(StudioTurn turn) {
  final assistantEvents =
      turn.events
          .where((event) => event.type == StudioTurnEventType.assistantMessage)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (assistantEvents.isNotEmpty) return assistantEvents.last;
  if (turn.status == StudioTurnStatus.completed) {
    final summaries =
        turn.events
            .where(
              (event) => event.type == StudioTurnEventType.completionSummary,
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (summaries.isNotEmpty) return summaries.last;
  }
  if (turn.status == StudioTurnStatus.failed ||
      turn.status == StudioTurnStatus.cancelled ||
      turn.status == StudioTurnStatus.interrupted) {
    final errors =
        turn.events
            .where((event) => event.type == StudioTurnEventType.error)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (errors.isNotEmpty) return errors.last;
  }
  return null;
}
