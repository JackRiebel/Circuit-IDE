import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_workspace.dart';
import '../../models/reviewed_edit.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../models/studio_view_models.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_thread_provider.dart';

class StudioTaskTranscriptIndex {
  final String? threadId;
  final String title;
  final String? effectiveTaskId;
  final String statusLabel;
  final bool statusActive;
  final String? lastError;
  final List<String> turnIds;
  final List<StudioConversationCompaction> compactions;

  const StudioTaskTranscriptIndex({
    required this.threadId,
    required this.title,
    required this.effectiveTaskId,
    required this.statusLabel,
    required this.statusActive,
    required this.lastError,
    required this.turnIds,
    required this.compactions,
  });

  factory StudioTaskTranscriptIndex.fromState(
    StudioThreadState state,
    AgentTask? task,
  ) {
    final thread = state.threadForTaskView(task?.id);
    final effectiveTaskId = task?.id ?? thread?.taskId;
    final lifecycle = StudioTaskLifecycleState.fromThread(thread);
    final displayState = TaskDisplayState.fromLifecycle(lifecycle);
    final orderedTurns = (thread?.turns ?? const <StudioTurn>[]).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    // A durable compaction is an explicit collapsed historical range. Its
    // source IDs stay in storage and can be restored by the user; keeping
    // them out of the default transcript prevents a thousand-turn task from
    // allocating a transcript row for every compacted historical turn.
    final compactedTurnIds = (thread?.conversationCompactions ?? const [])
        .where((compaction) => !compaction.restored)
        .expand((compaction) => compaction.sourceTurnIds)
        .toSet();
    return StudioTaskTranscriptIndex(
      threadId: thread?.id,
      title: thread?.title ?? task?.goal ?? 'New Circuit task',
      effectiveTaskId: effectiveTaskId,
      statusLabel: _statusLabel(thread, displayState),
      statusActive: displayState.isActive,
      lastError: thread?.lastError,
      turnIds: [
        for (final turn in orderedTurns)
          if (!compactedTurnIds.contains(turn.id)) turn.id,
      ],
      compactions: thread?.conversationCompactions ?? const [],
    );
  }

  static String _elapsed(DateTime start) {
    final delta = DateTime.now().difference(start);
    if (delta.inMinutes < 1) return '${delta.inSeconds}s';
    return '${delta.inMinutes}m ${delta.inSeconds.remainder(60)}s';
  }

  static String _statusLabel(
    StudioThread? thread,
    TaskDisplayState displayState,
  ) {
    if (!displayState.isActive) {
      final workedFor = _workedDuration(thread);
      if (workedFor != null && displayState.kind == TaskDisplayKind.done) {
        return 'Worked for $workedFor';
      }
      return displayState.label;
    }
    final startedAt = _activeTurnStartedAt(thread);
    final elapsed = startedAt == null ? '' : ' for ${_elapsed(startedAt)}';
    return '${displayState.label}$elapsed';
  }

  static String? _workedDuration(StudioThread? thread) {
    if (thread == null || thread.turns.isEmpty) return null;
    final completedTurns = thread.turns.where(
      (turn) =>
          turn.completedAt != null &&
          !turn.completedAt!.isBefore(turn.createdAt),
    );
    if (completedTurns.isEmpty) return null;
    final latest = completedTurns.reduce(
      (a, b) => a.completedAt!.isAfter(b.completedAt!) ? a : b,
    );
    return _formatDuration(latest.completedAt!.difference(latest.createdAt));
  }

