import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/tool_result_envelope.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/models/agent_tool_permission.dart';
import 'package:circuit_ide/models/confirmation_request.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:circuit_ide/ui/studio/studio_task_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StudioThreadController.debugPersistDebounceOverride = Duration.zero;
  tearDownAll(() {
    StudioThreadController.debugPersistDebounceOverride = null;
  });

  StudioTurn turn({
    required StudioTurnStatus status,
    TurnIntent intent = TurnIntent.ask,
    List<StudioTurnEvent> events = const [],
    List<TurnStepRecord> steps = const [],
    List<ToolResultEnvelope> toolResults = const [],
    String? lastError,
  }) {
    final now = DateTime(2026, 7, 10);
    return StudioTurn(
      id: 'turn-${status.name}-${intent.name}',
      threadId: 'thread',
      requestId: 'request',
      userMessageId: 'message',
      prompt: 'Do the work',
      model: 'gpt-5-nano',
      intent: intent,
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: status,
      events: events,
      steps: steps,
      toolResults: toolResults,
      createdAt: now,
      updatedAt: now,
      completedAt: switch (status) {
        StudioTurnStatus.completed ||
        StudioTurnStatus.failed ||
        StudioTurnStatus.cancelled ||
        StudioTurnStatus.interrupted => now,
        _ => null,
      },
      lastError: lastError,
    );
  }

  test('terminal outcomes are typed and persist independently of prose', () {
    final applied = turn(
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.completionSummary(
          turnId: 'turn',
          requestId: 'request',
          threadId: 'thread',
          title: 'Applied changes',
          detail: 'Provider prose cannot be the outcome authority.',
          timestamp: DateTime(2026, 7, 10),
        ),
      ],
    );
    final artifact = turn(
      status: StudioTurnStatus.completed,
      toolResults: const [
        ToolResultEnvelope(
          toolCallId: 'artifact',
          toolName: 'write_artifact',
          status: ToolResultStatus.success,
          summary: 'Created report.',
          artifacts: ['report.pdf'],
        ),
      ],
    );

    expect(
      inferStudioTurnOutcome(turn(status: StudioTurnStatus.completed)),
      StudioTurnOutcome.answered,
    );
    for (final intent in const [
      TurnIntent.chat,
      TurnIntent.ask,
      TurnIntent.code,
      TurnIntent.review,
    ]) {
      expect(
        inferStudioTurnOutcome(
          turn(status: StudioTurnStatus.completed, intent: intent),
        ),
        StudioTurnOutcome.answered,
        reason: '${intent.name} completions have a typed outcome.',
      );
    }
    expect(
      inferStudioTurnOutcome(
        turn(status: StudioTurnStatus.completed, intent: TurnIntent.plan),
      ),
      StudioTurnOutcome.preparedChanges,
    );
    expect(
      inferStudioTurnOutcome(applied),
      StudioTurnOutcome.answered,
      reason: 'Provider prose must not control the final outcome.',
    );
    expect(
      inferStudioTurnOutcome(
        turn(status: StudioTurnStatus.completed, intent: TurnIntent.verify),
      ),
      StudioTurnOutcome.verified,
    );
    expect(inferStudioTurnOutcome(artifact), StudioTurnOutcome.createdArtifact);
    expect(
      inferStudioTurnOutcome(
        turn(
          status: StudioTurnStatus.failed,
          toolResults: const [
            ToolResultEnvelope(
              toolCallId: 'denied-tool',
              toolName: 'run_command',
              status: ToolResultStatus.denied,
              summary: 'Denied by policy.',
            ),
          ],
        ),
      ),
      StudioTurnOutcome.blocked,
    );
    expect(
      inferStudioTurnOutcome(
        turn(status: StudioTurnStatus.failed, lastError: 'Command blocked.'),
      ),
      StudioTurnOutcome.failed,
      reason: 'Provider error prose is not outcome authority.',
    );
    expect(
      inferStudioTurnOutcome(turn(status: StudioTurnStatus.failed)),
      StudioTurnOutcome.failed,
    );
    expect(
      inferStudioTurnOutcome(turn(status: StudioTurnStatus.cancelled)),
      StudioTurnOutcome.cancelled,
    );

    final persisted = applied.copyWith(
      finalOutcome: StudioTurnOutcome.appliedChanges,
    );
    expect(
      StudioTurn.fromJson(persisted.toJson())!.finalOutcome,
      StudioTurnOutcome.appliedChanges,
    );
  });

  test(
    'Studio terminal controller writes an outcome for success, failure, and cancellation',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Outcome contract');
      final turns = container.read(studioTurnProvider.notifier);

      final answered = turns.registerTurn(
        requestId: 'answered',
        threadId: thread.id,
        taskId: null,
        userMessageId: 'answered-message',
        prompt: 'Explain this',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        intent: TurnIntent.ask,
      );
      turns.complete('answered', content: 'Here is the answer.');

      final blocked = turns.registerTurn(
        requestId: 'blocked',
        threadId: thread.id,
        taskId: null,
        userMessageId: 'blocked-message',
        prompt: 'Run an unsafe command',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
        intent: TurnIntent.verify,
      );
      turns.fail(
        'blocked',
        'Command blocked by the verification policy.',
        finalOutcome: StudioTurnOutcome.blocked,
      );

      final cancelled = turns.registerTurn(
        requestId: 'cancelled',
        threadId: thread.id,
        taskId: null,
        userMessageId: 'cancelled-message',
        prompt: 'Stop this request',
        model: 'gpt-5-nano',
        contextSummary: const StudioContextSummary(projectLabel: 'project'),
      );
      turns.cancel('cancelled', 'Cancelled by the user.');

      final persisted = container
          .read(studioThreadProvider)
          .threads
          .single
          .turns;
      StudioTurn byId(String id) =>
          persisted.firstWhere((candidate) => candidate.id == id);
      expect(byId(answered.id).finalOutcome, StudioTurnOutcome.answered);
      expect(byId(blocked.id).finalOutcome, StudioTurnOutcome.blocked);
      expect(byId(cancelled.id).finalOutcome, StudioTurnOutcome.cancelled);
    },
  );

  test('direct terminal writes receive a durable typed outcome', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Direct terminal outcome');
    final direct = turn(
      status: StudioTurnStatus.completed,
    ).copyWith(status: StudioTurnStatus.completed);

    expect(
      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(thread.id, direct),
      isTrue,
    );
    final stored = container
        .read(studioThreadProvider)
        .selectedThread!
        .turns
        .single;
    expect(stored.finalOutcome, StudioTurnOutcome.answered);
  });

  test('approval scope is durable and separate from approval state', () {
    final expiresAt = DateTime.now().add(const Duration(minutes: 5));
    final request = ConfirmationRequest(
      id: 'approval',
      toolCall: const ToolCallInfo(
        id: 'tool',
        name: 'run_command',
        arguments: {'command': 'flutter test'},
      ),
      preview: 'Run flutter test',
      warnings: const ['Tests may take several minutes.'],
      risk: ToolPermissionReason.commandRequiresReview,
      normalizedAction: 'command:test:9a4e2f',
      timestamp: expiresAt.subtract(const Duration(minutes: 5)),
      expiresAt: expiresAt,
    )..approve(scope: ApprovalGrant.turn);
    final event = StudioTurnEvent.approval(
      turnId: 'turn',
      requestId: 'request',
      threadId: 'thread',
      request: request,
      state: ApprovalRequestState.approved,
    );

    final restored = StudioTurnEvent.fromJson(event.toJson());

    expect(restored?.approvalState, ApprovalRequestState.approved);
    expect(restored?.approvalGrant, ApprovalGrant.turn);
    expect(restored?.approvalRisk, ToolPermissionReason.commandRequiresReview);
    expect(restored?.approvalNormalizedAction, 'command:test:9a4e2f');
    expect(restored?.approvalExpiresAt, expiresAt);
  });

  test(
    'expired approval fails closed and cannot be promoted to turn scope',
    () async {
      final request = ConfirmationRequest(
        id: 'expired-approval',
        toolCall: const ToolCallInfo(
          id: 'expired-tool',
          name: 'run_command',
          arguments: {'command': 'flutter test'},
        ),
        preview: 'Run flutter test',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );

      request.approve(scope: ApprovalGrant.turn);

      expect(await request.response, isFalse);
      expect(request.isExpired, isTrue);
      expect(request.grantedScope, isNull);
    },
  );

  testWidgets(
    'Studio transcript renders the typed outcome over provider prose',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Typed outcome transcript');
      final typed = turn(
        status: StudioTurnStatus.completed,
        events: [
          StudioTurnEvent.completionSummary(
            turnId: 'turn-completed-ask',
            requestId: 'request',
            threadId: thread.id,
            title: 'Provider summary',
            detail: 'The provider prose is supporting evidence only.',
            timestamp: DateTime(2026, 7, 10),
          ),
        ],
      ).copyWith(finalOutcome: StudioTurnOutcome.appliedChanges);
      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(thread.id, typed, select: true);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
        ),
      );

      expect(find.text('Applied changes'), findsOneWidget);
      expect(
        find.text(
          'Changes were applied. Review the patch or run verification next.',
        ),
        findsOneWidget,
      );
    },
  );
}
