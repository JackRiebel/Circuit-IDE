import 'dart:io';

import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active phase writes capture durable recovery checkpoints', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioThreadProvider.notifier);
    final thread = controller.createBlankThread(title: 'Recovery fixture');
    final timestamp = DateTime.utc(2026, 7, 11);

    for (final scenario in [
      (
        id: 'stream',
        status: StudioTurnStatus.streaming,
        intent: TurnIntent.ask,
        draft: 'partial response',
        events: const <StudioTurnEvent>[],
        results: const <ToolResultEnvelope>[],
        expectedPhase: StudioTurnPhase.streaming,
        expectedAction: StudioTurnRecoveryAction.retryTurn,
      ),
      (
        id: 'approval',
        status: StudioTurnStatus.waitingForApproval,
        intent: TurnIntent.verify,
        draft: '',
        events: [
          StudioTurnEvent(
            id: 'approval-event',
            turnId: 'approval',
            requestId: 'request-approval',
            threadId: thread.id,
            type: StudioTurnEventType.approvalRequest,
            title: 'Approval needed',
            detail: 'Run the command.',
            timestamp: timestamp,
            toolCallId: 'command-call',
            toolName: 'run_command',
            approvalId: 'approval-id',
            approvalState: ApprovalRequestState.pending,
          ),
        ],
        results: const <ToolResultEnvelope>[],
        expectedPhase: StudioTurnPhase.waitingApproval,
        expectedAction: StudioTurnRecoveryAction.rerunVerification,
      ),
      (
        id: 'verify',
        status: StudioTurnStatus.verifying,
        intent: TurnIntent.verify,
        draft: '',
        events: const <StudioTurnEvent>[],
        results: const [
          ToolResultEnvelope(
            toolCallId: 'command-run',
            toolName: 'run_command',
            status: ToolResultStatus.success,
            summary: 'Previous command completed.',
          ),
        ],
        expectedPhase: StudioTurnPhase.verifying,
        expectedAction: StudioTurnRecoveryAction.rerunVerification,
      ),
      (
        id: 'patch',
        status: StudioTurnStatus.reviewingPatch,
        intent: TurnIntent.code,
        draft: '',
        events: const <StudioTurnEvent>[],
        results: const <ToolResultEnvelope>[],
        expectedPhase: StudioTurnPhase.reviewingPatch,
        expectedAction: StudioTurnRecoveryAction.reviewPatch,
      ),
    ]) {
      final turn = StudioTurn(
        id: scenario.id,
        threadId: thread.id,
        requestId: 'request-${scenario.id}',
        userMessageId: 'message-${scenario.id}',
        prompt: 'Continue safely.',
        model: 'test-model',
        intent: scenario.intent,
        contextSummary: const StudioContextSummary(projectLabel: 'fixture'),
        status: scenario.status,
        assistantDraft: scenario.draft,
        events: scenario.events,
        toolResults: scenario.results,
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      expect(controller.upsertTurn(thread.id, turn), isTrue);
      final persisted = container
          .read(studioThreadProvider)
          .threads
          .single
          .turns
          .singleWhere((candidate) => candidate.id == scenario.id);
      final checkpoint = persisted.recoveryCheckpoint;
      expect(checkpoint, isNotNull);
      expect(checkpoint?.phase, scenario.expectedPhase);
      expect(checkpoint?.action, scenario.expectedAction);
      expect(checkpoint?.providerCursor, isNull);
    }
  });

  test('checkpoint preserves recovery context across a restart round trip', () {
    final checkpoint = StudioTurnRecoveryCheckpoint(
      phase: StudioTurnPhase.waitingApproval,
      capturedAt: DateTime.utc(2026, 7, 11),
      streamedCharacters: 37,
      completedToolCount: 2,
      pendingApprovalId: 'approval-id',
      pendingToolCallId: 'tool-id',
      pendingToolName: 'run_command',
      commandRunId: 'command-run',
      patchSetId: 'patch-id',
      action: StudioTurnRecoveryAction.rerunVerification,
    );
    final turn = StudioTurn(
      id: 'turn',
      threadId: 'thread',
      requestId: 'request',
      userMessageId: 'message',
      prompt: 'Run checks.',
      model: 'test-model',
      intent: TurnIntent.verify,
      recoveryCheckpoint: checkpoint,
      contextSummary: const StudioContextSummary(projectLabel: 'fixture'),
      status: StudioTurnStatus.interrupted,
      createdAt: DateTime.utc(2026, 7, 11),
      updatedAt: DateTime.utc(2026, 7, 11),
      completedAt: DateTime.utc(2026, 7, 11, 1),
    );

    final restored = StudioTurn.fromJson(turn.toJson());
    expect(
      restored?.recoveryCheckpoint?.phase,
      StudioTurnPhase.waitingApproval,
    );
    expect(restored?.recoveryCheckpoint?.pendingApprovalId, 'approval-id');
    expect(restored?.recoveryCheckpoint?.pendingToolName, 'run_command');
    expect(
      restored?.recoveryCheckpoint?.action,
      StudioTurnRecoveryAction.rerunVerification,
    );
  });

  test(
    'restart recovery retains checkpoints for streaming, approval, command, and verification phases',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_checkpoint_');
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory('${root.path}/project').create();
      final store = StudioThreadStore(baseDir: '${root.path}/history');
      final timestamp = DateTime.utc(2026, 7, 11);

      for (final scenario in [
        (
          id: 'stream',
          turnStatus: StudioTurnStatus.streaming,
          threadStatus: StudioThreadStatus.streaming,
          threadPhase: StudioSendPhase.streaming,
          intent: TurnIntent.ask,
          expectedPhase: StudioTurnPhase.streaming,
          expectedAction: StudioTurnRecoveryAction.retryTurn,
        ),
        (
          id: 'approval',
          turnStatus: StudioTurnStatus.waitingForApproval,
          threadStatus: StudioThreadStatus.waitingForApproval,
          threadPhase: StudioSendPhase.waitingForApproval,
          intent: TurnIntent.verify,
          expectedPhase: StudioTurnPhase.waitingApproval,
          expectedAction: StudioTurnRecoveryAction.rerunVerification,
        ),
        (
          id: 'command',
          turnStatus: StudioTurnStatus.toolRunning,
          threadStatus: StudioThreadStatus.runningCommand,
          threadPhase: StudioSendPhase.runningCommand,
          intent: TurnIntent.verify,
          expectedPhase: StudioTurnPhase.runningTool,
          expectedAction: StudioTurnRecoveryAction.rerunVerification,
        ),
        (
          id: 'verify',
          turnStatus: StudioTurnStatus.verifying,
          threadStatus: StudioThreadStatus.runningCommand,
          threadPhase: StudioSendPhase.runningCommand,
          intent: TurnIntent.verify,
          expectedPhase: StudioTurnPhase.verifying,
          expectedAction: StudioTurnRecoveryAction.rerunVerification,
        ),
      ]) {
        final active = StudioTurn(
          id: 'turn-${scenario.id}',
          threadId: 'thread-${scenario.id}',
          requestId: 'request-${scenario.id}',
          userMessageId: 'message-${scenario.id}',
          prompt: 'Resume safely.',
          model: 'test-model',
          intent: scenario.intent,
          contextSummary: StudioContextSummary(
            rootPath: project.path,
            projectLabel: 'project',
          ),
          status: scenario.turnStatus,
          assistantDraft: scenario.id == 'stream' ? 'partial reply' : '',
          createdAt: timestamp,
          updatedAt: timestamp,
        );
        final checkpointed = active.copyWith(
          recoveryCheckpoint: StudioTurnRecoveryCheckpoint.capture(active),
        );
        final thread = StudioThread(
          id: active.threadId,
          title: 'Recovery ${scenario.id}',
          status: scenario.threadStatus,
          phase: scenario.threadPhase,
          requestId: active.requestId,
          turns: [checkpointed],
          createdAt: timestamp,
          updatedAt: timestamp,
        );

        await store.save(project.path, [thread]);
        final restored = (await store.load(
          project.path,
        )).singleWhere((candidate) => candidate.id == thread.id).turns.single;
        expect(restored.status, StudioTurnStatus.interrupted);
        expect(restored.recoveryCheckpoint?.phase, scenario.expectedPhase);
        expect(restored.recoveryCheckpoint?.action, scenario.expectedAction);
        expect(restored.recoveryCheckpoint?.providerCursor, isNull);
      }
    },
  );
}
