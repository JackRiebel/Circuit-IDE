import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/theme/theme_tokens.dart';
import 'package:circuit_ide/ui/studio/studio_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Home recent tasks have durable semantics and keyboard selection',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Review the release evidence');
      await tester.pump(const Duration(seconds: 1));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudioHome())),
        ),
      );
      await tester.pumpAndSettle();

      final recentTask = find.byKey(
        ValueKey('studio-home-recent-thread-${thread.id}'),
      );
      expect(recentTask, findsOneWidget);
      expect(
        tester.getSemantics(recentTask),
        isSemantics(
          label: 'Open Review the release evidence, Ready recent task',
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(recentTask);
      await tester.pump();
      expect(container.read(studioShellProvider).mode, StudioMode.task);
      expect(container.read(studioThreadProvider).selectedThreadId, thread.id);

      container.read(studioShellProvider.notifier).openHome();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(container.read(studioShellProvider).mode, StudioMode.task);
      expect(container.read(studioThreadProvider).selectedThreadId, thread.id);

      final focusedContainer = find
          .descendant(of: recentTask, matching: find.byType(Container))
          .first;
      final decoration =
          tester.widget<Container>(focusedContainer).decoration!
              as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.width, 1.5);
      expect(border.top.color, ThemeTokens.dark.outlineFocus);

      final starterSuggestion = find.byKey(
        const ValueKey(
          'studio-home-suggestion-Open a project and explain the codebase',
        ),
      );
      expect(starterSuggestion, findsNothing);
    },
  );

  testWidgets('Home starter suggestions expose named keyboard actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: StudioHome())),
      ),
    );
    await tester.pumpAndSettle();

    final suggestion = find.byKey(
      const ValueKey(
        'studio-home-suggestion-Open a project and explain the codebase',
      ),
    );
    expect(suggestion, findsOneWidget);
    expect(
      tester.getSemantics(suggestion),
      isSemantics(
        label: 'Use suggestion: Open a project and explain the codebase',
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });
}
