import 'package:circuit_ide/models/confirmation_request.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/models/studio_right_drawer.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/studio_view_models.dart';
import 'package:circuit_ide/state/studio_right_drawer_provider.dart';
import 'package:circuit_ide/state/studio_source_artifact_provider.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_chrome.dart';
import 'package:circuit_ide/ui/studio/studio_recent_project_group.dart';
import 'package:circuit_ide/ui/studio/studio_right_drawer.dart';
import 'package:circuit_ide/ui/studio/studio_task_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  StudioThreadController.debugPersistDebounceOverride = Duration.zero;
  tearDownAll(() {
    StudioThreadController.debugPersistDebounceOverride = null;
  });

  testWidgets('Studio navigation and drawer controls expose named roles', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: Row(
                children: [
                  StudioChromeIconButton(
                    icon: Icons.tune_outlined,
                    tooltip: 'Command palette',
                    onTap: _noop,
                  ),
                  Expanded(child: StudioRightDrawer()),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Command palette'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Studio work panel')), findsOneWidget);
    expect(find.byTooltip('Open drawer view'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('rail attention status has text and shape beyond its color', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioRailTaskStatusIndicator(
              display: TaskDisplayState(
                kind: TaskDisplayKind.failed,
                label: 'Needs review',
                needsAttention: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Task status: Needs review'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('rail queue status has text and a non-spinning shape', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StudioRailTaskStatusIndicator(
              display: TaskDisplayState(
                kind: TaskDisplayKind.queued,
                label: 'Queued',
                isActive: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Task status: Queued'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'drawer view overflow switches modes and collapsed state stays compact',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(width: 420, child: StudioRightDrawer()),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Open drawer view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Artifacts').last);
      await tester.pumpAndSettle();
      expect(
        container.read(studioRightDrawerProvider).mode,
        StudioDrawerMode.artifacts,
      );

      container.read(studioRightDrawerProvider.notifier).toggleCollapsed();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Expand right panel'), findsOneWidget);
      expect(find.byTooltip('Open drawer view'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Progress view$')), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Artifacts view$')), findsNothing);
    },
  );

  testWidgets('Studio transcript exposes speaker, state, and approval risk', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Accessible task');
    final turn = StudioTurn(
      id: 'accessible-turn',
      threadId: thread.id,
      requestId: 'accessible-request',
      userMessageId: 'accessible-message',
      prompt: 'Run the checks',
      model: 'gpt-5-nano',
      contextSummary: const StudioContextSummary(projectLabel: 'project'),
      status: StudioTurnStatus.waitingForApproval,
      events: [
        StudioTurnEvent.userMessage(
          id: 'accessible-message',
          turnId: 'accessible-turn',
          requestId: 'accessible-request',
          threadId: thread.id,
          content: 'Run the checks',
          timestamp: DateTime(2026),
        ),
        StudioTurnEvent.assistantMessage(
          turnId: 'accessible-turn',
          requestId: 'accessible-request',
          threadId: thread.id,
          content: 'I will run the reviewed verification command.',
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
        ),
        StudioTurnEvent.approval(
          turnId: 'accessible-turn',
          requestId: 'accessible-request',
          threadId: thread.id,
          request: ConfirmationRequest(
            id: 'accessible-approval',
            toolCall: const ToolCallInfo(
              id: 'accessible-tool',
              name: 'run_command',
              arguments: {'command': 'flutter test'},
            ),
            preview: 'flutter test',
            warnings: const ['Shell command requires review.'],
          ),
          timestamp: DateTime(2026, 1, 1, 0, 0, 2),
        ),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(thread.id, turn, select: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioTaskView())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.bySemanticsLabel(RegExp('Task status:')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Your message')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Circuit response')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Approval needed: run command')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Copy response'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('artifact detail rows announce accessibility review status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final artifact = GeneratedArtifact(
      id: 'accessible-artifact',
      kind: GeneratedArtifactKind.pdf,
      status: GeneratedArtifactStatus.ready,
      fileName: 'accessible-report.pdf',
      filePath: '/tmp/accessible-report.pdf',
      summary: 'A reviewed customer report.',
      byteSize: 1024,
      metadata: const {
        'accessibilityStatus': 'Checks passed',
        'hasAccessibleArtifact': true,
        'accessibilityManualReview':
            'Review the generated output with the target format screen reader before external handoff.',
      },
      createdAt: DateTime(2026),
    );
    container
        .read(studioSourceArtifactProvider.notifier)
        .add(artifact.toSourceArtifact());
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.artifacts);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: StudioRightDrawer())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('accessible-report.pdf'));
    await tester.pump();

    expect(
      find.bySemanticsLabel('Accessibility: Checks passed'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Manual review: Review the generated output with the target format screen reader before external handoff.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });
}

void _noop() {}
