import 'package:circuit_ide/models/artifact_template.dart';
import 'package:circuit_ide/ui/studio/artifact_template_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('template selector previews and returns the selected template', (
    tester,
  ) async {
    ArtifactTemplate? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                selection = await showArtifactTemplateSelector(
                  context,
                  selectedTemplateId: 'circuit-standard',
                );
              },
              child: const Text('Choose template'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Choose template'));
    await tester.pumpAndSettle();

    expect(find.text('Choose artifact template'), findsOneWidget);
    expect(find.text('Circuit standard'), findsOneWidget);
    expect(find.text('Customer briefing'), findsOneWidget);
    expect(find.text('Executive review'), findsOneWidget);
    expect(find.text('CONFIDENTIAL'), findsOneWidget);
    expect(find.text('RESTRICTED'), findsOneWidget);

    final customerCard = find.byKey(
      const ValueKey('artifact-template-card-customer-briefing'),
    );
    expect(customerCard, findsOneWidget);
    tester.widget<Focus>(customerCard).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Customer briefing template')),
      isSemantics(isSelected: true),
    );
    await tester.tap(find.text('Create styled version'));
    await tester.pumpAndSettle();

    expect(selection?.id, 'customer-briefing');
    expect(selection?.footerText, contains('Prepared by CircuitCode'));
  });

  testWidgets('template selector retains its reviewed visual layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showArtifactTemplateSelector(
                context,
                selectedTemplateId: 'customer-briefing',
              ),
              child: const Text('Choose template'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Choose template'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/artifact_template_selector.png'),
    );
  });
}
