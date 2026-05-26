import 'package:circuit_ide/models/command_descriptor.dart';
import 'package:circuit_ide/state/command_palette_provider.dart';
import 'package:circuit_ide/ui/command_palette/command_palette.dart';
import 'package:circuit_ide/ui/layout/tools_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Tools panel renders grouped progressive disclosure', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ToolsPanel())),
      ),
    );

    expect(find.text('Project'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('Verification'), findsOneWidget);
    expect(find.text('Integrations'), findsOneWidget);
    expect(find.text('Advanced tools'), findsNothing);
  });

  testWidgets('Command palette renders category chips', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(commandPaletteProvider.notifier).registerCommands([
      CommandDescriptor(
        id: 'ai.reconnect',
        title: 'Reconnect AI',
        category: 'AI',
        icon: Icons.power_settings_new,
        run: () {},
      ),
      CommandDescriptor(
        id: 'workspace.refresh',
        title: 'Refresh Workspace',
        category: 'Workspace',
        icon: Icons.refresh,
        run: () {},
      ),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CommandPalette())),
      ),
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
  });
}
