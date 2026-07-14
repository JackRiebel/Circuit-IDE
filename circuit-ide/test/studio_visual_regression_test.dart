import 'package:circuit_ide/core/constants/studio_layout_contract.dart';
import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/command_run.dart';
import 'package:circuit_ide/models/confirmation_request.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_right_drawer.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/state/command_run_provider.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/macos_update_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/settings_provider.dart';
import 'package:circuit_ide/state/studio_browser_provider.dart';
import 'package:circuit_ide/state/studio_project_history_provider.dart';
import 'package:circuit_ide/state/studio_right_drawer_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_source_artifact_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_left_rail.dart';
import 'package:circuit_ide/ui/studio/studio_recent_project_group.dart';
import 'package:circuit_ide/ui/studio/studio_right_drawer.dart';
import 'package:circuit_ide/ui/studio/studio_prompt_composer.dart';
import 'package:circuit_ide/ui/studio/studio_task_view.dart';
import 'package:circuit_ide/ui/studio/studio_shell.dart';
import 'package:circuit_ide/ui/studio/studio_update_settings.dart';
import 'package:circuit_ide/services/macos_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'support/studio_golden_harness.dart';

void main() {
  testWidgets('transcript keeps assistant prose document-like', (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final threadController = container.read(studioThreadProvider.notifier);
    final thread = threadController.createBlankThread(title: 'Transcript');
    final timestamp = DateTime.utc(2026, 7, 11, 12);
    final turn = StudioTurn(
      id: 'turn-prose',
      threadId: thread.id,
      requestId: 'request-prose',
      userMessageId: 'message-prose',
      prompt: 'Summarize the implementation.',
      model: 'test-model',
      contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.userMessage(
          id: 'user-prose',
          turnId: 'turn-prose',
          requestId: 'request-prose',
          threadId: thread.id,
          content: 'Summarize the implementation.',
          timestamp: timestamp,
        ),
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-prose',
          requestId: 'request-prose',
          threadId: thread.id,
          content:
              '## Summary\n\nThe implementation is ready for review.\n\n- Context is scoped\n- Verification is next',
          timestamp: timestamp.add(const Duration(seconds: 1)),
        ),
      ],
      createdAt: timestamp,
      updatedAt: timestamp.add(const Duration(seconds: 1)),
      completedAt: timestamp.add(const Duration(seconds: 1)),
    );
    threadController.upsertTurn(thread.id, turn, select: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Summary'), findsOneWidget);
    await expectLater(
      find.byType(StudioTaskView),
      matchesGoldenFile('goldens/studio_transcript_prose.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('long transcript keeps its concluding checks readable', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Long release review');
    final timestamp = DateTime.utc(2026, 7, 13, 15, 30);
    final longResponse = [
      '# Release readiness review',
      'The visible conclusion must remain readable after a long evidence response.',
      for (var section = 1; section <= 14; section++) ...[
        '## Evidence section $section',
        'This section records one bounded observation, its owner, and the next review step before stable release.',
        '- Evidence is retained locally',
        '- External acceptance remains explicit',
      ],
      '## Verification checklist',
      '- Review the packaged release evidence.',
      '- Complete the named human acceptance gates.',
      '- Keep unresolved risks visible to the release owner.',
    ].join('\n\n');
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-long-transcript-visual',
            threadId: thread.id,
            requestId: 'request-long-transcript-visual',
            userMessageId: 'message-long-transcript-visual',
            prompt: 'Summarize the release readiness evidence.',
            model: 'test-model',
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.completed,
            events: [
              StudioTurnEvent.userMessage(
                id: 'user-long-transcript-visual',
                turnId: 'turn-long-transcript-visual',
                requestId: 'request-long-transcript-visual',
                threadId: thread.id,
                content: 'Summarize the release readiness evidence.',
                timestamp: timestamp,
              ),
              StudioTurnEvent.assistantMessage(
                turnId: 'turn-long-transcript-visual',
                requestId: 'request-long-transcript-visual',
                threadId: thread.id,
                content: longResponse,
                timestamp: timestamp.add(const Duration(seconds: 1)),
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(seconds: 1)),
            completedAt: timestamp.add(const Duration(seconds: 1)),
          ),
          select: true,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
    await tester.pumpAndSettle();

    final checklist = find.text('Verification checklist');
    expect(checklist, findsOneWidget);
    expect(tester.getRect(checklist).top, greaterThanOrEqualTo(0));
    await expectLater(
      find.byType(StudioTaskView),
      matchesGoldenFile('goldens/studio_transcript_long_response.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('drawer keeps an empty work surface compact and actionable', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.artifacts);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(
          const Align(
            alignment: Alignment.topRight,
            child: StudioRightDrawer(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No artifacts yet'), findsOneWidget);
    expect(find.text('Start a task'), findsOneWidget);
    await expectLater(
      find.byType(StudioRightDrawer),
      matchesGoldenFile('goldens/studio_drawer_artifacts_empty.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('browser preview keeps its user-control boundary visible', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.browser);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(
          const Align(
            alignment: Alignment.topRight,
            child: StudioRightDrawer(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Open a browser preview'), findsOneWidget);
    expect(
      find.textContaining('never gives the assistant browser control'),
      findsOneWidget,
    );
    expect(find.text('Open sources'), findsOneWidget);
    await expectLater(
      find.byType(StudioRightDrawer),
      matchesGoldenFile('goldens/studio_drawer_browser_empty.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('browser preview refuses to load a blocked origin', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final browser = container.read(studioBrowserProvider.notifier);
    expect(browser.open('https://blocked.example/release-notes'), isTrue);
    browser.blockCurrentSite();
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.browser);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(
          const Align(
            alignment: Alignment.topRight,
            child: StudioRightDrawer(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Site blocked'), findsOneWidget);
    expect(
      find.text('Allow this site from the browser toolbar to load it.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Site permission'), findsOneWidget);
    await expectLater(
      find.byType(StudioRightDrawer),
      matchesGoldenFile('goldens/studio_drawer_browser_blocked.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  for (final emptyCase in _emptyDrawerVisualCases) {
    testWidgets(
      'drawer keeps ${emptyCase.mode.name} empty-state action hierarchy visible',
      (tester) async {
        VisibilityDetectorController.instance.updateInterval = Duration.zero;
        await tester.binding.setSurfaceSize(const Size(420, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(studioRightDrawerProvider.notifier)
            .openMode(emptyCase.mode);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: studioGoldenHarness(
              const Align(
                alignment: Alignment.topRight,
                child: StudioRightDrawer(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(emptyCase.title), findsOneWidget);
        expect(find.text(emptyCase.actionLabel), findsOneWidget);
        await expectLater(
          find.byType(StudioRightDrawer),
          matchesGoldenFile('goldens/${emptyCase.goldenName}'),
        );
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }

  testWidgets('drawer keeps a populated artifact reviewable at a glance', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final artifact = GeneratedArtifact(
      id: 'artifact-visual',
      kind: GeneratedArtifactKind.report,
      status: GeneratedArtifactStatus.ready,
      fileName: 'release-readiness-report.md',
      filePath: '/fixtures/release-readiness-report.md',
      summary:
          'A focused release handoff with traceable checks, remaining risks, and a named review owner.',
      byteSize: 4096,
      previewRows: const [
        ['Gate', 'Status', 'Owner'],
        ['Packaged release probe', 'Recorded', 'Release engineering'],
        ['Accessibility review', 'Pending', 'Design operations'],
      ],
      sheetCount: 3,
      metadata: const {
        'qualityStatus': 'Review needed',
        'artifactPreviewSurface': 'Release readiness table',
        'artifactEvidenceReadiness': 'Cited evidence retained',
        'artifactPrimaryAction': 'Review remaining acceptance gates',
        'accessibilityStatus': 'Manual review required',
      },
      createdAt: DateTime.utc(2026, 7, 13, 15),
    );
    final source = artifact.toSourceArtifact();
    container.read(studioSourceArtifactProvider.notifier).add(source);
    container.read(studioRightDrawerProvider.notifier).openArtifact(source);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(
          const Align(
            alignment: Alignment.topRight,
            child: StudioRightDrawer(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('release-readiness-report.md'), findsOneWidget);
    expect(find.text('Release readiness table'), findsAtLeastNWidgets(1));
    expect(find.text('Review needed'), findsOneWidget);
    expect(find.text('Accessibility'), findsOneWidget);
    await expectLater(
      find.byType(StudioRightDrawer),
      matchesGoldenFile('goldens/studio_artifact_populated.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('drawer keeps completed command evidence reviewable', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Release verification');
    final timestamp = DateTime.utc(2026, 7, 13, 16);
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-command-visual',
            threadId: thread.id,
            requestId: 'request-command-visual',
            userMessageId: 'message-command-visual',
            prompt: 'Run the release verification.',
            model: 'test-model',
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.completed,
            createdAt: timestamp,
            updatedAt: timestamp,
            completedAt: timestamp,
          ),
          select: true,
        );
    final commands = container.read(commandRunProvider.notifier);
    commands.start(
      id: 'command-visual',
      command: 'flutter test test/release_gate_test.dart',
      requestId: 'request-command-visual',
      turnId: 'turn-command-visual',
      taskId: thread.taskId,
    );
    commands.append(
      'command-visual',
      CommandRunEventType.stdout,
      'Release checks passed.\nSigned bundle policy is ready for review.',
    );
    commands.finish(
      'command-visual',
      status: CommandRunStatus.succeeded,
      exitCode: 0,
    );
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.terminal);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(
          const Align(
            alignment: Alignment.topRight,
            child: StudioRightDrawer(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Command logs'), findsOneWidget);
    expect(find.text('flutter test test/release_gate_test.dart'), findsWidgets);
    expect(find.text('Release checks passed.'), findsOneWidget);
    expect(find.text('succeeded'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.byTooltip('Open drawer view'), findsOneWidget);
    expect(find.byTooltip('Collapse panel'), findsOneWidget);
    await expectLater(
      find.byType(StudioRightDrawer),
      matchesGoldenFile('goldens/studio_drawer_terminal_command.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('drawer keeps an active command visibly in progress', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Active verification');
    final timestamp = DateTime.utc(2026, 7, 14, 16, 20);
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-command-running-visual',
            threadId: thread.id,
            requestId: 'request-command-running-visual',
            userMessageId: 'message-command-running-visual',
            prompt: 'Run the bounded verification command.',
            model: 'test-model',
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.toolRunning,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
          select: true,
        );
    final commands = container.read(commandRunProvider.notifier);
    commands.start(
      id: 'command-running-visual',
      command: 'flutter test test/verification_gate_test.dart',
      requestId: 'request-command-running-visual',
      turnId: 'turn-command-running-visual',
      taskId: thread.taskId,
    );
    commands.append(
      'command-running-visual',
      CommandRunEventType.stdout,
      'Running the selected verification checks…',
    );
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.terminal);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(
          const Align(
            alignment: Alignment.topRight,
            child: StudioRightDrawer(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Command logs'), findsOneWidget);
    expect(
      find.text('flutter test test/verification_gate_test.dart'),
      findsWidgets,
    );
    expect(find.text('running'), findsOneWidget);
    expect(
      find.text('Running the selected verification checks…'),
      findsOneWidget,
    );
    await expectLater(
      find.byType(StudioRightDrawer),
      matchesGoldenFile('goldens/studio_drawer_terminal_running.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('transcript gives code and tables a review width', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(studioShellProvider.notifier).toggleRightProgressPanel();
    final threadController = container.read(studioThreadProvider.notifier);
    final thread = threadController.createBlankThread(title: 'Review widths');
    final timestamp = DateTime.utc(2026, 7, 11, 13);
    const prose = 'The review is ready. The normal explanation stays readable.';
    const code = '```dart\nfinal completed = true;\n```';
    const table =
        '| File | Status | Notes |\n| --- | --- | --- |\n| app.dart | Ready | Reviewed |';
    final turn = StudioTurn(
      id: 'turn-review-widths',
      threadId: thread.id,
      requestId: 'request-review-widths',
      userMessageId: 'message-review-widths',
      prompt: 'Show the review results.',
      model: 'test-model',
      contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
      status: StudioTurnStatus.completed,
      events: [
        StudioTurnEvent.userMessage(
          id: 'user-review-widths',
          turnId: 'turn-review-widths',
          requestId: 'request-review-widths',
          threadId: thread.id,
          content: 'Show the review results.',
          timestamp: timestamp,
        ),
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-review-widths',
          requestId: 'request-review-widths',
          threadId: thread.id,
          content: prose,
          timestamp: timestamp.add(const Duration(seconds: 1)),
        ),
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-review-widths',
          requestId: 'request-review-widths',
          threadId: thread.id,
          content: code,
          timestamp: timestamp.add(const Duration(seconds: 2)),
        ),
        StudioTurnEvent.assistantMessage(
          turnId: 'turn-review-widths',
          requestId: 'request-review-widths',
          threadId: thread.id,
          content: table,
          timestamp: timestamp.add(const Duration(seconds: 3)),
        ),
      ],
      createdAt: timestamp,
      updatedAt: timestamp.add(const Duration(seconds: 3)),
      completedAt: timestamp.add(const Duration(seconds: 3)),
    );
    threadController.upsertTurn(thread.id, turn, select: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(
            find.byKey(ValueKey('studio-assistant-prose-${prose.hashCode}')),
          )
          .width,
      StudioLayoutContract.proseWidth,
    );
    expect(
      tester
          .getSize(
            find.byKey(ValueKey('studio-assistant-review-${code.hashCode}')),
          )
          .width,
      StudioLayoutContract.reviewWidth,
    );
    expect(
      tester
          .getSize(
            find.byKey(ValueKey('studio-assistant-review-${table.hashCode}')),
          )
          .width,
      StudioLayoutContract.reviewWidth,
    );
    expect(
      tester.getSize(find.byType(StudioPromptComposer)).width,
      StudioLayoutContract.composerWidth,
    );
    await expectLater(
      find.byType(StudioTaskView),
      matchesGoldenFile('goldens/studio_transcript_review_width.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('pending approval keeps scoped actions visibly reviewable', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(studioShellProvider.notifier).toggleRightProgressPanel();
    final threadController = container.read(studioThreadProvider.notifier);
    final thread = threadController.createBlankThread(title: 'Approval review');
    final timestamp = DateTime.utc(2026, 7, 13, 12);
    final turn = StudioTurn(
      id: 'turn-pending-approval',
      threadId: thread.id,
      requestId: 'request-pending-approval',
      userMessageId: 'message-pending-approval',
      prompt: 'Run the focused verification suite.',
      model: 'test-model',
      contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
      status: StudioTurnStatus.waitingForApproval,
      events: [
        StudioTurnEvent.userMessage(
          id: 'user-pending-approval',
          turnId: 'turn-pending-approval',
          requestId: 'request-pending-approval',
          threadId: thread.id,
          content: 'Run the focused verification suite.',
          timestamp: timestamp,
        ),
        StudioTurnEvent.approval(
          turnId: 'turn-pending-approval',
          requestId: 'request-pending-approval',
          threadId: thread.id,
          request: ConfirmationRequest(
            id: 'approval-pending-visual',
            toolCall: const ToolCallInfo(
              id: 'tool-pending-approval',
              name: 'run_command',
              arguments: {'command': 'flutter test test/studio_*_test.dart'},
            ),
            preview: 'flutter test test/studio_*_test.dart',
            warnings: const [
              'Runs commands only in the current workspace for this turn.',
            ],
            timestamp: timestamp.add(const Duration(seconds: 1)),
          ),
          timestamp: timestamp.add(const Duration(seconds: 1)),
        ),
      ],
      createdAt: timestamp,
      updatedAt: timestamp.add(const Duration(seconds: 1)),
    );
    threadController.upsertTurn(thread.id, turn, select: true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review required'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Approve for this turn'), findsOneWidget);
    expect(find.text('Approve once'), findsOneWidget);
    await expectLater(
      find.byType(StudioTaskView),
      matchesGoldenFile('goldens/studio_pending_approval.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('streaming draft keeps the in-progress response readable', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Streaming response');
    const requestId = 'request-streaming-visual';
    final timestamp = DateTime.utc(2026, 7, 13, 13);
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-streaming-visual',
            threadId: thread.id,
            requestId: requestId,
            userMessageId: 'message-streaming-visual',
            prompt: 'Explain the active patch review.',
            model: 'test-model',
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.streaming,
            assistantDraft:
                'I found the active patch and am checking the changed files before recommending the next verification step.',
            events: [
              StudioTurnEvent.userMessage(
                id: 'user-streaming-visual',
                turnId: 'turn-streaming-visual',
                requestId: requestId,
                threadId: thread.id,
                content: 'Explain the active patch review.',
                timestamp: timestamp,
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(seconds: 1)),
          ),
          select: true,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('I found the active patch'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('studio-turn-turn-streaming-visual')),
      matchesGoldenFile('goldens/studio_streaming_draft.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('plan review keeps planned targets and acceptance visible', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Plan review');
    const requestId = 'request-plan-visual';
    final timestamp = DateTime.utc(2026, 7, 13, 13, 10);
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-plan-visual',
            threadId: thread.id,
            requestId: requestId,
            userMessageId: 'message-plan-visual',
            prompt: 'Plan the focused project repair.',
            model: 'test-model',
            intent: TurnIntent.plan,
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.reviewingPatch,
            events: [
              StudioTurnEvent.userMessage(
                id: 'user-plan-visual',
                turnId: 'turn-plan-visual',
                requestId: requestId,
                threadId: thread.id,
                content: 'Plan the focused project repair.',
                timestamp: timestamp,
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(seconds: 1)),
          ),
          select: true,
        );
    container
        .read(patchProposalProvider.notifier)
        .preserveProposal(
          ProposedPatchSet(
            id: 'plan-visual',
            title: 'Repair project opening flow',
            runId: requestId,
            edits: const [],
            createdAt: timestamp,
            planMarkdown:
                '# Plan\n\n1. Preserve the selected project.\n2. Verify the handoff.',
            plannedTargets: const [
              PlannedFileTarget(
                path: 'lib/state/workspace_session_provider.dart',
                intent: 'Preserve the selected project',
                operation: ProposedFileEditType.modify,
              ),
              PlannedFileTarget(
                path: 'test/workspace_open_provider_test.dart',
                intent: 'Verify the workspace handoff',
                operation: ProposedFileEditType.modify,
              ),
            ],
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repair project opening flow'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('studio-turn-turn-plan-visual')),
      matchesGoldenFile('goldens/studio_plan_review.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('patch conflict remains a distinct reviewable state', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Patch conflict');
    const requestId = 'request-conflict-visual';
    final timestamp = DateTime.utc(2026, 7, 13, 13, 20);
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-conflict-visual',
            threadId: thread.id,
            requestId: requestId,
            userMessageId: 'message-conflict-visual',
            prompt: 'Apply the reviewed edit.',
            model: 'test-model',
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.reviewingPatch,
            events: [
              StudioTurnEvent.userMessage(
                id: 'user-conflict-visual',
                turnId: 'turn-conflict-visual',
                requestId: requestId,
                threadId: thread.id,
                content: 'Apply the reviewed edit.',
                timestamp: timestamp,
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(seconds: 1)),
          ),
          select: true,
        );
    container
        .read(patchProposalProvider.notifier)
        .preserveProposal(
          ProposedPatchSet(
            id: 'conflict-visual',
            title: 'Update workspace handoff',
            runId: requestId,
            edits: const [
              ProposedFileEdit(
                path: 'lib/state/workspace_session_provider.dart',
                type: ProposedFileEditType.modify,
                before: 'final currentProject = oldProject;\n',
                after: 'final currentProject = selectedProject;\n',
                applyStatus: PatchApplyStatus.conflict,
                conflictMessage:
                    'The file changed after this patch was reviewed.',
              ),
            ],
            createdAt: timestamp,
            applyStatus: PatchApplyStatus.conflict,
            conflictMessage: 'The file changed after this patch was reviewed.',
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('changed after this patch was reviewed'),
      findsWidgets,
    );
    await expectLater(
      find.byKey(const ValueKey('studio-turn-turn-conflict-visual')),
      matchesGoldenFile('goldens/studio_patch_conflict.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('prepared patch keeps the reviewed change set actionable', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Review prepared update');
    const requestId = 'request-patch-ready-visual';
    final timestamp = DateTime.utc(2026, 7, 13, 13, 25);
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-patch-ready-visual',
            threadId: thread.id,
            requestId: requestId,
            userMessageId: 'message-patch-ready-visual',
            prompt: 'Prepare the reviewed project-history update.',
            model: 'test-model',
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.reviewingPatch,
            events: [
              StudioTurnEvent.userMessage(
                id: 'user-patch-ready-visual',
                turnId: 'turn-patch-ready-visual',
                requestId: requestId,
                threadId: thread.id,
                content: 'Prepare the reviewed project-history update.',
                timestamp: timestamp,
              ),
              StudioTurnEvent.assistantMessage(
                turnId: 'turn-patch-ready-visual',
                requestId: requestId,
                threadId: thread.id,
                content:
                    'I prepared a compact change set for your review before anything is written.',
                timestamp: timestamp.add(const Duration(seconds: 1)),
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(seconds: 1)),
          ),
          select: true,
        );
    container
        .read(patchProposalProvider.notifier)
        .preserveProposal(
          ProposedPatchSet(
            id: 'patch-ready-visual',
            title: 'Keep project history compact',
            runId: requestId,
            edits: const [
              ProposedFileEdit(
                path: 'lib/state/project_history_store.dart',
                type: ProposedFileEditType.modify,
                before: 'return visibleHistory;',
                after: 'return visibleHistory.take(pageSize).toList();',
              ),
              ProposedFileEdit(
                path: 'test/project_history_store_test.dart',
                type: ProposedFileEditType.create,
                after: 'void main() { /* verifies paging */ }',
              ),
            ],
            changedFiles: const [
              'lib/state/project_history_store.dart',
              'test/project_history_store_test.dart',
            ],
            diffSummary: '2 reviewed files: one modification and one test.',
            verificationSuggestions: const [
              'flutter test test/project_history_store_test.dart',
            ],
            createdAt: timestamp,
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Prepared 2 files'), findsOneWidget);
    expect(find.text('Apply changes'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('studio-turn-turn-patch-ready-visual')),
      matchesGoldenFile('goldens/studio_patch_prepared.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('applied patch keeps the verified outcome and next step visible', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Review applied update');
    const requestId = 'request-patch-applied-visual';
    final timestamp = DateTime.utc(2026, 7, 13, 13, 28);
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-patch-applied-visual',
            threadId: thread.id,
            requestId: requestId,
            userMessageId: 'message-patch-applied-visual',
            prompt: 'Apply the reviewed project-history update.',
            model: 'test-model',
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.completed,
            events: [
              StudioTurnEvent.userMessage(
                id: 'user-patch-applied-visual',
                turnId: 'turn-patch-applied-visual',
                requestId: requestId,
                threadId: thread.id,
                content: 'Apply the reviewed project-history update.',
                timestamp: timestamp,
              ),
              StudioTurnEvent.assistantMessage(
                turnId: 'turn-patch-applied-visual',
                requestId: requestId,
                threadId: thread.id,
                content:
                    'The reviewed update is applied. I kept the change scoped to project history and its test coverage.',
                timestamp: timestamp.add(const Duration(seconds: 1)),
              ),
              StudioTurnEvent.completionSummary(
                id: 'summary-patch-applied-visual',
                turnId: 'turn-patch-applied-visual',
                requestId: requestId,
                threadId: thread.id,
                title: 'Applied changes',
                detail:
                    'Applied 2 reviewed files. Recommended next step: run the focused project-history test.',
                timestamp: timestamp.add(const Duration(seconds: 2)),
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(seconds: 2)),
            completedAt: timestamp.add(const Duration(seconds: 2)),
          ),
          select: true,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Applied changes'), findsWidgets);
    expect(
      find.textContaining('Recommended next step: run the focused'),
      findsWidgets,
    );
    await expectLater(
      find.byKey(const ValueKey('studio-turn-turn-patch-applied-visual')),
      matchesGoldenFile('goldens/studio_patch_applied.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('failed turn keeps the recovery detail visible', (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Recover from provider failure');
    const requestId = 'request-error-visual';
    final timestamp = DateTime.utc(2026, 7, 13, 13, 30);
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-error-visual',
            threadId: thread.id,
            requestId: requestId,
            userMessageId: 'message-error-visual',
            prompt: 'Check the provider connection.',
            model: 'test-model',
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.failed,
            lastError:
                'The provider connection timed out before the first byte.',
            events: [
              StudioTurnEvent.userMessage(
                id: 'user-error-visual',
                turnId: 'turn-error-visual',
                requestId: requestId,
                threadId: thread.id,
                content: 'Check the provider connection.',
                timestamp: timestamp,
              ),
              StudioTurnEvent.error(
                turnId: 'turn-error-visual',
                requestId: requestId,
                threadId: thread.id,
                detail:
                    'The provider connection timed out before the first byte. Check the connection and try again.',
                timestamp: timestamp.add(const Duration(seconds: 1)),
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(seconds: 1)),
          ),
          select: true,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('provider connection timed out'), findsWidgets);
    await expectLater(
      find.byKey(const ValueKey('studio-turn-turn-error-visual')),
      matchesGoldenFile('goldens/studio_turn_failure.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('interrupted turn keeps the safe recovery action visible', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Recover verification after restart');
    const requestId = 'request-interrupted-visual';
    final timestamp = DateTime.utc(2026, 7, 13, 13, 40);
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-interrupted-visual',
            threadId: thread.id,
            requestId: requestId,
            userMessageId: 'message-interrupted-visual',
            prompt: 'Run the focused verification after applying the patch.',
            model: 'test-model',
            intent: TurnIntent.verify,
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.interrupted,
            assistantDraft: 'The focused verification was ready to run.',
            recoveryCheckpoint: StudioTurnRecoveryCheckpoint(
              phase: StudioTurnPhase.waitingApproval,
              capturedAt: timestamp.add(const Duration(seconds: 1)),
              streamedCharacters: 47,
              completedToolCount: 1,
              pendingApprovalId: 'approval-interrupted-visual',
              pendingToolCallId: 'tool-interrupted-visual',
              pendingToolName: 'run_command',
              commandRunId: 'command-interrupted-visual',
              action: StudioTurnRecoveryAction.rerunVerification,
            ),
            events: [
              StudioTurnEvent.userMessage(
                id: 'user-interrupted-visual',
                turnId: 'turn-interrupted-visual',
                requestId: requestId,
                threadId: thread.id,
                content:
                    'Run the focused verification after applying the patch.',
                timestamp: timestamp,
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(seconds: 1)),
            completedAt: timestamp.add(const Duration(seconds: 1)),
          ),
          select: true,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Task interrupted — Rerun verification'), findsOneWidget);
    expect(find.textContaining('The old approval expired'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('studio-turn-turn-interrupted-visual')),
      matchesGoldenFile('goldens/studio_interrupted_recovery.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('no-project home retains the shipped starting surface', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Where should we start?'), findsOneWidget);
    expect(find.text('No project selected'), findsOneWidget);
    await expectLater(
      find.byType(StudioShell),
      matchesGoldenFile('goldens/studio_home_no_project.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('settings retains its production-dark control hierarchy', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(studioShellProvider.notifier).openSettings();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Studio settings'), findsOneWidget);
    expect(find.byTooltip('Choose model'), findsOneWidget);
    expect(find.text('New chat'), findsOneWidget);
    expect(find.byTooltip('Open project folder'), findsOneWidget);
    await expectLater(
      find.byType(StudioShell),
      matchesGoldenFile('goldens/studio_settings.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('settings keeps offline connector recovery visible', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(studioShellProvider.notifier).openSettings();
    container
        .read(settingsProvider.notifier)
        .setConnectorHealth(
          ConnectorHealth(
            status: ConnectorHealthStatus.requestFailed,
            message: 'Connection check failed. Verify the network and retry.',
            checkedAt: DateTime.utc(2026, 7, 14, 9, 30),
            errorCategory: ConnectorHealthErrorCategory.offline,
            retryAdvice:
                'Retry the connection check. If it repeats, export the redacted support bundle.',
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connector health'), findsOneWidget);
    expect(find.text('requestFailed'), findsOneWidget);
    expect(find.textContaining('Verify the network and retry'), findsOneWidget);
    expect(
      find.textContaining('export the redacted support bundle'),
      findsOneWidget,
    );
    await expectLater(
      find.byType(StudioShell),
      matchesGoldenFile('goldens/studio_settings_offline_recovery.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('update settings keep active-work deferral visually explicit', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(640, 460));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        macosUpdateServiceProvider.overrideWithValue(
          _VisualUpdateService(
            const CircuitUpdateStatus(
              configured: true,
              channel: CircuitUpdateChannel.beta,
              automaticChecks: true,
              allowsAutomaticDownloads: true,
              canCheck: true,
              mutationActive: true,
              installDeferred: true,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(
          const Padding(
            padding: EdgeInsets.all(24),
            child: StudioUpdateSettingsPanel(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('App updates'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Check now'),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.textContaining('Updates wait until active Studio work'),
      findsOneWidget,
    );
    await expectLater(
      find.byType(StudioUpdateSettingsPanel),
      matchesGoldenFile('goldens/studio_update_deferred.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('research source repair remains visible in the Progress drawer', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final timestamp = DateTime.utc(2026, 7, 14, 9, 30);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Research rollout risks');
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-research-progress-visual',
            threadId: thread.id,
            requestId: 'request-research-progress-visual',
            userMessageId: 'message-research-progress-visual',
            prompt: 'Compare official rollout guidance from direct sources.',
            model: 'test-model',
            intent: TurnIntent.ask,
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.waitingForModel,
            steps: [
              TurnStepRecord(
                step: TurnStep.researchPlan,
                status: TurnStepStatus.completed,
                title: 'Research plan ready',
                startedAt: timestamp,
                completedAt: timestamp.add(const Duration(seconds: 3)),
              ),
              TurnStepRecord(
                step: TurnStep.sourceAcquisition,
                status: TurnStepStatus.running,
                title: 'Independent-source retry',
                detail:
                    'Checking one more approved source path before finalizing evidence.',
                startedAt: timestamp.add(const Duration(seconds: 4)),
              ),
              TurnStepRecord(
                step: TurnStep.evidenceReview,
                status: TurnStepStatus.queued,
                title: 'Evidence review',
                startedAt: timestamp.add(const Duration(seconds: 4)),
              ),
            ],
            events: [
              StudioTurnEvent.progress(
                turnId: 'turn-research-progress-visual',
                requestId: 'request-research-progress-visual',
                threadId: thread.id,
                title: 'Independent-source retry',
                detail:
                    'Checking one more approved source path before finalizing evidence.',
                timestamp: timestamp.add(const Duration(seconds: 5)),
              ),
            ],
            providerDiagnostics: [
              ProviderLifecycleEvent(
                requestId: 'request-research-progress-visual',
                turnId: 'turn-research-progress-visual',
                kind: ProviderLifecycleEventKind.outcomeRepair,
                timestamp: timestamp.add(const Duration(seconds: 5)),
                model: 'test-model',
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(seconds: 5)),
          ),
          select: true,
        );
    container
        .read(studioRightDrawerProvider.notifier)
        .openMode(StudioDrawerMode.progress);
    final selectedResearchTurn = container
        .read(studioThreadProvider)
        .selectedThread
        ?.turns
        .singleOrNull;
    expect(selectedResearchTurn?.steps, hasLength(3));
    expect(
      selectedResearchTurn?.events.single.title,
      'Independent-source retry',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(
          const Align(
            alignment: Alignment.topRight,
            child: StudioRightDrawer(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Independent-source retry'), findsOneWidget);
    expect(find.text('1 model retry'), findsOneWidget);
    expect(
      find.text(
        'Checking one more approved source path before finalizing evidence.',
      ),
      findsOneWidget,
    );
    await expectLater(
      find.byType(StudioRightDrawer),
      matchesGoldenFile('goldens/studio_research_source_repair.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('research outcome keeps citations and conflict review readable', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Rollout guidance research');
    final timestamp = DateTime.utc(2026, 7, 14, 16);
    const response = '''
## Research conclusion

A staged rollout with explicit rollback criteria is the supported path for this change.

## Sources

- [Release safety guide](https://standards.example/release-safety) — checked 2026-07-14
- [Operations recovery guide](https://operations.example/recovery) — checked 2026-07-14

## Evidence table

| Claim | Direct evidence | Status |
| --- | --- | --- |
| Use staged rollout gates | Two independent guides | Corroborated |

## Conflict review

No material conflicts identified.
''';
    container
        .read(studioThreadProvider.notifier)
        .upsertTurn(
          thread.id,
          StudioTurn(
            id: 'turn-research-outcome-visual',
            threadId: thread.id,
            requestId: 'request-research-outcome-visual',
            userMessageId: 'message-research-outcome-visual',
            prompt: 'Compare direct sources for safe rollout guidance.',
            model: 'test-model',
            intent: TurnIntent.ask,
            contextSummary: const StudioContextSummary(projectLabel: 'Fixture'),
            status: StudioTurnStatus.completed,
            events: [
              StudioTurnEvent.userMessage(
                id: 'user-research-outcome-visual',
                turnId: 'turn-research-outcome-visual',
                requestId: 'request-research-outcome-visual',
                threadId: thread.id,
                content: 'Compare direct sources for safe rollout guidance.',
                timestamp: timestamp,
              ),
              StudioTurnEvent.assistantMessage(
                turnId: 'turn-research-outcome-visual',
                requestId: 'request-research-outcome-visual',
                threadId: thread.id,
                content: response,
                timestamp: timestamp.add(const Duration(seconds: 1)),
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp.add(const Duration(seconds: 1)),
            completedAt: timestamp.add(const Duration(seconds: 1)),
          ),
          select: true,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioTaskView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Research conclusion'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Evidence table'), findsOneWidget);
    expect(find.text('Conflict review'), findsOneWidget);
    expect(find.text('No material conflicts identified.'), findsOneWidget);
    await expectLater(
      find.byType(StudioTaskView),
      matchesGoldenFile('goldens/studio_research_cited_outcome.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('rail history retains recent project task hierarchy', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const projectPath = '/fixtures/visual-network';
    final timestamp = DateTime.utc(2026, 7, 13, 14);
    final threads = [
      for (final (index, title) in [
        'Audit the provider contract',
        'Review the latest patch',
        'Plan release validation',
        'Inspect project history',
        'Summarize accessibility gaps',
        'Prepare the handoff',
      ].indexed)
        StudioThread(
          id: 'rail-visual-$index',
          title: title,
          status: index == 0
              ? StudioThreadStatus.streaming
              : StudioThreadStatus.done,
          createdAt: timestamp.add(Duration(minutes: index)),
          updatedAt: timestamp.add(Duration(minutes: index)),
        ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileTreeProvider.overrideWith(
            () => _VisualFileTreeNotifier(projectPath),
          ),
          studioThreadProvider.overrideWith(
            () => _VisualStudioThreadController(
              threads: threads,
              selectedThreadId: threads.last.id,
            ),
          ),
          studioProjectHistoryProvider.overrideWith(
            () => _VisualProjectHistoryController(
              projectPath: projectPath,
              threads: threads,
            ),
          ),
          studioRailNowProvider.overrideWithValue(
            () => timestamp.add(const Duration(hours: 2)),
          ),
        ],
        child: studioGoldenHarness(const StudioLeftRail()),
      ),
    );
    // The streaming task intentionally has an indeterminate status indicator,
    // so settling would wait forever. Advance a fixed amount instead to keep
    // the captured animation frame deterministic.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('visual-network'), findsOneWidget);
    expect(find.text('Audit the provider contract'), findsOneWidget);
    expect(find.text('Prepare the handoff'), findsOneWidget);
    await expectLater(
      find.byType(StudioLeftRail),
      matchesGoldenFile('goldens/studio_rail_history.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('rail distinguishes queued background work from active work', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const projectPath = '/fixtures/queued-background';
    final timestamp = DateTime.utc(2026, 7, 14, 9);
    final tasks = [
      AgentTask(
        id: 'background-running-visual',
        mascotAlias: 'Benny',
        profile: AgentTaskProfile.investigate,
        status: AgentTaskStatus.running,
        goal: 'Review the current workspace',
        workspaceRoot: projectPath,
        backgroundExecutionRequested: true,
        createdAt: timestamp,
      ),
      AgentTask(
        id: 'background-queued-visual',
        mascotAlias: 'Clark',
        profile: AgentTaskProfile.verify,
        status: AgentTaskStatus.queued,
        goal: 'Run verification after review',
        workspaceRoot: projectPath,
        backgroundExecutionRequested: true,
        createdAt: timestamp.add(const Duration(minutes: 1)),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentWorkspaceProvider.overrideWith(
            () => _VisualAgentWorkspaceController(tasks),
          ),
          fileTreeProvider.overrideWith(
            () => _VisualFileTreeNotifier(projectPath),
          ),
          studioThreadProvider.overrideWith(
            () => _VisualStudioThreadController(
              threads: const [],
              selectedThreadId: null,
            ),
          ),
          studioProjectHistoryProvider.overrideWith(
            () => _VisualProjectHistoryController(
              projectPath: projectPath,
              threads: const [],
            ),
          ),
          studioRailNowProvider.overrideWithValue(
            () => timestamp.add(const Duration(hours: 2)),
          ),
        ],
        child: studioGoldenHarness(const StudioLeftRail()),
      ),
    );
    // The running task intentionally animates. Capture one deterministic
    // frame while preserving the non-animated queued clock indicator.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Review the current workspace'), findsOneWidget);
    expect(find.text('Run verification after review'), findsOneWidget);
    expect(find.bySemanticsLabel('Task status: Queued'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    await expectLater(
      find.byType(StudioLeftRail),
      matchesGoldenFile('goldens/studio_rail_background_queue.png'),
    );
    await tester.pump(const Duration(seconds: 1));
  });
}

const _emptyDrawerVisualCases = <_EmptyDrawerVisualCase>[
  _EmptyDrawerVisualCase(
    mode: StudioDrawerMode.code,
    title: 'No file selected',
    actionLabel: 'Open files',
    goldenName: 'studio_drawer_code_empty.png',
  ),
  _EmptyDrawerVisualCase(
    mode: StudioDrawerMode.diff,
    title: 'No changes',
    actionLabel: 'Start a task',
    goldenName: 'studio_drawer_diff_empty.png',
  ),
  _EmptyDrawerVisualCase(
    mode: StudioDrawerMode.files,
    title: 'No project selected',
    actionLabel: 'Back to projects',
    goldenName: 'studio_drawer_files_empty.png',
  ),
  _EmptyDrawerVisualCase(
    mode: StudioDrawerMode.sources,
    title: 'No sources yet',
    actionLabel: 'Start a task',
    goldenName: 'studio_drawer_sources_empty.png',
  ),
  _EmptyDrawerVisualCase(
    mode: StudioDrawerMode.context,
    title: 'No context yet',
    actionLabel: 'Start a task',
    goldenName: 'studio_drawer_context_empty.png',
  ),
];

class _EmptyDrawerVisualCase {
  final StudioDrawerMode mode;
  final String title;
  final String actionLabel;
  final String goldenName;

  const _EmptyDrawerVisualCase({
    required this.mode,
    required this.title,
    required this.actionLabel,
    required this.goldenName,
  });
}

class _VisualFileTreeNotifier extends FileTreeNotifier {
  final String projectPath;

  _VisualFileTreeNotifier(this.projectPath);

  @override
  FileTreeState build() => FileTreeState(rootPath: projectPath);
}

class _VisualAgentWorkspaceController extends AgentWorkspaceController {
  final List<AgentTask> tasks;

  _VisualAgentWorkspaceController(this.tasks);

  @override
  AgentWorkspaceState build() => AgentWorkspaceState(tasks: tasks);
}

class _VisualStudioThreadController extends StudioThreadController {
  final List<StudioThread> threads;
  final String? selectedThreadId;

  _VisualStudioThreadController({
    required this.threads,
    required this.selectedThreadId,
  });

  @override
  StudioThreadState build() =>
      StudioThreadState(threads: threads, selectedThreadId: selectedThreadId);
}

class _VisualProjectHistoryController extends StudioProjectHistoryController {
  final String projectPath;
  final List<StudioThread> threads;

  _VisualProjectHistoryController({
    required this.projectPath,
    required this.threads,
  });

  @override
  StudioProjectHistoryState build() => StudioProjectHistoryState(
    byPath: {
      projectPath: StudioProjectHistory(
        threads: threads,
        totalThreadCount: threads.length,
      ),
    },
  );
}

class _VisualUpdateService extends MacosUpdateService {
  final CircuitUpdateStatus updateStatus;

  _VisualUpdateService(this.updateStatus) : super(isSupported: () => true);

  @override
  Future<CircuitUpdateStatus> status() async => updateStatus;
}
