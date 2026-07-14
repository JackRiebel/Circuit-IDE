import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_workspace.dart';
import '../../models/studio_shell.dart';
import '../../models/turn_intent.dart';
import '../../state/agent_turn_runtime_provider.dart';
import '../../state/agent_workspace_provider.dart';
import 'studio_message_sender.dart';

/// Keeps background task dispatch separate from the Studio shell layout.
///
/// The dispatch path retains the same runtime ownership checks as foreground
/// work: only one Studio request may run at a time, and a claimed task must be
/// bound to the request that actually starts it.
void cancelStoppedBackgroundTasks(
  WidgetRef ref,
  AgentWorkspaceState? previous,
  AgentWorkspaceState next,
) {
  if (previous == null) return;
  final previousById = {for (final task in previous.tasks) task.id: task};
  for (final task in next.tasks) {
    final before = previousById[task.id];
    final requestId = before?.activeRunId;
    if (requestId == null ||
        (task.status != AgentTaskStatus.paused &&
            task.status != AgentTaskStatus.cancelled)) {
      continue;
    }
    if (ref.read(agentTurnRuntimeProvider).sessionFor(requestId) != null) {
      ref.read(agentTurnRuntimeProvider.notifier).cancel(requestId);
    }
  }
}

void scheduleBackgroundTaskDispatch(WidgetRef ref, BuildContext context) {
  if (ref.read(agentTurnRuntimeProvider).hasActiveStudioRequest) return;
  final candidate =
      ref
          .read(agentWorkspaceProvider)
          .tasks
          .where(
            (task) =>
                task.backgroundExecutionRequested &&
                task.status == AgentTaskStatus.running &&
                task.activeRunId == null,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final task = candidate.firstOrNull;
  if (task == null) return;
  final controller = ref.read(agentWorkspaceProvider.notifier);
  final claimId = controller.claimBackgroundExecution(task.id);
  if (claimId == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted ||
        ref.read(agentTurnRuntimeProvider).hasActiveStudioRequest) {
      controller.releaseBackgroundExecutionClaim(task.id, claimId);
      return;
    }
    unawaited(_dispatchBackgroundTask(ref, task, claimId));
  });
}

Future<void> _dispatchBackgroundTask(
  WidgetRef ref,
  AgentTask task,
  String claimId,
) async {
  final controller = ref.read(agentWorkspaceProvider.notifier);
  final current = ref
      .read(agentWorkspaceProvider)
      .tasks
      .where((candidate) => candidate.id == task.id)
      .firstOrNull;
  if (current?.activeRunId != claimId ||
      current?.status != AgentTaskStatus.running) {
    return;
  }
  StudioSendResult result;
  try {
    result = await sendStudioMessage(
      ref,
      task.goal,
      taskId: task.id,
      finishTask: true,
      threadTitle: '${task.mascotAlias}: ${task.goal}',
      deferTaskWhenStudioBusy: true,
      intentRoutingOverride: _backgroundTaskIntent(task),
      promptModeOverride: backgroundTaskPromptMode(task),
    );
  } catch (_) {
    // The task owns a persisted dispatch claim even when an unexpected local
    // setup error occurs before a Studio request is registered. Clear it via
    // the normal terminal path so a same-workspace follower is promoted.
    final pending = ref
        .read(agentWorkspaceProvider)
        .tasks
        .where((candidate) => candidate.id == task.id)
        .firstOrNull;
    if (pending?.activeRunId == claimId) {
      controller.failTask(
        task.id,
        'Background task could not start. Check the connection and retry.',
      );
    }
    return;
  }
  if (result.blockedByActiveRequest) {
    // A foreground request won the single Studio lane after this task was
    // claimed. This is a retryable scheduling race, never a task failure.
    controller.releaseBackgroundExecutionClaim(task.id, claimId);
    return;
  }
  final requestId = result.requestId;
  if (requestId == null || result.status != StudioSendStatus.sent) {
    // sendStudioMessage normally writes a terminal task state for a genuine
    // preflight failure. Guard the claim anyway so no unexpected result can
    // leave a durable background task permanently undispatchable.
    final pending = ref
        .read(agentWorkspaceProvider)
        .tasks
        .where((candidate) => candidate.id == task.id)
        .firstOrNull;
    if (pending?.activeRunId == claimId) {
      controller.failTask(
        task.id,
        result.error ??
            'Background task could not start. Check the connection and retry.',
      );
    }
    return;
  }
  final bound = controller.bindBackgroundExecutionRequest(
    task.id,
    claimId: claimId,
    requestId: requestId,
  );
  if (!bound &&
      ref.read(agentTurnRuntimeProvider).sessionFor(requestId) != null) {
    ref.read(agentTurnRuntimeProvider.notifier).cancel(requestId);
  }
}

IntentRoutingDecision _backgroundTaskIntent(AgentTask task) {
  final intent = switch (task.profile) {
    AgentTaskProfile.investigate ||
    AgentTaskProfile.research ||
    AgentTaskProfile.handoff => TurnIntent.ask,
    AgentTaskProfile.plan => TurnIntent.plan,
    AgentTaskProfile.patch => TurnIntent.code,
    AgentTaskProfile.review => TurnIntent.review,
    AgentTaskProfile.verify => TurnIntent.verify,
  };
  return IntentRoutingDecision(
    intent: intent,
    confidence: 1,
    reason: 'Explicitly started ${task.profile.name} background task.',
    source: IntentRoutingSource.deterministic,
  );
}

/// Background Research retains its web-only tool contract even if the visible
/// composer mode changes before the queued task reaches the runtime.
StudioPromptMode? backgroundTaskPromptMode(AgentTask task) {
  return task.profile == AgentTaskProfile.research
      ? StudioPromptMode.research
      : null;
}
