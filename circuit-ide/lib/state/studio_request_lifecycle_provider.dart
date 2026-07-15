import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/turn_completion_summary.dart';
import '../enums/event_type.dart';
import '../models/confirmation_request.dart';
import '../models/agent_tool_permission.dart';
import '../models/provider_lifecycle_event.dart';
import '../models/studio_request_lifecycle.dart';
import '../models/studio_source_artifact.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import '../models/token_usage.dart';
import '../models/tool_call_info.dart';
import '../models/tool_result_envelope.dart';
import '../models/turn_intent.dart';
import '../services/deep_research_report_builder.dart';
import '../services/event_bus.dart';
import 'agent_workspace_provider.dart';
import 'studio_request_patch_proposal.dart';
import 'studio_request_tool_activity.dart';
import 'studio_thread_provider.dart';
import 'studio_turn_provider.dart';

part 'studio_request_lifecycle_completion.dart';
part 'studio_request_lifecycle_provider_events.dart';

class StudioRequestLifecycleController
    extends _StudioRequestLifecycleProviderEventController {
  final _softTimers = <String, Timer>{};
  final _hardTimers = <String, Timer>{};
  final _runtimeEventBindings = <String, _LifecycleEventBinding>{};

  @override
  StudioRequestLifecycleState build() {
    ref.onDispose(() {
      for (final timer in [..._softTimers.values, ..._hardTimers.values]) {
        timer.cancel();
      }
      for (final binding in _runtimeEventBindings.values) {
        binding.dispose();
      }
    });
    return const StudioRequestLifecycleState();
  }

  void attachRuntimeEvents(String requestId, EventBus events) {
    detachRuntimeEvents(requestId);
    final handlers = <EventType, EventHandler>{};
    _listenToAgentEvents(
      events,
      handlers,
      finishOnTerminalProviderDiagnostic: false,
    );
    _runtimeEventBindings[requestId] = _LifecycleEventBinding(
      events: events,
      handlers: handlers,
    );
  }

  void detachRuntimeEvents(String requestId) {
    _runtimeEventBindings.remove(requestId)?.dispose();
  }

  void registerRequest({
    required String requestId,
    required String threadId,
    required String model,
    required StudioContextSummary contextSummary,
    TurnIntent intent = TurnIntent.code,
    String? taskId,
  }) {
    final now = DateTime.now();
    final entry = StudioRequestLifecycleEntry(
      requestId: requestId,
      threadId: threadId,
      taskId: taskId,
      model: model,
      intent: intent,
      contextSummary: contextSummary,
      startedAt: now,
      lastEventAt: now,
      lastEventKind: StudioRequestLifecycleEventKind.requestStarted,
      lastEventDetail: 'Request sent to Circuit AI.',
    );
    state = state.copyWith(
      activeRequests: {...state.activeRequests, requestId: entry},
    );
    ref
        .read(studioThreadProvider.notifier)
        .markPhase(
          threadId,
          status: StudioThreadStatus.preflighting,
          phase: StudioSendPhase.preflighting,
          requestId: requestId,
          model: model,
          contextSummary: contextSummary,
        );
    ref
        .read(studioTurnProvider.notifier)
        .markProgress(
          requestId,
          title: 'Request sent',
          detail: 'Waiting for Circuit AI.',
          status: StudioTurnStatus.waitingForModel,
        );
    _scheduleWatchdogs(entry);
  }

  void cancelRequest(
    String requestId, {
    String message = 'Request cancelled.',
  }) {
    final entry = state.active(requestId);
    if (entry == null) return;
    _finish(entry, StudioRequestLifecycleEventKind.cancelled, message);
  }

  void failRequest(String requestId, String message) {
    final entry = state.active(requestId);
    if (entry == null) return;
    _finish(entry, StudioRequestLifecycleEventKind.failed, message);
  }

  void completeRequest(String requestId, {String message = 'Completed.'}) {
    final entry = state.active(requestId);
    if (entry == null) return;
    ref
        .read(studioTurnProvider.notifier)
        .complete(requestId, content: '', summary: message);
    ref.read(studioThreadProvider.notifier).complete(entry.threadId);
    if (entry.taskId != null) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .completeTask(entry.taskId!, result: message);
    }
    _finish(entry, StudioRequestLifecycleEventKind.completed, message);
  }

  void _listenToAgentEvents(
    EventBus events,
    Map<EventType, EventHandler> handlers, {
    required bool finishOnTerminalProviderDiagnostic,
  }) {
    void on(EventType type, EventHandler handler) {
      handlers[type] = handler;
      events.on(type, handler);
    }

    on(EventType.messageStarted, _handleMessageStarted);
    on(EventType.messageChunk, _handleMessageChunk);
    on(EventType.planDraftUpdated, _handlePlanDraftUpdated);
    on(EventType.tokensUpdated, _handleTokensUpdated);
    on(EventType.toolCallStarted, _handleToolStarted);
    on(EventType.toolCallCompleted, _handleToolCompleted);
    on(EventType.toolCallError, _handleToolError);
    on(EventType.toolResultRecorded, _handleToolResultRecorded);
    on(EventType.confirmationNeeded, _handleConfirmationNeeded);
    on(EventType.confirmationReceived, _handleConfirmationReceived);
    on(EventType.messageCompleted, _handleMessageCompleted);
    on(EventType.messageError, _handleMessageError);
    on(
      EventType.providerLifecycle,
      (event) => _handleProviderLifecycle(
        event,
        finishOnTerminalProviderDiagnostic: finishOnTerminalProviderDiagnostic,
      ),
    );
  }

  @override
  StudioRequestLifecycleEntry? _entryFor(Event event) {
    final requestId = event.data['requestId'] as String?;
    if (requestId == null) return null;
    return state.active(requestId);
  }

  void _handleMessageStarted(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    _touch(
      entry,
      StudioRequestLifecycleEventKind.requestStarted,
      detail: 'Circuit AI accepted the request.',
    );
    ref
        .read(studioTurnProvider.notifier)
        .markProgress(
          entry.requestId,
          title: 'Connected',
          detail: 'Circuit AI accepted the request.',
          status: StudioTurnStatus.waitingForModel,
        );
  }

  void _handlePlanDraftUpdated(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final content = event.data['content'] as String? ?? '';
    ref
        .read(studioTurnProvider.notifier)
        .replaceAssistantDraft(entry.requestId, content);
    _touch(
      entry,
      StudioRequestLifecycleEventKind.streaming,
      detail: 'Circuit AI is drafting a plan.',
    );
  }

  void _handleMessageChunk(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final content = event.data['content'] as String? ?? '';
    _touch(
      entry,
      StudioRequestLifecycleEventKind.streaming,
      detail: 'Circuit AI is responding.',
    );
    ref
        .read(studioTurnProvider.notifier)
        .appendAssistantDelta(entry.requestId, content);
    ref
        .read(studioThreadProvider.notifier)
        .markPhase(
          entry.threadId,
          status: StudioThreadStatus.streaming,
          phase: StudioSendPhase.streaming,
          requestId: entry.requestId,
          model: entry.model,
          contextSummary: entry.contextSummary,
        );
  }

  void _handleTokensUpdated(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final usage = event.data['lastUsage'] as TokenUsage?;
    if (usage == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .updateTokenUsage(entry.threadId, usage);
  }

  void _handleToolStarted(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final tool = event.data['toolCall'] as ToolCallInfo?;
    final activity = describeStudioRequestToolActivity(tool, running: true);
    _touch(
      entry,
      StudioRequestLifecycleEventKind.toolRunning,
      detail: activity.detail,
    );
    ref
        .read(studioThreadProvider.notifier)
        .markPhase(
          entry.threadId,
          status: StudioThreadStatus.runningCommand,
          phase: StudioSendPhase.runningCommand,
          requestId: entry.requestId,
          model: entry.model,
          contextSummary: entry.contextSummary,
        );
    if (tool != null) {
      _upsertToolEvent(
        entry,
        tool,
        activity.title,
        activity.detail,
        running: true,
      );
    } else {
      ref
          .read(studioTurnProvider.notifier)
          .markProgress(
            entry.requestId,
            title: 'Tool running',
            detail: 'running',
            status: StudioTurnStatus.toolRunning,
          );
    }
  }

  void _handleToolCompleted(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final tool = event.data['toolCall'] as ToolCallInfo?;
    final activity = describeStudioRequestToolActivity(tool, running: false);
    _touch(
      entry,
      StudioRequestLifecycleEventKind.toolRunning,
      detail: activity.detail,
    );
    if (tool != null) {
      _upsertToolEvent(entry, tool, activity.title, activity.detail);
      if (tool.name == 'propose_patch') {
        StudioRequestPatchProposalHandler(ref).createPatchPlan(entry, tool);
      }
    } else {
      ref
          .read(studioTurnProvider.notifier)
          .markProgress(
            entry.requestId,
            title: 'Tool completed',
            detail: 'completed',
          );
    }
  }

  void _handleToolError(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final tool = event.data['toolCall'] as ToolCallInfo?;
    final activity = describeStudioRequestToolActivity(
      tool,
      running: false,
      failed: true,
    );
    _touch(
      entry,
      StudioRequestLifecycleEventKind.toolRunning,
      detail: activity.detail,
    );
    if (tool != null) {
      _upsertToolEvent(entry, tool, activity.title, activity.detail);
    } else {
      ref
          .read(studioTurnProvider.notifier)
          .markProgress(
            entry.requestId,
            title: 'Tool failed',
            detail: 'failed',
          );
    }
  }

  void _handleToolResultRecorded(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final result = event.data['result'] as ToolResultEnvelope?;
    if (result == null) return;
    ref
        .read(studioTurnProvider.notifier)
        .addToolResult(entry.requestId, result);
    ref
        .read(studioTurnProvider.notifier)
        .recordResearchToolResult(entry.requestId, result);
  }

  void _handleConfirmationNeeded(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    _touch(
      entry,
      StudioRequestLifecycleEventKind.approvalNeeded,
      detail: 'Waiting for approval.',
    );
    ref.read(studioThreadProvider.notifier).waitForApproval(entry.threadId);
    final request = event.data['request'] as ConfirmationRequest?;
    if (request != null) {
      ref
          .read(studioTurnProvider.notifier)
          .upsertApproval(entry.requestId, request);
    }
    if (entry.taskId != null) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .markWaitingForApproval(
            entry.taskId!,
            message: 'Waiting for approval.',
          );
    }
  }

  void _handleConfirmationReceived(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final approvalId = event.data['id'] as String?;
    if (approvalId == null) return;
    final approved = event.data['approved'] as bool? ?? false;
    final expired = event.data['approvalExpired'] as bool? ?? false;
    final approvalGrant = ApprovalGrant.values
        .where((value) => value.name == event.data['approvalGrant'])
        .firstOrNull;
    ref
        .read(studioTurnProvider.notifier)
        .resolveApproval(
          entry.requestId,
          approvalId,
          expired
              ? ApprovalRequestState.expired
              : approved
              ? ApprovalRequestState.approved
              : ApprovalRequestState.rejected,
          approvalGrant: approved ? approvalGrant : null,
        );
    _touch(
      entry,
      StudioRequestLifecycleEventKind.toolRunning,
      detail: expired
          ? 'Approval expired.'
          : approved
          ? 'Approval granted.'
          : 'Approval rejected.',
    );
  }

  void _handleMessageError(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final error = event.data['error'] as String? ?? 'Request failed.';
    ref.read(studioThreadProvider.notifier).fail(entry.threadId, error);
    ref.read(studioTurnProvider.notifier).fail(entry.requestId, error);
    if (entry.taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(entry.taskId!, error);
    }
    _finish(entry, StudioRequestLifecycleEventKind.failed, error);
  }

  @override
  void _touch(
    StudioRequestLifecycleEntry entry,
    StudioRequestLifecycleEventKind kind, {
    String? detail,
  }) {
    final updated = entry.copyWith(
      lastEventAt: DateTime.now(),
      lastEventKind: kind,
      lastEventDetail: detail,
    );
    state = state.copyWith(
      activeRequests: {...state.activeRequests, entry.requestId: updated},
    );
    _scheduleSoftWatchdog(updated);
  }

  @override
  void _finish(
    StudioRequestLifecycleEntry entry,
    StudioRequestLifecycleEventKind kind,
    String detail,
  ) {
    _cancelTimers(entry.requestId);
    detachRuntimeEvents(entry.requestId);
    final finished = entry.copyWith(
      lastEventAt: DateTime.now(),
      lastEventKind: kind,
      lastEventDetail: detail,
    );
    final active = {...state.activeRequests}..remove(entry.requestId);
    final recent = {entry.requestId: finished, ...state.recentRequests};
    state = state.copyWith(
      activeRequests: active,
      recentRequests: Map.fromEntries(recent.entries.take(30)),
    );
    if (kind == StudioRequestLifecycleEventKind.failed) {
      ref.read(studioThreadProvider.notifier).fail(entry.threadId, detail);
      ref.read(studioTurnProvider.notifier).fail(entry.requestId, detail);
      if (entry.taskId != null) {
        ref
            .read(agentWorkspaceProvider.notifier)
            .failTask(entry.taskId!, detail);
      }
    } else if (kind == StudioRequestLifecycleEventKind.cancelled) {
      ref
          .read(studioThreadProvider.notifier)
          .cancel(entry.threadId, message: detail);
      ref.read(studioTurnProvider.notifier).cancel(entry.requestId, detail);
      if (entry.taskId != null) {
        ref.read(agentWorkspaceProvider.notifier).cancelTask(entry.taskId!);
      }
    } else if (kind == StudioRequestLifecycleEventKind.completed) {
      ref
          .read(studioTurnProvider.notifier)
          .markProgress(
            entry.requestId,
            title: _titleFor(kind),
            detail: detail,
            status: StudioTurnStatus.completed,
          );
    }
  }

  void _scheduleWatchdogs(StudioRequestLifecycleEntry entry) {
    _scheduleSoftWatchdog(entry);
    _hardTimers[entry.requestId]?.cancel();
    _hardTimers[entry.requestId] = Timer(const Duration(minutes: 4), () {
      final current = state.active(entry.requestId);
      if (current == null) return;
      const message =
          'Request timed out after 4 minutes. Try again or check the Circuit AI connection.';
      ref.read(studioThreadProvider.notifier).fail(current.threadId, message);
      if (current.taskId != null) {
        ref
            .read(agentWorkspaceProvider.notifier)
            .failTask(current.taskId!, message);
      }
      _finish(current, StudioRequestLifecycleEventKind.failed, message);
    });
  }

  void _scheduleSoftWatchdog(StudioRequestLifecycleEntry entry) {
    _softTimers[entry.requestId]?.cancel();
    _softTimers[entry.requestId] = Timer(const Duration(seconds: 18), () {
      final current = state.active(entry.requestId);
      if (current == null) return;
      _touch(
        current,
        StudioRequestLifecycleEventKind.waitingForModel,
        detail: 'Still waiting for Circuit AI.',
      );
      ref
          .read(studioThreadProvider.notifier)
          .markPhase(
            current.threadId,
            status: StudioThreadStatus.preflighting,
            phase: StudioSendPhase.preflighting,
            requestId: current.requestId,
            model: current.model,
            contextSummary: current.contextSummary,
          );
      ref
          .read(studioTurnProvider.notifier)
          .markProgress(
            current.requestId,
            title: 'Still waiting',
            detail: 'Circuit AI has not returned output yet.',
            status: StudioTurnStatus.waitingForModel,
          );
    });
  }

  void _cancelTimers(String requestId) {
    _softTimers.remove(requestId)?.cancel();
    _hardTimers.remove(requestId)?.cancel();
  }

  void _upsertToolEvent(
    StudioRequestLifecycleEntry entry,
    ToolCallInfo tool,
    String title,
    String detail, {
    bool running = false,
  }) {
    ref
        .read(studioTurnProvider.notifier)
        .upsertTool(
          entry.requestId,
          toolCallId: tool.id,
          toolName: tool.name,
          title: title,
          detail: detail,
          filePath: studioRequestToolPath(tool),
          running: running,
        );
  }

  String _titleFor(StudioRequestLifecycleEventKind kind) => switch (kind) {
    StudioRequestLifecycleEventKind.completed => 'Completed',
    StudioRequestLifecycleEventKind.failed => 'Failed',
    StudioRequestLifecycleEventKind.cancelled => 'Cancelled',
    StudioRequestLifecycleEventKind.approvalNeeded => 'Approval needed',
    StudioRequestLifecycleEventKind.toolRunning => 'Tool activity',
    StudioRequestLifecycleEventKind.streaming => 'Streaming',
    StudioRequestLifecycleEventKind.waitingForModel => 'Still waiting',
    StudioRequestLifecycleEventKind.requestStarted => 'Request sent',
  };

  @override
  String _preview(String content) {
    final trimmed = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.length <= 180) return trimmed;
    return '${trimmed.substring(0, 177)}...';
  }
}

class _LifecycleEventBinding {
  final EventBus events;
  final Map<EventType, EventHandler> handlers;

  const _LifecycleEventBinding({required this.events, required this.handlers});

  void dispose() {
    for (final entry in handlers.entries) {
      events.off(entry.key, entry.value);
    }
  }
}

final studioRequestLifecycleProvider =
    NotifierProvider<
      StudioRequestLifecycleController,
      StudioRequestLifecycleState
    >(StudioRequestLifecycleController.new);
