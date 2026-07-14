import 'package:circuit_ide/models/studio_browser.dart';
import 'package:circuit_ide/theme/theme_tokens.dart';
import 'package:circuit_ide/ui/studio/studio_browser_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'browser tabs keep a visible focus ring and select with keyboard activation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final focusNode = FocusNode(debugLabel: 'test-browser-tab-focus');
      addTearDown(focusNode.dispose);
      var selectionCount = 0;
      var closeCount = 0;
      const tab = StudioBrowserTab(
        id: 'browser-tab-accessible',
        currentUrl: 'https://circuit.example/reports',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StudioBrowserTabButton(
                tab: tab,
                active: true,
                focusNode: focusNode,
                onSelect: () => selectionCount++,
                onClose: () => closeCount++,
              ),
            ),
          ),
        ),
      );

      final tabControl = find.bySemanticsLabel('circuit.example browser tab');
      expect(tabControl, findsOneWidget);
      expect(
        tester.getSemantics(tabControl),
        matchesSemantics(
          label: 'circuit.example browser tab',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      final decoration = find
          .descendant(
            of: find.byType(StudioBrowserTabButton),
            matching: find.byType(Container),
          )
          .evaluate()
          .map((element) => element.widget)
          .whereType<Container>()
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.border != null)
          .single;
      final border = decoration.border! as Border;
      expect(border.top.width, 1.5);
      expect(border.top.color, ThemeTokens.dark.outlineFocus);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      expect(selectionCount, 3);

      await tester.tap(find.bySemanticsLabel('Close circuit.example'));
      expect(closeCount, 1);
      semantics.dispose();
    },
  );
}
