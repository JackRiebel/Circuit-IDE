import 'dart:io';

import 'package:circuit_ide/core/constants/design_tokens.dart';
import 'package:circuit_ide/models/command_descriptor.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/state/command_palette_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/ui/command_palette/command_palette.dart';
import 'package:circuit_ide/ui/layout/tools_panel.dart';
import 'package:circuit_ide/ui/studio/studio_chrome.dart';
import 'package:circuit_ide/ui/studio/studio_left_rail.dart';
import 'package:circuit_ide/ui/studio/studio_prompt_composer.dart';
import 'package:circuit_ide/ui/studio/studio_rail_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
    expect(find.text('AI'), findsWidgets);
    expect(find.text('Verification'), findsOneWidget);
    expect(find.text('Integrations'), findsNothing);
    expect(find.text('Notebooks'), findsNothing);
    expect(find.text('Agents'), findsNothing);
    expect(find.text('MCP Hub'), findsNothing);
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
        description: 'Reconnect provider',
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
    expect(find.text('AI'), findsWidgets);
    expect(find.text('Workspace'), findsWidgets);

    final allChip = tester.widget<Text>(find.text('All'));
    expect(allChip.style?.fontSize, FontSizes.xxs);
    expect(allChip.style?.fontWeight, FontWeight.w600);

    final commandText = tester.widget<Text>(find.text('Reconnect AI'));
    expect(commandText.style?.fontSize, FontSizes.xs);
    expect(commandText.style?.fontWeight, FontWeight.w500);
    final commandMeta = tester.widget<Text>(find.text('Reconnect provider'));
    expect(commandMeta.style?.fontSize, FontSizes.xxs);

    final commandIcon = tester.widget<Icon>(
      find.byIcon(Icons.power_settings_new),
    );
    expect(commandIcon.size, 14);

    final commandRowSize = tester.getSize(
      find
          .ancestor(
            of: find.text('Reconnect AI'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(commandRowSize.height, 38);
  });

  testWidgets('Command palette keeps search focus during keyboard selection', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    String? executed;
    container.read(commandPaletteProvider.notifier).registerCommands([
      CommandDescriptor(
        id: 'first',
        title: 'First command',
        category: 'Test',
        icon: Icons.looks_one_outlined,
        run: () => executed = 'first',
      ),
      CommandDescriptor(
        id: 'second',
        title: 'Second command',
        category: 'Test',
        icon: Icons.looks_two_outlined,
        run: () => executed = 'second',
      ),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CommandPalette())),
      ),
    );
    await tester.pump();
    final inputFocus = tester
        .widget<TextField>(find.byType(TextField))
        .focusNode;
    expect(inputFocus?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(inputFocus?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(executed, 'second');
    expect(container.read(commandPaletteProvider).isOpen, isFalse);
  });

  testWidgets('Command palette restores the prior editor focus when closed', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final editorFocus = FocusNode(debugLabel: 'test-editor-focus');
    addTearDown(editorFocus.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              final paletteOpen = ref.watch(commandPaletteProvider).isOpen;
              return Scaffold(
                body: Stack(
                  children: [
                    TextField(
                      focusNode: editorFocus,
                      decoration: const InputDecoration(labelText: 'Editor'),
                    ),
                    if (paletteOpen) const CommandPalette(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    editorFocus.requestFocus();
    await tester.pump();
    expect(editorFocus.hasFocus, isTrue);

    container.read(commandPaletteProvider.notifier).open();
    await tester.pump();
    final paletteFocus = tester
        .widget<TextField>(find.byType(TextField).last)
        .focusNode;
    expect(paletteFocus?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();

    expect(container.read(commandPaletteProvider).isOpen, isFalse);
    expect(editorFocus.hasFocus, isTrue);
  });

  testWidgets('Studio composer retains keyboard focus through Studio updates', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: StudioPromptComposer(
              hintText: 'Ask Circuit',
              onSubmit: (_) {},
            ),
          ),
        ),
      ),
    );
    final composerFocus = tester
        .widget<TextField>(find.byType(TextField))
        .focusNode!;
    composerFocus.requestFocus();
    await tester.pump();
    expect(composerFocus.hasFocus, isTrue);

    container
        .read(studioShellProvider.notifier)
        .setPromptMode(StudioPromptMode.review);
    container.read(studioShellProvider.notifier).setPlanModeEnabled(true);
    await tester.pump();

    expect(composerFocus.hasFocus, isTrue);
  });

  testWidgets('Studio rail row keeps project icons on compact rail scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioRailRow(
              icon: Icons.folder_outlined,
              label: 'CircuitCode',
              selected: true,
              project: true,
            ),
          ),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.folder_outlined));
    expect(icon.size, 14);

    final label = tester.widget<Text>(find.text('CircuitCode'));
    expect(label.style?.fontSize, FontSizes.sm);
    expect(label.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('Studio rail selected rows use quiet Codex-like chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioRailRow(
              icon: Icons.folder_outlined,
              label: 'CircuitCode',
              selected: true,
              project: true,
              hoverTrailing: StudioChromeIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'New thread in CircuitCode',
                width: 22,
                height: 22,
                iconSize: 12,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final rowContainer = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('CircuitCode'),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = rowContainer.decoration;
    expect(decoration, isA<BoxDecoration>());
    expect((decoration! as BoxDecoration).border, isNull);

    final actionIcon = tester.widget<Icon>(find.byIcon(Icons.edit_outlined));
    expect(actionIcon.size, 12);
    final actionSize = tester.getSize(
      find.byTooltip('New thread in CircuitCode'),
    );
    expect(
      actionSize,
      const Size(
        StudioChromeIconButton.minimumTargetSize,
        StudioChromeIconButton.minimumTargetSize,
      ),
    );
  });

  testWidgets('Studio chrome icon buttons use soft compact corners', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioChromeIconButton(
              icon: Icons.tune_outlined,
              tooltip: 'Tune',
              active: true,
            ),
          ),
        ),
      ),
    );

    final decorated = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.tune_outlined),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = decorated.decoration;
    expect(decoration, isA<BoxDecoration>());
    expect(
      (decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(6),
    );

    final ink = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.byIcon(Icons.tune_outlined),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(ink.borderRadius, BorderRadius.circular(6));

    final icon = tester.widget<Icon>(find.byIcon(Icons.tune_outlined));
    expect(icon.size, 14);
  });

  testWidgets(
    'Studio prominent chrome button uses neutral native chrome tone',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StudioChromeIconButton(
                icon: Icons.arrow_downward,
                tooltip: 'Open project folder',
                prominent: true,
                width: 28,
                height: 28,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      final decorated = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.arrow_downward),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = decorated.decoration;
      expect(decoration, isA<BoxDecoration>());
      final boxDecoration = decoration! as BoxDecoration;
      expect(boxDecoration.color, isNot(const Color(0xFF4C8DFF)));
      expect(boxDecoration.borderRadius, BorderRadius.circular(Radii.pill));

      final icon = tester.widget<Icon>(find.byIcon(Icons.arrow_downward));
      expect(icon.size, 14);
    },
  );

  test('Studio rail does not draw fake macOS traffic-light controls', () async {
    final source = await File(
      'lib/ui/studio/studio_left_rail.dart',
    ).readAsString();

    expect(source, isNot(contains('_WindowDot')));
    expect(source, isNot(contains('0xFFFF5F57')));
    expect(source, isNot(contains('0xFFFFBD2E')));
    expect(source, isNot(contains('0xFF28C840')));
  });

  testWidgets('Studio create-project dialog uses compact Codex-like controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: StudioLeftRail())),
      ),
    );

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Create project'));
    expect(title.style?.fontSize, FontSizes.base);
    expect(title.style?.fontWeight, FontWeight.w600);

    final body = tester.widget<Text>(
      find.text('Name a new folder for this Circuit task.'),
    );
    expect(body.style?.fontSize, FontSizes.xs);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style?.fontSize, FontSizes.sm);
    expect(field.decoration?.labelStyle?.fontSize, FontSizes.xs);

    final folderIcon = tester.widget<Icon>(find.byIcon(Icons.folder_outlined));
    expect(folderIcon.size, 14);

    final changeButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Change'),
    );
    expect(changeButton.style?.minimumSize?.resolve({})?.height, 28);

    final createButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create'),
    );
    expect(createButton.style?.minimumSize?.resolve({})?.height, 28);
  });
}
