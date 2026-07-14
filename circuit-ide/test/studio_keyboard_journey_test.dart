import 'dart:io';

import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/command_descriptor.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/command_palette_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/settings_provider.dart';
import 'package:circuit_ide/state/studio_right_drawer_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_thread_search_provider.dart';
import 'package:circuit_ide/state/theme_provider.dart';
import 'package:circuit_ide/ui/studio/studio_shell.dart';
import 'package:circuit_ide/ui/studio/studio_left_rail.dart';
import 'package:circuit_ide/ui/studio/studio_task_view.dart';
import 'package:circuit_ide/ui/command_palette/command_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  VisibilityDetectorController.instance.updateInterval = Duration.zero;

  testWidgets(
    'keyboard traversal can type in the composer and request a patch revision',
    (tester) async {
      final originalPersistDebounce =
          StudioThreadController.debugPersistDebounceOverride;
      StudioThreadController.debugPersistDebounceOverride = Duration.zero;
      addTearDown(
        () => StudioThreadController.debugPersistDebounceOverride =
            originalPersistDebounce,
      );
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Keyboard reviewed patch');
      const requestId = 'keyboard-reviewed-patch-request';
      final timestamp = DateTime.utc(2026, 7, 13, 17);
      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(
            thread.id,
            StudioTurn(
              id: 'keyboard-reviewed-patch-turn',
              threadId: thread.id,
              requestId: requestId,
              userMessageId: 'keyboard-reviewed-patch-message',
              prompt: 'Prepare the reviewed README edit.',
              model: 'test-model',
              intent: TurnIntent.code,
              contextSummary: const StudioContextSummary(
                projectLabel: 'Keyboard fixture',
              ),
              status: StudioTurnStatus.reviewingPatch,
              events: [
                StudioTurnEvent.userMessage(
                  id: 'keyboard-reviewed-patch-user',
                  turnId: 'keyboard-reviewed-patch-turn',
                  requestId: requestId,
                  threadId: thread.id,
                  content: 'Prepare the reviewed README edit.',
                  timestamp: timestamp,
                ),
              ],
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
            select: true,
          );
      container
          .read(patchProposalProvider.notifier)
          .preserveProposal(
            ProposedPatchSet(
              id: 'keyboard-reviewed-patch',
              title: 'Update README from keyboard review',
              runId: requestId,
              edits: const [
                ProposedFileEdit(
                  path: 'README.md',
                  type: ProposedFileEditType.modify,
                  before: 'before keyboard review\n',
                  after: 'after keyboard review\n',
                ),
              ],
              createdAt: timestamp,
            ),
          );
      container.read(studioShellProvider.notifier).openThread(thread.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: StudioShell()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final composer = find.byType(TextField);
      final revision = find.widgetWithText(OutlinedButton, 'Ask for revision');
      expect(composer, findsOneWidget);
      expect(revision, findsOneWidget);

      await _tabUntil(
        tester,
        () =>
            FocusManager.instance.primaryFocus?.debugLabel ==
            'studio-prompt-composer',
        target: 'the Studio composer',
      );
      await tester.enterText(composer, 'Keep this patch review keyboard-only.');
      expect(
        container.read(studioShellProvider).composerText,
        'Keep this patch review keyboard-only.',
      );

      await _tabUntil(
        tester,
        () =>
            FocusManager.instance.primaryFocus?.debugLabel ==
            'studio-patch-revision',
        target: 'Ask for revision',
      );
      final focusBorder = tester
          .widget<OutlinedButton>(revision)
          .style
          ?.side
          ?.resolve(const {WidgetState.focused});
      expect(focusBorder?.color, container.read(themeProvider).outlineFocus);
      expect(focusBorder?.width, 1.5);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      final proposal = container.read(patchProposalProvider).active;
      expect(proposal?.approvalStatus, PatchApprovalStatus.revisionRequested);
      expect(
        container.read(studioShellProvider).promptMode,
        StudioPromptMode.code,
      );
      expect(
        container.read(studioShellProvider).composerText,
        startsWith('Revise these proposed changes. Change:'),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'keyboard traversal applies a reviewed patch only inside the active workspace',
    (tester) async {
      final originalPersistDebounce =
          StudioThreadController.debugPersistDebounceOverride;
      StudioThreadController.debugPersistDebounceOverride = Duration.zero;
      addTearDown(
        () => StudioThreadController.debugPersistDebounceOverride =
            originalPersistDebounce,
      );
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final root = Directory.systemTemp.createTempSync(
        'studio_keyboard_apply_',
      );
      final readme = File('${root.path}/README.md')..writeAsStringSync('old');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(
        () =>
            container.read(fileTreeProvider.notifier).openDirectory(root.path),
      );
      await tester.runAsync(
        () => container.read(agentWorkspaceProvider.notifier).reload(),
      );
      await tester.runAsync(
        () => container.read(studioThreadProvider.notifier).reload(),
      );
      final task = container
          .read(agentWorkspaceProvider.notifier)
          .startTask(
            goal: 'Apply the reviewed README edit.',
            profile: AgentTaskProfile.patch,
          );
      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(taskId: task.id, title: 'Keyboard applied patch');
      container.read(studioShellProvider.notifier).openTask(task.id);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      const requestId = 'keyboard-applied-patch-request';
      final timestamp = DateTime.utc(2026, 7, 13, 18);
      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(
            thread.id,
            StudioTurn(
              id: 'keyboard-applied-patch-turn',
              threadId: thread.id,
              requestId: requestId,
              userMessageId: 'keyboard-applied-patch-message',
              prompt: 'Apply the reviewed README edit.',
              model: 'test-model',
              intent: TurnIntent.code,
              contextSummary: const StudioContextSummary(
                projectLabel: 'Keyboard fixture',
              ),
              status: StudioTurnStatus.reviewingPatch,
              events: [
                StudioTurnEvent.userMessage(
                  id: 'keyboard-applied-patch-user',
                  turnId: 'keyboard-applied-patch-turn',
                  requestId: requestId,
                  threadId: thread.id,
                  content: 'Apply the reviewed README edit.',
                  timestamp: timestamp,
                ),
              ],
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
            select: true,
          );
      container
          .read(patchProposalProvider.notifier)
          .preserveProposal(
            ProposedPatchSet(
              id: 'keyboard-applied-patch',
              title: 'Apply README from keyboard review',
              runId: requestId,
              agentTaskId: task.id,
              edits: const [
                ProposedFileEdit(
                  path: 'README.md',
                  type: ProposedFileEditType.modify,
                  before: 'old',
                  after: 'new',
                ),
              ],
              createdAt: timestamp,
            ),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: StudioTaskView()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        container.read(patchProposalProvider).active?.id,
        'keyboard-applied-patch',
      );
      expect(find.text('Apply changes'), findsOneWidget);
      await _tabUntil(
        tester,
        () =>
            FocusManager.instance.primaryFocus?.debugLabel ==
            'studio-patch-apply',
        target: 'Apply changes',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      for (var attempt = 0; attempt < 40; attempt++) {
        final state = container.read(patchProposalProvider);
        final patch = state.active ?? state.history.first;
        if (!state.isApplying &&
            patch.applyStatus == PatchApplyStatus.applied) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }

      final patchState = container.read(patchProposalProvider);
      final appliedPatch = patchState.active ?? patchState.history.first;
      expect(readme.readAsStringSync(), 'new');
      expect(appliedPatch.applyStatus, PatchApplyStatus.applied);
      expect(appliedPatch.changedFiles, ['README.md']);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'keyboard composer keeps focus and a queued follow-up while the transcript streams',
    (tester) async {
      final originalPersistDebounce =
          StudioThreadController.debugPersistDebounceOverride;
      StudioThreadController.debugPersistDebounceOverride = Duration.zero;
      addTearDown(
        () => StudioThreadController.debugPersistDebounceOverride =
            originalPersistDebounce,
      );
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Keyboard streaming follow-up');
      const requestId = 'keyboard-streaming-request';
      const turnId = 'keyboard-streaming-turn';
      final timestamp = DateTime.utc(2026, 7, 13, 19);
      container
          .read(studioThreadProvider.notifier)
          .upsertTurn(
            thread.id,
            StudioTurn(
              id: turnId,
              threadId: thread.id,
              requestId: requestId,
              userMessageId: 'keyboard-streaming-message',
              prompt: 'Explain the current implementation.',
              model: 'test-model',
              intent: TurnIntent.chat,
              contextSummary: const StudioContextSummary(
                projectLabel: 'Keyboard fixture',
              ),
              status: StudioTurnStatus.streaming,
              assistantDraft: 'Streaming the first response chunk.',
              events: [
                StudioTurnEvent.userMessage(
                  id: 'keyboard-streaming-user',
                  turnId: turnId,
                  requestId: requestId,
                  threadId: thread.id,
                  content: 'Explain the current implementation.',
                  timestamp: timestamp,
                ),
              ],
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
            select: true,
          );
      container.read(studioShellProvider.notifier).openThread(thread.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: StudioShell()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final composer = find.byType(TextField);
      await _tabUntil(
        tester,
        () =>
            FocusManager.instance.primaryFocus?.debugLabel ==
            'studio-prompt-composer',
        target: 'the Studio composer',
      );
      await tester.enterText(composer, 'Queue this after the current reply.');

      container
          .read(studioThreadProvider.notifier)
          .updateTurn(
            thread.id,
            turnId,
            status: StudioTurnStatus.streaming,
            assistantDraft: 'Streaming the next response chunk.',
          );
      await tester.pump();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'studio-prompt-composer',
      );
      expect(
        container.read(studioShellProvider).composerText,
        'Queue this after the current reply.',
      );
      expect(find.text('Streaming the next response chunk.'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'keyboard shortcut opens the command palette, executes a command, and restores focus',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final originFocus = FocusNode(debugLabel: 'keyboard-dialog-origin');
      addTearDown(originFocus.dispose);
      var executedSecondCommand = false;
      container.read(commandPaletteProvider.notifier).registerCommands([
        CommandDescriptor(
          id: 'keyboard.first',
          title: 'First keyboard command',
          category: 'Test',
          icon: Icons.looks_one_outlined,
          run: () {},
        ),
        CommandDescriptor(
          id: 'keyboard.second',
          title: 'Second keyboard command',
          category: 'Test',
          icon: Icons.looks_two_outlined,
          run: () => executedSecondCommand = true,
        ),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: CallbackShortcuts(
                bindings: {
                  const SingleActivator(
                    LogicalKeyboardKey.keyK,
                    meta: true,
                  ): () =>
                      container.read(commandPaletteProvider.notifier).toggle(),
                },
                child: Consumer(
                  builder: (context, ref, child) => Stack(
                    children: [
                      TextField(focusNode: originFocus),
                      if (ref.watch(commandPaletteProvider).isOpen)
                        const CommandPalette(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      originFocus.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.pump();

      expect(container.read(commandPaletteProvider).isOpen, isTrue);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'command-palette-search',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      expect(executedSecondCommand, isTrue);
      expect(container.read(commandPaletteProvider).isOpen, isFalse);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'keyboard-dialog-origin',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'keyboard rail search filters history and opens the matching task',
    (tester) async {
      final originalPersistDebounce =
          StudioThreadController.debugPersistDebounceOverride;
      StudioThreadController.debugPersistDebounceOverride = Duration.zero;
      addTearDown(
        () => StudioThreadController.debugPersistDebounceOverride =
            originalPersistDebounce,
      );
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final root = Directory.systemTemp.createTempSync('studio_keyboard_rail_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(
        () =>
            container.read(fileTreeProvider.notifier).openDirectory(root.path),
      );
      container.read(settingsProvider.notifier).addRecentProject(root.path);
      await tester.runAsync(
        () => container.read(studioThreadProvider.notifier).reload(),
      );
      final background = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Keyboard rail background task');
      final matching = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Keyboard rail matching task');
      container.read(studioShellProvider.notifier).openThread(background.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: StudioShell()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        container.read(studioThreadProvider).selectedThreadId,
        background.id,
      );
      await _tabUntil(
        tester,
        () =>
            FocusManager.instance.primaryFocus?.debugLabel ==
            'studio-rail-Search',
        target: 'the rail Search action',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      final searchField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search chats',
      );
      expect(container.read(studioThreadSearchProvider).isOpen, isTrue);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'matching');
      await tester.pump();
      final rail = find.byType(StudioLeftRail);
      expect(rail, findsOneWidget);
      expect(
        find.descendant(
          of: rail,
          matching: find.text('Keyboard rail matching task'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rail,
          matching: find.text('Keyboard rail background task'),
        ),
        findsNothing,
      );

      await _tabUntil(
        tester,
        () =>
            FocusManager.instance.primaryFocus?.debugLabel ==
            'studio-rail-Keyboard rail matching task',
        target: 'the filtered rail task',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(
        container.read(studioThreadProvider).selectedThreadId,
        matching.id,
      );
      expect(container.read(studioShellProvider).selectedTaskId, isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'keyboard traversal collapses and restores the work panel without losing focus',
    (tester) async {
      final originalPersistDebounce =
          StudioThreadController.debugPersistDebounceOverride;
      StudioThreadController.debugPersistDebounceOverride = Duration.zero;
      addTearDown(
        () => StudioThreadController.debugPersistDebounceOverride =
            originalPersistDebounce,
      );
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Keyboard work panel');
      container.read(studioShellProvider.notifier).openThread(thread.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: StudioShell()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      await _tabUntil(
        tester,
        () =>
            FocusManager.instance.primaryFocus?.debugLabel ==
            'studio-chrome-Collapse panel',
        target: 'Collapse panel',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.pump();

      expect(container.read(studioRightDrawerProvider).collapsed, isTrue);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'studio-progress-toggle',
      );

      await _tabUntil(
        tester,
        () =>
            FocusManager.instance.primaryFocus?.debugLabel ==
            'studio-chrome-Expand right panel',
        target: 'Expand right panel',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.pump();

      expect(container.read(studioRightDrawerProvider).collapsed, isFalse);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'studio-progress-toggle',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<void> _tabUntil(
  WidgetTester tester,
  bool Function() hasReachedTarget, {
  required String target,
}) async {
  final visited = <String>[];
  for (var attempt = 0; attempt < 96; attempt++) {
    if (hasReachedTarget()) return;
    visited.add(FocusManager.instance.primaryFocus?.debugLabel ?? 'unnamed');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('Keyboard traversal did not reach $target. Visited: $visited');
}
