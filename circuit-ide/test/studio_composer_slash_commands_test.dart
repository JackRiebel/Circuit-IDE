import 'package:circuit_ide/ui/studio/studio_composer_slash_commands.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('slash-command rows expose named keyboard selection', (
    tester,
  ) async {
    final selected = <StudioSlashCommand>[];
    const command = StudioSlashCommand(
      name: 'status',
      title: 'Status',
      detail: 'Summarize project state',
      prompt: 'Summarize the current project state.',
      icon: Icons.info_outline,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioSlashCommandMenu(
              commands: const [command],
              onSelect: selected.add,
            ),
          ),
        ),
      ),
    );

    final row = find.byKey(const ValueKey('studio-slash-command-status'));
    expect(row, findsOneWidget);
    expect(
      tester.getSemantics(row),
      isSemantics(
        label: 'Use Status slash command: Summarize project state',
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(row);
    await tester.pump();
    expect(selected, [command]);
    selected.clear();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(selected, [command]);
  });
}
