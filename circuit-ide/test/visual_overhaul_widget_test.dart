import 'dart:io';

import 'package:circuit_ide/core/constants/design_tokens.dart';
import 'package:circuit_ide/models/command_descriptor.dart';
import 'package:circuit_ide/state/command_palette_provider.dart';
import 'package:circuit_ide/ui/command_palette/command_palette.dart';
import 'package:circuit_ide/ui/layout/tools_panel.dart';
import 'package:circuit_ide/ui/studio/studio_chrome.dart';
import 'package:circuit_ide/ui/studio/studio_left_rail.dart';
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
    expect(actionSize, const Size(22, 22));
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
