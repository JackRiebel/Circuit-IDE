import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_request.dart';

class AgentRequestController
    extends Notifier<Map<AgentRequestLane, AgentRequestState>> {
  @override
  Map<AgentRequestLane, AgentRequestState> build() {
    return {
      for (final lane in AgentRequestLane.values)
        lane: AgentRequestState(lane: lane),
    };
  }

  bool isBusy(AgentRequestLane lane) {
    final status = state[lane]?.status ?? AgentRequestStatus.idle;
    return status == AgentRequestStatus.queued ||
        status == AgentRequestStatus.running ||
        status == AgentRequestStatus.streaming ||
        status == AgentRequestStatus.cancelling;
  }

  void start({
    required AgentRequestLane lane,
    required String requestId,
    required String model,
  }) {
    state = {
      ...state,
      lane: AgentRequestState(
        lane: lane,
        status: AgentRequestStatus.running,
        requestId: requestId,
        model: model,
        startedAt: DateTime.now(),
      ),
    };
  }

  void markStreaming(AgentRequestLane lane) {
    final current = state[lane];
    if (current == null) return;
    state = {
      ...state,
      lane: current.copyWith(status: AgentRequestStatus.streaming),
    };
  }

  void requestCancel(AgentRequestLane lane) {
    final current = state[lane];
    if (current == null) return;
    state = {
      ...state,
      lane: current.copyWith(
        status: AgentRequestStatus.cancelling,
        cancelRequested: true,
      ),
    };
  }

  void finish(AgentRequestLane lane, {String? error, bool cancelled = false}) {
    final current = state[lane];
    if (current == null) return;
    state = {
      ...state,
      lane: current.copyWith(
        status: cancelled
            ? AgentRequestStatus.done
            : error == null
            ? AgentRequestStatus.done
            : AgentRequestStatus.failed,
        endedAt: DateTime.now(),
        error: error,
      ),
    };
  }
}

final agentRequestProvider =
    NotifierProvider<
      AgentRequestController,
      Map<AgentRequestLane, AgentRequestState>
    >(AgentRequestController.new);
