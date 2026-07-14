import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_task_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  StudioThreadController.debugPersistDebounceOverride = Duration.zero;
  tearDownAll(() {
    StudioThreadController.debugPersistDebounceOverride = null;
  });

  testWidgets('live transcript output follows the tail when already at tail', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final turn = _seedTranscript(container);

    await _pumpTaskView(tester, container);
    final position = _transcriptPosition(tester);
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));

    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          turn.threadId,
          turn.copyWith(
            status: StudioTurnStatus.streaming,
            assistantDraft: _longStreamingDraft,
            updatedAt: DateTime(2026, 1, 1, 0, 5),
          ),
          select: true,
        );
    await tester.pump();
    await tester.pump();

    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
  });

  testWidgets(
    'live transcript output preserves a historical reading position',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final turn = _seedTranscript(container);

      await _pumpTaskView(tester, container);
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, 420));
      await tester.pumpAndSettle();
      final position = _transcriptPosition(tester);
      final heldOffset = position.pixels;
      expect(heldOffset, lessThan(position.maxScrollExtent - 80));

      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(
            turn.threadId,
            turn.copyWith(
              status: StudioTurnStatus.streaming,
              assistantDraft: _longStreamingDraft,
              updatedAt: DateTime(2026, 1, 1, 0, 5),
            ),
            select: true,
          );
      await tester.pump();
      await tester.pump();

      expect(position.pixels, closeTo(heldOffset, 1));
      expect(position.pixels, lessThan(position.maxScrollExtent - 80));
    },
  );
}

Future<void> _pumpTaskView(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 900, height: 560, child: StudioTaskView()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _transcriptPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

StudioTurn _seedTranscript(ProviderContainer container) {
  final thread = container
      .read(studioThreadProvider.notifier)
      .createBlankThread(title: 'Scroll anchor task');
  late StudioTurn latest;
  for (var index = 0; index < 16; index++) {
    final timestamp = DateTime(2026, 1, 1, 0, index);
    final turn = StudioTurn(
      id: 'scroll-turn-$index',
      threadId: thread.id,
      requestId: 'scroll-request-$index',
      userMessageId: 'scroll-message-$index',
      prompt: 'Review transcript item $index.',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.userMessage(
          id: 'scroll-message-$index',
          turnId: 'scroll-turn-$index',
          requestId: 'scroll-request-$index',
          threadId: thread.id,
          content: 'Review transcript item $index.',
          timestamp: timestamp,
        ),
        StudioTurnEvent.assistantMessage(
          turnId: 'scroll-turn-$index',
          requestId: 'scroll-request-$index',
          threadId: thread.id,
          content:
              'Completed transcript item $index with a concise, reviewable result.',
          timestamp: timestamp.add(const Duration(seconds: 1)),
        ),
      ],
      createdAt: timestamp,
      updatedAt: timestamp.add(const Duration(seconds: 1)),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);
    latest = turn;
  }
  return latest;
}

const _longStreamingDraft =
    'Live output keeps growing while Circuit verifies the implementation. '
    'This deliberately spans several transcript lines so tail-follow and '
    'historical reading-position behavior can be observed independently.';