  static DateTime? _activeTurnStartedAt(StudioThread? thread) {
    if (thread == null || thread.turns.isEmpty) return null;
    final activeTurns = thread.turns.where(
      (turn) => switch (turn.status) {
        StudioTurnStatus.queued ||
        StudioTurnStatus.buildingContext ||
        StudioTurnStatus.sent ||
        StudioTurnStatus.waitingForModel ||
        StudioTurnStatus.streaming ||
        StudioTurnStatus.toolRunning ||
        StudioTurnStatus.waitingForApproval ||
        StudioTurnStatus.verifying => true,
        StudioTurnStatus.reviewingPatch => false,
        StudioTurnStatus.completed ||
        StudioTurnStatus.failed ||
        StudioTurnStatus.cancelled ||
        StudioTurnStatus.interrupted => false,
      },
    );
    final candidates = activeTurns.isEmpty ? thread.turns : activeTurns;
    return candidates
        .reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b)
        .createdAt;
  }

  static String _formatDuration(Duration delta) {
    if (delta.inHours > 0) {
      return '${delta.inHours}h ${delta.inMinutes.remainder(60)}m';
    }
    if (delta.inMinutes > 0) {
      return '${delta.inMinutes}m ${delta.inSeconds.remainder(60)}s';
    }
    return '${delta.inSeconds}s';
  }

  @override
  bool operator ==(Object other) {
    return other is StudioTaskTranscriptIndex &&
        threadId == other.threadId &&
        title == other.title &&
        effectiveTaskId == other.effectiveTaskId &&
        statusLabel == other.statusLabel &&
        statusActive == other.statusActive &&
        lastError == other.lastError &&
        listEquals(turnIds, other.turnIds) &&
        listEquals(compactions, other.compactions);
  }

  @override
  int get hashCode => Object.hash(
    threadId,
    title,
    effectiveTaskId,
    statusLabel,
    statusActive,
    lastError,
    Object.hashAll(turnIds),
    Object.hashAll(compactions),
  );
}

typedef StudioTurnTranscriptBuilder =
    Widget Function(
      BuildContext context,
      WidgetRef ref,
      StudioTurn turn,
      ProposedPatchSet? turnPatch, {
      required String? taskId,
    });

class StudioTurnTranscriptItem extends ConsumerWidget {
  final String turnId;
  final String? taskId;
  final bool isLatestTurn;
  final StudioTurnTranscriptBuilder builder;

  const StudioTurnTranscriptItem({
    super.key,
    required this.turnId,
    required this.taskId,
    required this.isLatestTurn,
    required this.builder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turn = ref.watch(
      studioThreadProvider.select(
        (state) => _turnById(state, turnId, taskId: taskId),
      ),
    );
    if (turn == null) return const SizedBox.shrink();
    final turnPatch = ref.watch(
      patchProposalProvider.select(
        (state) => _patchForTurn(
          _visiblePatchesForTask(state, taskId),
          turn,
          isLatestTurn: isLatestTurn,
        ),
      ),
    );
    return KeyedSubtree(
      key: ValueKey('studio-turn-${turn.id}'),
      child: builder(context, ref, turn, turnPatch, taskId: taskId),
    );
  }

  static StudioTurn? _turnById(
    StudioThreadState state,
    String turnId, {
    required String? taskId,
  }) {
    final thread = state.threadForTaskView(taskId);
    if (thread != null) {
      for (final turn in thread.turns) {
        if (turn.id == turnId) return turn;
      }
    }
    final selectedThread = state.selectedThread;
    if (selectedThread != null && selectedThread.id != thread?.id) {
      for (final turn in selectedThread.turns) {
        if (turn.id == turnId) return turn;
      }
    }
    return null;
  }

  static ProposedPatchSet? _patchForTurn(
    List<ProposedPatchSet> patches,
    StudioTurn turn, {
    required bool isLatestTurn,
  }) {
    return patches
            .where((patch) => patch.runId == turn.requestId)
            .firstOrNull ??
        (isLatestTurn
            ? patches.where((patch) => patch.runId == null).firstOrNull
            : null);
  }

  static List<ProposedPatchSet> _visiblePatchesForTask(
    PatchProposalState state,
    String? taskId,
  ) {
    final byId = <String, ProposedPatchSet>{};

    void addPatch(ProposedPatchSet? patch) {
      if (patch == null) return;
      if (patch.approvalStatus == PatchApprovalStatus.rejected) return;
      if (patch.agentTaskId != null && patch.agentTaskId != taskId) return;
      byId[patch.id] = patch;
    }

    addPatch(state.active);
    for (final patch in state.history) {
      addPatch(patch);
    }
    return byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
}
