import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_message_sender.dart';
import 'package:circuit_ide/ui/studio/studio_task_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compaction preserves source links and typed work facts', () {
    final turns = List.generate(7, (index) => _turn(index));

    final compaction = buildStudioConversationCompaction(turns);

    expect(compaction, isNotNull);
    expect(compaction!.sourceTurnIds, ['turn-0', 'turn-1', 'turn-2']);
    expect(compaction.summary, contains('Read-only compact history'));
    expect(compaction.summary, contains('user request or preference: Task 1'));
    expect(compaction.summary, contains('Accepted plan: Update startup flow'));
    expect(compaction.summary, contains('lib/startup.dart (applied)'));
    expect(compaction.summary, contains('Unresolved: Network request failed.'));
    expect(compaction.sourceTokenEstimate, greaterThan(0));
  });

  test('active compaction replaces only source turns in model history', () {
    final turns = List.generate(7, (index) => _turn(index));
    final compaction = buildStudioConversationCompaction(turns)!;
    final thread = StudioThread(
      id: 'thread',
      title: 'Compaction',
      turns: turns,
      conversationCompactions: [compaction],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    final history = studioModelHistoryForThread(thread);

    expect(
      history.first.content,
      contains('read-only conversation compaction'),
    );
    expect(history.map((message) => message.id), isNot(contains('message-1')));
    expect(history.map((message) => message.id), contains('message-3'));
    expect(history.map((message) => message.id), contains('message-6'));
  });

  test('restoring compaction returns source turns to model history', () {
    final turns = List.generate(7, (index) => _turn(index));
    final compaction = buildStudioConversationCompaction(turns)!;
    final thread = StudioThread(
      id: 'thread',
      title: 'Compaction',
      turns: turns,
      conversationCompactions: [compaction.copyWith(restored: true)],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    final history = studioModelHistoryForThread(thread);

    expect(history.map((message) => message.id), contains('message-1'));
    expect(
      history.map((message) => message.content),
      isNot(contains(contains('read-only conversation compaction'))),
    );
  });

  test('thread provider creates and restores durable compaction state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(studioThreadProvider.notifier);
    final thread = notifier.createBlankThread(title: 'Compaction');
    for (var index = 0; index < 7; index++) {
      expect(
        notifier.upsertTurn(thread.id, _turn(index, threadId: thread.id)),
        isTrue,
      );
    }
    final compacted = container.read(studioThreadProvider).selectedThread!;
    expect(compacted.conversationCompactions, hasLength(1));
    final initialCompaction = compacted.conversationCompactions.single;
    expect(initialCompaction.sourceTurnIds, ['turn-0', 'turn-1', 'turn-2']);

    for (var index = 7; index < 10; index++) {
      expect(
        notifier.upsertTurn(thread.id, _turn(index, threadId: thread.id)),
        isTrue,
      );
    }
    final expanded = container.read(studioThreadProvider).selectedThread!;
    expect(expanded.conversationCompactions, hasLength(1));
    final compaction = expanded.conversationCompactions.single;
    expect(compaction.restored, isFalse);
    expect(compaction.sourceTurnIds, [
      'turn-0',
      'turn-1',
      'turn-2',
      'turn-3',
      'turn-4',
      'turn-5',
    ]);

    expect(
      notifier.restoreConversationCompaction(thread.id, compaction.id),
      isTrue,
    );
    final restored = container.read(studioThreadProvider).selectedThread!;
    expect(restored.conversationCompactions.single.restored, isTrue);

    final encoded = restored.toJson();
    final decoded = StudioThread.fromJson(encoded)!;
    expect(
      decoded.conversationCompactions.single.sourceTurnIds,
      compaction.sourceTurnIds,
    );
    expect(decoded.conversationCompactions.single.restored, isTrue);
  });

  testWidgets('transcript lets users inspect and restore compacted turns', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(studioThreadProvider.notifier);
    final thread = notifier.createBlankThread(title: 'Compaction');
    for (var index = 0; index < 7; index++) {
      notifier.upsertTurn(thread.id, _turn(index, threadId: thread.id));
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );
    await tester.pump();

    expect(find.text('Older conversation compacted'), findsOneWidget);
    await tester.tap(find.text('Older conversation compacted'));
    await tester.pump();
    expect(find.text('Restore source turns to model history'), findsOneWidget);

    final restoreButton = find.widgetWithText(
      TextButton,
      'Restore source turns to model history',
    );
    tester.widget<TextButton>(restoreButton).onPressed!.call();
    await tester.pump();
    expect(
      container
          .read(studioThreadProvider)
          .selectedThread!
          .conversationCompactions
          .single
          .restored,
      isTrue,
    );
    expect(find.text('Historical turns restored'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}

StudioTurn _turn(int index, {String threadId = 'thread'}) {
  final now = DateTime.utc(2026, 7, 1).add(Duration(minutes: index));
  return StudioTurn(
    id: 'turn-$index',
    threadId: threadId,
    requestId: 'request-$index',
    userMessageId: 'message-$index',
    prompt: 'Task $index',
    model: 'gpt-5',
    contextSummary: const StudioContextSummary(projectLabel: 'project'),
    status: index == 2 ? StudioTurnStatus.failed : StudioTurnStatus.completed,
    acceptedPlanContext: index == 0
        ? const AcceptedPlanContext(
            patchSetId: 'patch-startup',
            title: 'Startup',
            summary: 'Update startup flow',
            markdown: '',
          )
        : null,
    planTargetProgress: index == 0
        ? [
            PlanTargetProgress(
              path: 'lib/startup.dart',
              intent: 'Update startup',
              operation: ProposedFileEditType.modify,
              state: PlanTargetProgressState.applied,
              updatedAt: now,
            ),
          ]
        : const [],
    createdAt: now,
    updatedAt: now,
    completedAt: now,
    lastError: index == 2 ? 'Network request failed.' : null,
  );
}
