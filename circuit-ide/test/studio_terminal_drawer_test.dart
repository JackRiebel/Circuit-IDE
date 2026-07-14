import 'package:circuit_ide/models/command_run.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/state/command_run_provider.dart';
import 'package:circuit_ide/state/studio_right_drawer_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_terminal_drawer.dart';
import 'package:circuit_ide/theme/theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Terminal command rows are semantic, focused, and keyboard selectable',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final timestamp = DateTime.utc(2026, 7, 14, 15);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Terminal evidence');
      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(
            thread.id,
            StudioTurn(
              id: 'terminal-turn',
              threadId: thread.id,
              requestId: 'terminal-request',
              userMessageId: 'terminal-message',
              prompt: 'Run focused verification.',
              model: 'test-model',
              contextSummary: const StudioContextSummary(
                projectLabel: 'Fixture',
              ),
              status: StudioTurnStatus.streaming,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
            select: true,
          );
      await tester.pump(const Duration(seconds: 1));
      final commands = container.read(commandRunProvider.notifier);
      commands.start(
        id: 'terminal-command-one',
        command: 'flutter test test/one_test.dart',
        requestId: 'terminal-request',
        turnId: 'terminal-turn',
        taskId: thread.taskId,
      );
      commands.append(
        'terminal-command-one',
        CommandRunEventType.stdout,
        'First focused verification is running.',
      );
      commands.start(
        id: 'terminal-command-two',
        command: 'flutter test test/two_test.dart',
        requestId: 'terminal-request',
        turnId: 'terminal-turn',
        taskId: thread.taskId,
      );
      commands.append(
        'terminal-command-two',
        CommandRunEventType.stdout,
        'Second focused verification is running.',
      );
      final drawer = container.read(studioRightDrawerProvider.notifier);
      drawer.openCommand('terminal-command-one');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: StudioTerminalDrawer()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final secondRow = find.byKey(
        const ValueKey('studio-terminal-command-terminal-command-two'),
      );
      expect(secondRow, findsOneWidget);
      expect(
        tester.getSemantics(secondRow),
        isSemantics(
          label: 'Open running command: flutter test test/two_test.dart',
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(secondRow);
      await tester.pump();
      expect(
        container.read(studioRightDrawerProvider).commandRunId,
        'terminal-command-two',
      );

      drawer.openCommand('terminal-command-one');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(
        container.read(studioRightDrawerProvider).commandRunId,
        'terminal-command-two',
      );

      final focusedContainer = find
          .descendant(of: secondRow, matching: find.byType(Container))
          .first;
      final decoration =
          tester.widget<Container>(focusedContainer).decoration!
              as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.width, 1.5);
      expect(border.top.color, ThemeTokens.dark.outlineFocus);
    },
  );
}
