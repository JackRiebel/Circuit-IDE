import 'package:circuit_ide/models/command_descriptor.dart';
import 'package:circuit_ide/state/command_palette_provider.dart';
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
        title: 'Refresh Code Map',
        description: 'Rebuild L-SDF index',
        category: 'Workspace',
        icon: Icons.hub_outlined,
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

    container.read(commandPaletteProvider.notifier).filter('lsdf');
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
}
