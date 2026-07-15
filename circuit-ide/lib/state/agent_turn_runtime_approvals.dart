part of 'agent_turn_runtime_provider.dart';

/// Scoped approval grants and their bounded, per-request lifecycle.
///
/// The runtime facade owns runner execution and terminal cleanup; this base
/// owns only the durable-in-memory approval state that may authorize a tool.
abstract class _AgentTurnRuntimeApprovalController
    extends Notifier<AgentTurnRuntimeState> {
  final _pendingApprovals = <String, ConfirmationRequest>{};
  final _approvalRequestIds = <String, String>{};
  final _approvalExpiryTimers = <String, Timer>{};
  final _turnApprovalGrantKeys = <String, String>{};

  Future<bool> _handleConfirmationNeeded(
    String requestId,
    ConfirmationRequest request,
    EventBus events,
  ) async {
    final grantKey = _turnApprovalGrantKeys[requestId];
    final requestGrantKey = _approvalGrantKeyForRequest(requestId, request);
    if (grantKey != null && grantKey == requestGrantKey) {
      events.emit(EventType.confirmationNeeded, {
        'request': request,
        'requestId': requestId,
      });
      events.emit(EventType.confirmationReceived, {
        'id': request.id,
        'approved': true,
        'requestId': requestId,
        'approvalGrant': ApprovalGrant.turn.name,
      });
      return true;
    }
    _pendingApprovals[request.id] = request;
    _approvalRequestIds[request.id] = requestId;
    _scheduleApprovalExpiry(requestId, request);
    events.emit(EventType.confirmationNeeded, {
      'request': request,
      'requestId': requestId,
    });
    final approved = await request.response;
    _clearPendingApproval(request.id);
    events.emit(EventType.confirmationReceived, {
      'id': request.id,
      'approved': approved,
      'requestId': requestId,
      if (request.isExpired) 'approvalExpired': true,
      if (approved) 'approvalGrant': request.grantedScope?.name,
    });
    return approved;
  }

  void approveOnce(String approvalId) {
    final request = _takePendingApproval(approvalId);
    if (request != null) {
      request.approve(scope: ApprovalGrant.once);
    }
  }

  void approveForTurn(String approvalId) {
    final requestId = _approvalRequestIds[approvalId];
    final request = _takePendingApproval(approvalId);
    if (requestId != null && request != null && !request.isExpired) {
      _turnApprovalGrantKeys[requestId] = _approvalGrantKeyForRequest(
        requestId,
        request,
      );
      request.approve(scope: ApprovalGrant.turn);
    } else if (request != null) {
      request.expire();
    }
  }

  void rejectApproval(String approvalId) {
    final request = _takePendingApproval(approvalId);
    if (request != null) {
      request.reject();
    }
  }

  void _scheduleApprovalExpiry(String requestId, ConfirmationRequest request) {
    _approvalExpiryTimers.remove(request.id)?.cancel();
    final delay = request.expiresAt.difference(DateTime.now());
    _approvalExpiryTimers[request.id] = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        if (_approvalRequestIds[request.id] != requestId) return;
        final pending = _takePendingApproval(request.id);
        pending?.expire();
      },
    );
  }

  ConfirmationRequest? _takePendingApproval(String approvalId) {
    _approvalExpiryTimers.remove(approvalId)?.cancel();
    _approvalRequestIds.remove(approvalId);
    return _pendingApprovals.remove(approvalId);
  }

  void _clearPendingApproval(String approvalId) {
    _approvalExpiryTimers.remove(approvalId)?.cancel();
    _approvalRequestIds.remove(approvalId);
    _pendingApprovals.remove(approvalId);
  }

  String _approvalGrantKeyForRequest(
    String requestId,
    ConfirmationRequest request,
  ) {
    final session = state.sessionFor(requestId);
    return AgentToolPermissionPolicy(
      workingDir: session?.workspaceRoot ?? Directory.systemTemp.path,
    ).approvalGrantKeyFor(request.toolCall);
  }
}
