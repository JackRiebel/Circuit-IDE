import 'package:circuit_ide/ui/project/project_cockpit_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Project Cockpit renders a no-workspace state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ProjectCockpitPanel())),
      ),
    );

    expect(find.text('Project Cockpit'), findsOneWidget);
    expect(find.textContaining('Open a folder'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });
}
