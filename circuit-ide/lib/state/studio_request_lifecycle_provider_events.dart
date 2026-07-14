part of 'studio_request_lifecycle_provider.dart';

/// Provider diagnostics and streaming state for a Studio request.
///
/// This layer deliberately owns only provider lifecycle translation. The
/// concrete controller owns timers and event bindings, while completion owns
/// durable research evidence and final handoff. Keeping provider lifecycle
/// handling here makes terminal-provider behavior independently auditable
/// without coupling it to the request's event-bus plumbing.
abstract class _StudioRequestLifecycleProviderEventController
    extends _StudioRequestLifecycleCompletionController {
  StudioRequestLifecycleEntry? _providerEntryFor(Event event) {
    final requestId = event.data['requestId'] as String?;
    if (requestId == null) return null;
    return state.find(requestId);
  }

  void _handleProviderLifecycle(
    Event event, {
    required bool finishOnTerminalProviderDiagnostic,
  }) {
    final entry = _providerEntryFor(event);
    if (entry == null) return;
    final lifecycle = event.data['event'] as ProviderLifecycleEvent?;
    if (lifecycle == null) return;
    final rawDetail =
        lifecycle.detail ??
        switch (lifecycle.kind) {
          ProviderLifecycleEventKind.requestSent => 'Request sent to provider.',
          ProviderLifecycleEventKind.toolExposure =>
            'Runtime exposed phase-specific tools.',
          ProviderLifecycleEventKind.authFailed =>
            'Circuit authentication failed.',
          ProviderLifecycleEventKind.reconnecting =>
            'Circuit is refreshing authentication and reconnecting once.',
          ProviderLifecycleEventKind.connected => 'Provider connected.',
          ProviderLifecycleEventKind.firstByte =>
            'Circuit AI started responding.',
          ProviderLifecycleEventKind.noFirstByte =>
            'Circuit AI returned no response bytes.',
          ProviderLifecycleEventKind.firstTextDelta =>
            'Circuit AI started writing.',
          ProviderLifecycleEventKind.firstToolDelta =>
            'Circuit AI started a tool call.',
          ProviderLifecycleEventKind.nonSseJson =>
            'Circuit returned a non-streaming JSON response.',
          ProviderLifecycleEventKind.jsonFallback =>
            'Circuit returned a non-streaming response.',
          ProviderLifecycleEventKind.toolOnly =>
            'Circuit returned tool calls without assistant text.',
          ProviderLifecycleEventKind.noTextOrTool =>
            'Circuit returned no assistant text or tool calls.',
          ProviderLifecycleEventKind.unavailableTool =>
            'Circuit requested a tool that is not available in this mode.',
          ProviderLifecycleEventKind.rateLimited =>
            'Circuit API rate limit reached.',
          ProviderLifecycleEventKind.malformedChunk =>
            'Circuit returned a malformed stream chunk.',
          ProviderLifecycleEventKind.malformedBytes =>
            'Circuit returned malformed response bytes.',
          ProviderLifecycleEventKind.streamEndedWithoutDone =>
            'Circuit stream ended without a completion marker.',
          ProviderLifecycleEventKind.outcomeRepair =>
            'Circuit is repairing an invalid draft response.',
          ProviderLifecycleEventKind.outcomeRejected =>
            'Circuit produced an invalid draft response.',
          ProviderLifecycleEventKind.completed => 'Provider completed.',
          ProviderLifecycleEventKind.failed => 'Provider failed.',
          ProviderLifecycleEventKind.cancelled => 'Provider request cancelled.',
          ProviderLifecycleEventKind.timeout => 'Provider request timed out.',
        };
    final detail = switch (lifecycle.kind) {
      ProviderLifecycleEventKind.noTextOrTool
          when !rawDetail.toLowerCase().contains('without text') =>
        '$rawDetail Completed without text or tool calls.',
      _ => rawDetail,
    };
    // An outcome rejection is a runtime diagnostic, not a terminal turn
    // transition. The turn runtime decides whether it can repair/revise the
    // proposal or must fail the request after inspecting the complete result.
    final lifecycleEventKind = switch (lifecycle.kind) {
      ProviderLifecycleEventKind.firstTextDelta =>
        StudioRequestLifecycleEventKind.streaming,
      ProviderLifecycleEventKind.firstToolDelta =>
        StudioRequestLifecycleEventKind.toolRunning,
      ProviderLifecycleEventKind.toolOnly =>
        StudioRequestLifecycleEventKind.toolRunning,
      ProviderLifecycleEventKind.toolExposure =>
        StudioRequestLifecycleEventKind.waitingForModel,
      ProviderLifecycleEventKind.completed =>
        StudioRequestLifecycleEventKind.completed,
      ProviderLifecycleEventKind.outcomeRejected =>
        StudioRequestLifecycleEventKind.toolRunning,
      ProviderLifecycleEventKind.failed =>
        StudioRequestLifecycleEventKind.failed,
      ProviderLifecycleEventKind.authFailed =>
        StudioRequestLifecycleEventKind.failed,
      ProviderLifecycleEventKind.cancelled =>
        StudioRequestLifecycleEventKind.cancelled,
      ProviderLifecycleEventKind.timeout =>
        StudioRequestLifecycleEventKind.failed,
      ProviderLifecycleEventKind.noFirstByte =>
        StudioRequestLifecycleEventKind.failed,
      ProviderLifecycleEventKind.noTextOrTool =>
        StudioRequestLifecycleEventKind.failed,
      ProviderLifecycleEventKind.unavailableTool =>
        StudioRequestLifecycleEventKind.failed,
      ProviderLifecycleEventKind.rateLimited =>
        StudioRequestLifecycleEventKind.failed,
      ProviderLifecycleEventKind.malformedBytes =>
        StudioRequestLifecycleEventKind.failed,
      ProviderLifecycleEventKind.streamEndedWithoutDone =>
        StudioRequestLifecycleEventKind.failed,
      _ => StudioRequestLifecycleEventKind.waitingForModel,
    };
    final terminalProviderEvent =
        lifecycleEventKind == StudioRequestLifecycleEventKind.failed ||
        lifecycleEventKind == StudioRequestLifecycleEventKind.cancelled;
    final isActive = state.active(entry.requestId) != null;
    if (!isActive) {
      if (_canRecordArchivedProviderDiagnostic(
        entry,
        lifecycleEventKind: lifecycleEventKind,
      )) {
        ref
            .read(studioTurnProvider.notifier)
            .addProviderDiagnostic(entry.requestId, lifecycle);
      }
      return;
    }
    ref
        .read(studioTurnProvider.notifier)
        .addProviderDiagnostic(entry.requestId, lifecycle);
    if (terminalProviderEvent && finishOnTerminalProviderDiagnostic) {
      _finish(entry, lifecycleEventKind, detail);
    } else {
      _touch(entry, lifecycleEventKind, detail: detail);
    }
    final progressStatus = switch (lifecycle.kind) {
      ProviderLifecycleEventKind.firstTextDelta => StudioTurnStatus.streaming,
      ProviderLifecycleEventKind.firstToolDelta => StudioTurnStatus.toolRunning,
      ProviderLifecycleEventKind.toolOnly => StudioTurnStatus.toolRunning,
      ProviderLifecycleEventKind.toolExposure =>
        StudioTurnStatus.waitingForModel,
      ProviderLifecycleEventKind.completed => null,
      ProviderLifecycleEventKind.authFailed => StudioTurnStatus.failed,
      ProviderLifecycleEventKind.failed => StudioTurnStatus.failed,
      ProviderLifecycleEventKind.cancelled => StudioTurnStatus.cancelled,
      ProviderLifecycleEventKind.timeout => StudioTurnStatus.failed,
      ProviderLifecycleEventKind.noFirstByte => StudioTurnStatus.failed,
      ProviderLifecycleEventKind.noTextOrTool => StudioTurnStatus.failed,
      ProviderLifecycleEventKind.unavailableTool => StudioTurnStatus.failed,
      ProviderLifecycleEventKind.rateLimited => StudioTurnStatus.failed,
      ProviderLifecycleEventKind.malformedChunk =>
        StudioTurnStatus.waitingForModel,
      ProviderLifecycleEventKind.malformedBytes => StudioTurnStatus.failed,
      ProviderLifecycleEventKind.streamEndedWithoutDone =>
        StudioTurnStatus.failed,
      ProviderLifecycleEventKind.outcomeRepair =>
        StudioTurnStatus.waitingForModel,
      ProviderLifecycleEventKind.outcomeRejected =>
        StudioTurnStatus.toolRunning,
      _ => StudioTurnStatus.waitingForModel,
    };
    final isResearchSourceRepair =
        lifecycle.kind == ProviderLifecycleEventKind.outcomeRepair &&
        (_turnForRequest(
              entry.requestId,
            )?.steps.any((step) => step.step == TurnStep.researchPlan) ??
            false);
    ref
        .read(studioTurnProvider.notifier)
        .markProgress(
          entry.requestId,
          title: isResearchSourceRepair
              ? 'Retrying source acquisition'
              : _providerProgressTitle(lifecycle.kind),
          detail: isResearchSourceRepair
              ? 'Checking one more approved source path before finalizing evidence.'
              : detail,
          status: progressStatus,
        );
  }

  String _providerProgressTitle(ProviderLifecycleEventKind kind) {
    return switch (kind) {
      ProviderLifecycleEventKind.requestSent => 'Provider request sent',
      ProviderLifecycleEventKind.toolExposure => 'Tools scoped for turn',
      ProviderLifecycleEventKind.authFailed => 'Authentication failed',
      ProviderLifecycleEventKind.reconnecting => 'Refreshing authentication',
      ProviderLifecycleEventKind.connected => 'Provider connected',
      ProviderLifecycleEventKind.firstByte => 'Provider responding',
      ProviderLifecycleEventKind.noFirstByte => 'No provider bytes',
      ProviderLifecycleEventKind.firstTextDelta => 'Streaming response',
      ProviderLifecycleEventKind.firstToolDelta => 'Tool call started',
      ProviderLifecycleEventKind.nonSseJson => 'Non-streaming response',
      ProviderLifecycleEventKind.jsonFallback => 'JSON fallback',
      ProviderLifecycleEventKind.toolOnly => 'Tool-only response',
      ProviderLifecycleEventKind.noTextOrTool => 'No model output',
      ProviderLifecycleEventKind.unavailableTool => 'Unavailable tool',
      ProviderLifecycleEventKind.rateLimited => 'Rate limited',
      ProviderLifecycleEventKind.malformedChunk => 'Malformed stream chunk',
      ProviderLifecycleEventKind.malformedBytes => 'Malformed response bytes',
      ProviderLifecycleEventKind.streamEndedWithoutDone => 'Stream ended early',
      ProviderLifecycleEventKind.outcomeRepair => 'Repairing response',
      ProviderLifecycleEventKind.outcomeRejected => 'Invalid model outcome',
      ProviderLifecycleEventKind.completed => 'Provider completed',
      ProviderLifecycleEventKind.failed => 'Provider failed',
      ProviderLifecycleEventKind.cancelled => 'Provider cancelled',
      ProviderLifecycleEventKind.timeout => 'Provider timed out',
    };
  }

  bool _canRecordArchivedProviderDiagnostic(
    StudioRequestLifecycleEntry entry, {
    required StudioRequestLifecycleEventKind lifecycleEventKind,
  }) {
    final archivedKind = state.recentRequests[entry.requestId]?.lastEventKind;
    return switch (archivedKind) {
      StudioRequestLifecycleEventKind.failed =>
        lifecycleEventKind == StudioRequestLifecycleEventKind.failed,
      StudioRequestLifecycleEventKind.cancelled =>
        lifecycleEventKind == StudioRequestLifecycleEventKind.cancelled,
      _ => false,
    };
  }

  void _touch(
    StudioRequestLifecycleEntry entry,
    StudioRequestLifecycleEventKind kind, {
    String? detail,
  });
}
