import 'package:circuit_ide/core/commands/core_command_registry.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/command_descriptor.dart';
import 'package:circuit_ide/state/command_palette_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Command palette filters by category, title, and description', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(commandPaletteProvider.notifier).registerCommands([
      CommandDescriptor(
        id: 'workspace.refresh',
        title: 'Refresh Workspace',
        description: 'Refresh the lightweight file index',
        category: 'Workspace',
        icon: Icons.refresh,
        run: () {},
      ),
      CommandDescriptor(
        id: 'ai.reconnect',
        title: 'Reconnect AI',
        category: 'AI',
        icon: Icons.power_settings_new,
        run: () {},
      ),
    ]);

    container.read(commandPaletteProvider.notifier).filter('file index');
    expect(
      container.read(commandPaletteProvider).filteredCommands.single.id,
      'workspace.refresh',
    );

    container.read(commandPaletteProvider.notifier).filter('ai');
    expect(
      container.read(commandPaletteProvider).filteredCommands.map((c) => c.id),
      contains('ai.reconnect'),
    );
  });

  test('Command palette supports category filters and recent commands', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var ran = false;
    final refresh = CommandDescriptor(
      id: 'workspace.refresh',
      title: 'Refresh Workspace',
      category: 'Workspace',
      icon: Icons.refresh,
      run: () => ran = true,
    );
    final reconnect = CommandDescriptor(
      id: 'ai.reconnect',
      title: 'Reconnect AI',
      category: 'AI',
      icon: Icons.power_settings_new,
      run: () {},
    );

    container.read(commandPaletteProvider.notifier).registerCommands([
      refresh,
      reconnect,
    ]);
    container.read(commandPaletteProvider.notifier).setCategory('AI');

    expect(
      container.read(commandPaletteProvider).filteredCommands.single.id,
      'ai.reconnect',
    );

    container.read(commandPaletteProvider.notifier).execute(refresh);

    expect(ran, isTrue);
    expect(
      container.read(commandPaletteProvider).recentCommands.single.id,
      'workspace.refresh',
    );
  });

  testWidgets(
    'Core Studio command registry quarantines legacy runtime commands',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              return TextButton(
                onPressed: () => CoreCommandRegistry.register(ref),
                child: const Text('register'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('register'));
    await tester.pump();

    final commandIds = container
          .read(commandPaletteProvider)
          .allCommands
          .map((command) => command.id)
          .toSet();

      expect(commandIds, contains('studio.home'));
      expect(commandIds, contains('studio.newTask'));
      expect(commandIds, contains('settings.open'));
      expect(commandIds, isNot(contains('file.save')));
      expect(commandIds, isNot(contains('view.toggleTerminal')));
      expect(commandIds, isNot(contains('project.startWorkItem')));
      expect(commandIds, isNot(contains('agentWorkspace.startParallelTask')));

      container
          .read(commandPaletteProvider.notifier)
          .execute(
            container
                .read(commandPaletteProvider)
                .allCommands
                .singleWhere((command) => command.id == 'settings.open'),
          );

      expect(container.read(studioShellProvider).mode, StudioMode.settings);
    },
  );
}
