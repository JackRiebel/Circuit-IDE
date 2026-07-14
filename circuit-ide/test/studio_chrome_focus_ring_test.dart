import 'package:circuit_ide/theme/theme_tokens.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/state/studio_right_drawer_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/ui/studio/studio_chrome.dart';
import 'package:circuit_ide/ui/studio/studio_composer_image_directives.dart';
import 'package:circuit_ide/ui/studio/studio_composer_utility_controls.dart';
import 'package:circuit_ide/ui/studio/studio_file_sources_drawer.dart';
import 'package:circuit_ide/ui/studio/studio_progress_drawer.dart';
import 'package:circuit_ide/ui/studio/studio_rail_row.dart';
import 'package:circuit_ide/ui/studio/studio_settings_view.dart';
import 'package:circuit_ide/ui/studio/studio_task_plan_primitives.dart';
import 'package:circuit_ide/ui/studio/studio_task_patch_files.dart';
import 'package:circuit_ide/ui/studio/studio_task_card.dart';
import 'package:circuit_ide/ui/studio/studio_composer_selectors.dart';
import 'package:circuit_ide/ui/studio/studio_prompt_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shared Studio chrome controls expose a tokenized focus ring', (
    tester,
  ) async {
    final focusNode = FocusNode(debugLabel: 'test-studio-chrome-focus');
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioChromeIconButton(
              focusNode: focusNode,
              tooltip: 'Open keyboard target',
              icon: Icons.keyboard,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      _decoration(tester, find.byType(StudioChromeIconButton)).border,
      isNull,
    );
    focusNode.requestFocus();
    await tester.pump();

    final border =
        _decoration(tester, find.byType(StudioChromeIconButton)).border!
            as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, ThemeTokens.dark.outlineFocus);
  });

  testWidgets('tonal controls retain a visible focus ring and target size', (
    tester,
  ) async {
    final focusNode = FocusNode(debugLabel: 'test-studio-tonal-focus');
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioTonalButton(
              focusNode: focusNode,
              label: 'Open source',
              icon: Icons.open_in_new,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(StudioTonalButton)).height,
      greaterThanOrEqualTo(StudioTonalButton.minimumTargetSize),
    );
    focusNode.requestFocus();
    await tester.pump();

    final border =
        _decoration(tester, find.byType(StudioTonalButton)).border! as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, ThemeTokens.dark.outlineFocus);
  });

  testWidgets('loading Studio chrome controls stay named and unavailable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioChromeIconButton(
              tooltip: 'Check Circuit AI connection',
              icon: Icons.refresh,
              onTap: () {},
              loading: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Check Circuit AI connection')),
      isSemantics(
        label: 'Check Circuit AI connection',
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('Progress drawer Context details uses the shared action target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: StudioProgressDrawer())),
      ),
    );

    final action = find.byTooltip('Context details');
    expect(action, findsOneWidget);
    expect(
      tester.getSize(find.byType(StudioChromeIconButton)),
      const Size(
        StudioChromeIconButton.minimumTargetSize,
        StudioChromeIconButton.minimumTargetSize,
      ),
    );
    expect(
      tester.getSemantics(action),
      isSemantics(
        label: 'Context details',
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets(
    'focusable Studio action surfaces retain a focus ring and keyboard activation',
    (tester) async {
      final focusNode = FocusNode(debugLabel: 'test-studio-action-surface');
      addTearDown(focusNode.dispose);
      var activationCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StudioFocusableActionSurface(
                semanticLabel: 'Open customer report',
                focusNode: focusNode,
                onTap: () => activationCount++,
                child: const SizedBox(width: 180, height: 28),
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      final border =
          _decoration(tester, find.byType(StudioFocusableActionSurface)).border!
              as Border;
      expect(border.top.width, 1.5);
      expect(border.top.color, ThemeTokens.dark.outlineFocus);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      expect(activationCount, 3);
      expect(find.bySemanticsLabel('Open customer report'), findsOneWidget);
    },
  );

  testWidgets('plan icon actions inherit Studio chrome focus behavior', (
    tester,
  ) async {
    final focusNode = FocusNode(debugLabel: 'test-plan-action-focus');
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioPlanIconAction(
              focusNode: focusNode,
              tooltip: 'Remove plan target',
              icon: Icons.delete_outline,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(StudioPlanIconAction)),
      const Size(28, 28),
    );
    focusNode.requestFocus();
    await tester.pump();

    final border =
        _decoration(tester, find.byType(StudioChromeIconButton)).border!
            as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, ThemeTokens.dark.outlineFocus);
    expect(find.bySemanticsLabel('Remove plan target'), findsOneWidget);
  });

  testWidgets('activity rows retain a visible focus ring and minimum target', (
    tester,
  ) async {
    final focusNode = FocusNode(debugLabel: 'test-studio-activity-focus');
    addTearDown(focusNode.dispose);
    var activationCount = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioActivityRow(
              focusNode: focusNode,
              icon: Icons.info_outline,
              title: 'Index complete',
              detail: 'Open project evidence',
              onTap: () => activationCount++,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(StudioActivityRow)).height,
      greaterThanOrEqualTo(StudioChromeIconButton.minimumTargetSize),
    );
    expect(
      find.bySemanticsLabel('Index complete, Open project evidence'),
      findsOneWidget,
    );
    await tester.tap(find.byType(StudioActivityRow));
    await tester.pump();
    expect(activationCount, 1);
    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(activationCount, 2);

    final border =
        _decoration(tester, find.byType(StudioActivityRow)).border! as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, ThemeTokens.dark.outlineFocus);
    semantics.dispose();
  });

  testWidgets(
    'rail rows expose a durable focus ring and activate with Space or Enter',
    (tester) async {
      var activationCount = 0;
      final focusNode = FocusNode(debugLabel: 'test-studio-rail-focus');
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StudioRailRow(
                icon: Icons.chat_bubble_outline,
                label: 'Accessible project task',
                onTap: () => activationCount++,
                focusNode: focusNode,
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      expect(
        tester.getSize(find.byType(StudioRailRow)).height,
        greaterThanOrEqualTo(StudioChromeIconButton.minimumTargetSize),
      );
      final border =
          _decoration(tester, find.byType(StudioRailRow)).border! as Border;
      expect(border.top.width, 1.5);
      expect(border.top.color, ThemeTokens.dark.outlineFocus);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(activationCount, 2);
      expect(find.bySemanticsLabel('Accessible project task'), findsWidgets);
    },
  );

  testWidgets(
    'settings toggles retain focus, keyboard activation, and target size',
    (tester) async {
      final focusNode = FocusNode(debugLabel: 'test-studio-setting-focus');
      addTearDown(focusNode.dispose);
      var toggled = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StudioSettingsToggle(
                focusNode: focusNode,
                semanticLabel: 'Keep local diagnostics',
                value: false,
                onChanged: (value) => toggled = value,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(StudioSettingsToggle)).height,
        greaterThanOrEqualTo(StudioSettingsToggle.minimumTargetSize),
      );
      focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);

      final border =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byType(StudioSettingsToggle),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      final focusBorder = border.border! as Border;
      expect(focusBorder.top.width, 1.5);
      expect(focusBorder.top.color, ThemeTokens.dark.outlineFocus);
      expect(toggled, isTrue);
    },
  );

  testWidgets(
    'drawer list rows retain a semantic focus ring and activate with Space or Enter',
    (tester) async {
      var activationCount = 0;
      final focusNode = FocusNode(debugLabel: 'test-studio-drawer-row-focus');
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StudioDrawerListRow(
                focusNode: focusNode,
                icon: Icons.description_outlined,
                title: 'Customer evidence',
                subtitle: 'Generated readiness report',
                onTap: () => activationCount++,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(StudioDrawerListRow)).height,
        greaterThanOrEqualTo(StudioChromeIconButton.minimumTargetSize),
      );
      focusNode.requestFocus();
      await tester.pump();

      final border =
          _decoration(tester, find.byType(StudioDrawerListRow)).border!
              as Border;
      expect(border.top.width, 1.5);
      expect(border.top.color, ThemeTokens.dark.outlineFocus);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(activationCount, 2);
      expect(
        find.bySemanticsLabel('Customer evidence, Generated readiness report'),
        findsWidgets,
      );
    },
  );

  testWidgets('Add context uses the shared accessible chrome control', (
    tester,
  ) async {
    final focusNode = FocusNode(debugLabel: 'test-add-context-focus');
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: StudioAddContextButton(focusNode: focusNode)),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(StudioAddContextButton)),
      const Size(24, 24),
    );
    focusNode.requestFocus();
    await tester.pump();

    final border =
        _decoration(tester, find.byType(StudioChromeIconButton)).border!
            as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, ThemeTokens.dark.outlineFocus);
    expect(find.bySemanticsLabel('Add context'), findsWidgets);
  });

  testWidgets('image directive removal uses shared accessible chrome control', (
    tester,
  ) async {
    var removalCount = 0;
    var previewCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioImageDirectivePreview(
              path: '/tmp/circuit-image-directive-fixture.png',
              role: null,
              tokens: ThemeTokens.dark,
              onRemove: () => removalCount++,
              onPreview: () => previewCount++,
            ),
          ),
        ),
      ),
    );

    final removeControl = find.bySemanticsLabel('Remove image');
    expect(removeControl, findsOneWidget);
    expect(tester.getSize(removeControl), const Size(26, 26));

    await tester.tap(removeControl);
    expect(removalCount, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(removalCount, 2);

    final previewControl = find.byKey(
      const ValueKey(
        'studio-image-preview-/tmp/circuit-image-directive-fixture.png',
      ),
    );
    expect(previewControl, findsOneWidget);
    expect(
      tester.getSemantics(previewControl),
      isSemantics(
        label: 'Preview attached image circuit-image-directive-fixture.png',
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(previewControl);
    await tester.pump();
    expect(previewCount, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(previewCount, 2);
  });

  testWidgets('patch file rows support named keyboard diff inspection', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final patch = ProposedPatchSet(
      id: 'patch-focus-row',
      title: 'Accessible file row',
      createdAt: DateTime.utc(2026, 7, 14),
      edits: const [
        ProposedFileEdit(
          path: 'lib/workspace.dart',
          type: ProposedFileEditType.modify,
          before: 'before',
          after: 'after',
        ),
      ],
    );
    final file = studioPatchFiles(patch).single;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: StudioPatchFileRow(patch: patch, file: file),
          ),
        ),
      ),
    );

    final row = find.bySemanticsLabel('Open diff for lib/workspace.dart');
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, 32);
    await tester.tap(row);
    await tester.pump();

    final focusedBorders = find
        .descendant(
          of: find.byType(StudioFocusableActionSurface),
          matching: find.byType(Container),
        )
        .evaluate()
        .map((element) => element.widget)
        .whereType<Container>()
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.border)
        .whereType<Border>();
    expect(
      focusedBorders.any(
        (border) =>
            border.top.width == 1.5 &&
            border.top.color == ThemeTokens.dark.outlineFocus,
      ),
      isTrue,
    );
    expect(container.read(studioRightDrawerProvider).patchFilePath, file.path);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(container.read(studioRightDrawerProvider).patchFilePath, file.path);
  });

  testWidgets('task cards retain a named keyboard task action', (tester) async {
    var activationCount = 0;
    final task = AgentTask(
      id: 'task-focus-card',
      mascotAlias: 'Benny',
      profile: AgentTaskProfile.investigate,
      status: AgentTaskStatus.running,
      goal: 'Inspect workspace state',
      createdAt: DateTime.utc(2026, 7, 14),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioTaskCard(
              task: task,
              projectLabel: 'CircuitCode',
              onTap: () => activationCount++,
            ),
          ),
        ),
      ),
    );

    final card = find.bySemanticsLabel(
      'Open Inspect workspace state, Working task',
    );
    expect(card, findsOneWidget);
    await tester.tap(card);
    await tester.pump();
    expect(activationCount, 1);
    final focusedBorders = find
        .descendant(
          of: find.byType(StudioFocusableActionSurface),
          matching: find.byType(Container),
        )
        .evaluate()
        .map((element) => element.widget)
        .whereType<Container>()
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.border)
        .whereType<Border>();
    expect(
      focusedBorders.any(
        (border) =>
            border.top.width == 1.5 &&
            border.top.color == ThemeTokens.dark.outlineFocus,
      ),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activationCount, 2);
  });

  testWidgets('plan choices expose keyboard-operable button semantics', (
    tester,
  ) async {
    var activationCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioPlanChoiceButton(
              index: '1',
              label: 'Approve the implementation plan',
              enabled: true,
              onPressed: () => activationCount++,
            ),
          ),
        ),
      ),
    );

    final choice = find.bySemanticsLabel('Approve the implementation plan');
    expect(choice, findsOneWidget);
    await tester.tap(choice);
    await tester.pump();
    expect(activationCount, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activationCount, 2);
    expect(
      _hasOutlineFocus(tester, find.byType(StudioFocusableActionSurface)),
      isTrue,
    );
  });

  testWidgets('disabled plan choices remain named unavailable buttons', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioPlanChoiceButton(
              index: null,
              label: 'Choose a plan target first',
              enabled: false,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Choose a plan target first')),
      isSemantics(
        label: 'Choose a plan target first',
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('Plan mode toggle is a selected keyboard action', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: StudioComposerPlanModeToggle(enabled: false)),
        ),
      ),
    );

    final toggle = find.bySemanticsLabel('Toggle Plan mode');
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(container.read(studioShellProvider).planModeEnabled, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(container.read(studioShellProvider).planModeEnabled, isFalse);
    expect(
      _hasOutlineFocus(tester, find.byType(StudioFocusableActionSurface)),
      isTrue,
    );
  });

  testWidgets('disabled action surfaces retain their unavailable semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioFocusableActionSurface(
              semanticLabel: 'Queue research',
              child: SizedBox(width: 28, height: 28),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Queue research')),
      isSemantics(
        label: 'Queue research',
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets(
    'research queue control becomes a named action once it has text',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final semantics = tester.ensureSemantics();
      final queued = <String>[];
      container
          .read(studioShellProvider.notifier)
          .setPromptMode(StudioPromptMode.research);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StudioPromptComposer(
                hintText: 'Ask a research question',
                onSubmit: (_) {},
                onQueueResearch: queued.add,
              ),
            ),
          ),
        ),
      );

      final queue = find.bySemanticsLabel('Queue research');
      expect(queue, findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'Compare official sources',
      );
      await tester.pump();
      expect(
        tester.getSemantics(queue),
        isSemantics(
          label: 'Queue research',
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(queue);
      await tester.pump();
      expect(queued, ['Compare official sources']);
      semantics.dispose();
    },
  );
}

BoxDecoration _decoration(WidgetTester tester, Finder control) {
  final containers = find
      .descendant(of: control, matching: find.byType(Container))
      .evaluate()
      .map((element) => element.widget)
      .whereType<Container>();
  return containers
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .single;
}

bool _hasOutlineFocus(WidgetTester tester, Finder control) {
  final focusedBorders = find
      .descendant(of: control, matching: find.byType(Container))
      .evaluate()
      .map((element) => element.widget)
      .whereType<Container>()
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .map((decoration) => decoration.border)
      .whereType<Border>();
  return focusedBorders.any(
    (border) =>
        border.top.width == 1.5 &&
        border.top.color == ThemeTokens.dark.outlineFocus,
  );
}
