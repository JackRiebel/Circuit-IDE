import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'StudioTurnStateMachine maps persisted statuses to canonical phases',
    () {
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.queued),
        StudioTurnPhase.created,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.buildingContext),
        StudioTurnPhase.retrieving,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.waitingForModel),
        StudioTurnPhase.requesting,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.streaming),
        StudioTurnPhase.streaming,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.waitingForApproval),
        StudioTurnPhase.waitingApproval,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.toolRunning),
        StudioTurnPhase.runningTool,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.reviewingPatch),
        StudioTurnPhase.reviewingPatch,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.verifying),
        StudioTurnPhase.verifying,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.completed),
        StudioTurnPhase.completed,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.failed),
        StudioTurnPhase.failed,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.cancelled),
        StudioTurnPhase.cancelled,
      );
      expect(
        StudioTurnStateMachine.phaseFor(StudioTurnStatus.interrupted),
        StudioTurnPhase.interrupted,
      );
    },
  );

  test('Studio turn update boundary rejects illegal terminal transitions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'State machine');
    final turn = container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'state-machine-request',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'state-machine-message',
          prompt: 'Check the lifecycle',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(projectLabel: 'project'),
        );
    final threads = container.read(studioThreadProvider.notifier);

    expect(
      threads.updateTurn(
        thread.id,
        turn.id,
        status: StudioTurnStatus.completed,
        complete: true,
      ),
      isTrue,
    );
    expect(
      threads.updateTurn(
        thread.id,
        turn.id,
        status: StudioTurnStatus.streaming,
      ),
      isFalse,
    );
    final persisted = container
        .read(studioThreadProvider)
        .threads
        .single
        .turns
        .single;
    expect(persisted.status, StudioTurnStatus.completed);
    expect(persisted.completedAt, isNotNull);
    expect(
      StudioTurnStateMachine.canTransition(
        StudioTurnStatus.completed,
        StudioTurnStatus.streaming,
      ),
      isFalse,
    );
  });

  test('terminal phases reject every follow-on transition', () {
    const terminal = [
      StudioTurnStatus.completed,
      StudioTurnStatus.failed,
      StudioTurnStatus.cancelled,
      StudioTurnStatus.interrupted,
    ];
    for (final from in terminal) {
      for (final to in StudioTurnStatus.values) {
        expect(
          StudioTurnStateMachine.canTransition(from, to),
          from == to,
          reason: '${from.name} must not transition to ${to.name}',
        );
      }
    }

    for (final edge in [
      (StudioTurnStatus.queued, StudioTurnStatus.buildingContext),
      (StudioTurnStatus.buildingContext, StudioTurnStatus.waitingForModel),
      (StudioTurnStatus.waitingForModel, StudioTurnStatus.streaming),
      (StudioTurnStatus.streaming, StudioTurnStatus.toolRunning),
      (StudioTurnStatus.toolRunning, StudioTurnStatus.waitingForApproval),
      (StudioTurnStatus.waitingForApproval, StudioTurnStatus.reviewingPatch),
      (StudioTurnStatus.reviewingPatch, StudioTurnStatus.verifying),
      (StudioTurnStatus.verifying, StudioTurnStatus.completed),
    ]) {
      expect(
        StudioTurnStateMachine.canTransition(edge.$1, edge.$2),
        isTrue,
        reason: '${edge.$1.name} -> ${edge.$2.name} must remain legal',
      );
    }
  });
}
