import 'dart:async';
import 'dart:io';

import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/agent/security/agent_tool_permission_policy.dart'
    as tool_policy;
import 'package:circuit_ide/agent/studio_agent_environment.dart';
import 'package:circuit_ide/app.dart';
import 'package:circuit_ide/core/utils/platform_utils.dart';
import 'package:circuit_ide/enums/connection_status.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/services/event_bus.dart';
import 'package:circuit_ide/services/project_directory_picker.dart';
import 'package:circuit_ide/state/agent_turn_runtime_provider.dart';
import 'package:circuit_ide/state/command_run_provider.dart';
import 'package:circuit_ide/state/connection_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/settings_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/workspace_session_provider.dart';
import 'package:circuit_ide/ui/studio/studio_rail_row.dart' show StudioRailRow;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'desktop Studio journey streams, searches, reviews, and applies a project patch',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final originalConfigDir = PlatformUtils.configDirOverride;
      final originalDebounce =
          StudioThreadController.debugPersistDebounceOverride;
      final root = await Directory.systemTemp.createTemp('circuit-ui-journey-');
      final config = await Directory(p.join(root.path, 'config')).create();
      final project = await Directory(
        p.join(root.path, 'journey-project'),
      ).create();
      await Directory(p.join(project.path, 'lib')).create();
      await File(
        p.join(project.path, 'lib', 'main.dart'),
      ).writeAsString('void main() {}\n');
      PlatformUtils.configDirOverride = config.path;
      StudioThreadController.debugPersistDebounceOverride = Duration.zero;

      final provider = _DesktopJourneyProvider();
      final directoryPicker = _DesktopJourneyDirectoryPicker(project.path);
      final events = EventBus();
      final container = ProviderContainer(
        overrides: [
          projectDirectoryPickerProvider.overrideWithValue(directoryPicker),
          studioAgentEnvironmentOverrideProvider.overrideWithValue(
            StudioAgentEnvironment(
              provider: provider,
              model: 'gpt-5-nano',
              workspaceRoot: project.path,
              permissionPolicy: tool_policy.AgentToolPermissionPolicy(
                workingDir: project.path,
              ),
              events: events,
              onProviderEvent: (_) {},
            ),
          ),
        ],
      );
      addTearDown(() async {
        PlatformUtils.configDirOverride = originalConfigDir;
        StudioThreadController.debugPersistDebounceOverride = originalDebounce;
        try {
          await root.delete(recursive: true);
        } on FileSystemException catch (error) {
          if (error.osError?.errorCode != 2) rethrow;
        }
      });
      var initialResourcesDisposed = false;
      void disposeInitialResources() {
        if (initialResourcesDisposed) return;
        initialResourcesDisposed = true;
        container.dispose();
        events.dispose();
      }

      // Cleanup runs in reverse registration order. Dispose state owners before
      // removing their persistence directory so an early assertion failure
      // cannot race an in-flight atomic history write.
      addTearDown(disposeInitialResources);

      container
          .read(connectionStatusProvider.notifier)
          .set(ConnectionStatus.connected);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CircuitIDEApp(),
        ),
      );
      await tester.pumpAndSettle();

      final openProject = find.text('Open project folder');
      expect(openProject, findsOneWidget);
      await tester.tap(openProject);
      await _pumpUntil(
        tester,
        () =>
            container.read(fileTreeProvider).rootPath == project.path &&
            container
                .read(settingsProvider)
                .recentProjects
                .contains(project.path),
      );
      expect(directoryPicker.chooseCount, 1);
      expect(
        container.read(settingsProvider).recentProjects,
        contains(project.path),
      );
      await tester.pumpAndSettle();
      expect(find.text('journey-project'), findsWidgets);
      final composer = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Ask, plan, or describe work',
      );
      expect(composer, findsOneWidget);

      await tester.tap(composer);
      await tester.enterText(
        composer,
        'Explain lib/main.dart in this project.',
      );
      await tester.pump();
      final submit = find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.startsWith('Start Circuit task') ?? false),
      );
      expect(submit, findsOneWidget);
      await tester.tap(submit);
      await _pumpUntil(
        tester,
        () => find
            .text('The project entrypoint is ready for the next change.')
            .evaluate()
            .isNotEmpty,
      );

      expect(provider.requests, hasLength(1));
      expect(
        find.text('The project entrypoint is ready for the next change.'),
        findsOneWidget,
      );
      await _pumpUntil(
        tester,
        () => !container.read(agentTurnRuntimeProvider).hasActiveStudioRequest,
      );
      final thread = container.read(studioThreadProvider).selectedThread;
      expect(thread, isNotNull);
      expect(thread!.turns, hasLength(1));
      expect(thread.turns.single.prompt, contains('Explain lib/main.dart'));

      await tester.tap(find.text('Search').first);
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search chats',
      );
      expect(search, findsOneWidget);
      await tester.enterText(search, 'Explain lib/main.dart');
      await tester.pumpAndSettle();

      expect(find.text(thread.title), findsWidgets);

      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      final followUp = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Ask for follow-up changes',
      );
      expect(followUp, findsOneWidget);
      await tester.tap(find.byTooltip('Task mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Code').last);
      await tester.pumpAndSettle();
      expect(container.read(studioShellProvider).promptMode.name, 'code');
      await tester.tap(followUp);
      await tester.enterText(
        followUp,
        'Create lib/journey_marker.dart with a JourneyMarker widget.',
      );
      await tester.pump();
      expect(container.read(studioShellProvider).promptMode.name, 'code');
      final followUpSubmit = find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.startsWith('Send follow-up') ?? false),
      );
      expect(followUpSubmit, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _pumpUntil(
        tester,
        () => !container.read(agentTurnRuntimeProvider).hasActiveStudioRequest,
      );
      final patchTurn = container
          .read(studioThreadProvider)
          .selectedThread!
          .turns
          .firstWhere(
            (turn) => turn.displayPrompt.contains('JourneyMarker widget'),
          );
      expect(
        patchTurn.status.name,
        'completed',
        reason: 'Patch request did not complete: ${patchTurn.lastError}',
      );
      await tester.pumpAndSettle();
      final proposals = container.read(patchProposalProvider);
      final proposedPatch = proposals.active;
      expect(proposedPatch, isNotNull);
      final proposedPatchId = proposedPatch!.id;
      final turns = container
          .read(studioThreadProvider)
          .selectedThread!
          .turns
          .map((turn) => '${turn.intent.name}:${turn.displayPrompt}')
          .join(' | ');
      expect(
        find.text('Apply changes'),
        findsOneWidget,
        reason:
            'No reviewable patch card was rendered (intent=${patchTurn.intent.name}, active=${proposals.active?.title}, history=${proposals.history.length}, toolResults=${patchTurn.toolResults.length}, requests=${provider.requests.length}, turns=$turns, providerTools=${provider.exposedTools}).',
      );

      await tester.tap(find.text('Apply changes').first);
      final marker = File(p.join(project.path, 'lib', 'journey_marker.dart'));
      await _pumpUntil(tester, () => marker.existsSync());
      expect(
        await marker.readAsString(),
        'const desktopJourneyMarker = true;\n',
      );
      await _pumpUntil(
        tester,
        () => container
            .read(patchProposalProvider)
            .history
            .where((patch) => patch.id == proposedPatchId)
            .any(
              (patch) =>
                  patch.applyStatus == PatchApplyStatus.applied &&
                  patch.verificationRequested &&
                  patch.verificationSuggestions.any(
                    (command) => command == 'npm --version',
                  ),
            ),
      );

      // Verification is a distinct user-approved action after the patch
      // transaction. The real command runner must receive that scoped grant
      // and return a completed verification turn through the production UI.
      final runVerification = find.text('Run verification');
      expect(runVerification, findsOneWidget);
      await tester.ensureVisible(runVerification);
      await tester.tap(runVerification);
      await _pumpUntil(
        tester,
        () => container
            .read(studioThreadProvider)
            .selectedThread!
            .turns
            .any(
              (turn) =>
                  turn.intent.name == 'verify' &&
                  turn.status.name == 'completed',
            ),
      );
      final verificationRun = container
          .read(commandRunProvider)
          .values
          .singleWhere((run) => run.command == 'npm --version');
      expect(
        verificationRun.status.name,
        'succeeded',
        reason: verificationRun.combinedOutput,
      );
      expect(verificationRun.combinedOutput, isNotEmpty);

      final appliedThread = container
          .read(studioThreadProvider)
          .selectedThread!;
      expect(appliedThread.taskId, isNull);
      final activeRow = _railRowFor(appliedThread.title);
      expect(activeRow, findsOneWidget);
      await tester.tap(activeRow);
      await tester.pumpAndSettle();
      expect(
        container.read(studioThreadProvider).selectedThreadId,
        appliedThread.id,
      );
      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(_threadById(container, appliedThread.id).archived, isTrue);

      await tester.tap(find.text('Filter tasks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show archived tasks'));
      await tester.pumpAndSettle();
      final archivedRow = _railRowFor(appliedThread.title);
      expect(archivedRow, findsOneWidget);
      await tester.tap(archivedRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore to rail'));
      await tester.pumpAndSettle();
      expect(_threadById(container, appliedThread.id).archived, isFalse);

      await tester.tap(find.text('Filter tasks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show archived tasks'));
      await tester.pumpAndSettle();
      final restoredRow = _railRowFor(appliedThread.title);
      expect(restoredRow, findsOneWidget);
      await tester.tap(restoredRow);
      await tester.pumpAndSettle();
      expect(
        container.read(studioThreadProvider).selectedThreadId,
        appliedThread.id,
      );

      // A restart must recover the restored task from the durable Studio
      // store, rather than relying on the live provider container.
      await tester.runAsync(
        () => _waitForPersistedThread(
          project.path,
          threadId: appliedThread.id,
          archived: false,
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      disposeInitialResources();

      final restartedEvents = EventBus();
      final restartedContainer = ProviderContainer(
        overrides: [
          studioAgentEnvironmentOverrideProvider.overrideWithValue(
            StudioAgentEnvironment(
              provider: provider,
              model: 'gpt-5-nano',
              workspaceRoot: project.path,
              permissionPolicy: tool_policy.AgentToolPermissionPolicy(
                workingDir: project.path,
              ),
              events: restartedEvents,
              onProviderEvent: (_) {},
            ),
          ),
        ],
      );
      var restartedResourcesDisposed = false;
      void disposeRestartedResources() {
        if (restartedResourcesDisposed) return;
        restartedResourcesDisposed = true;
        restartedContainer.dispose();
        restartedEvents.dispose();
      }

      addTearDown(disposeRestartedResources);
      await tester.runAsync(() async {
        final workspace = await restartedContainer
            .read(workspaceSessionProvider.notifier)
            .openWorkspaceAndBindAgent(project.path);
        expect(workspace.success, isTrue);
        await restartedContainer.read(studioThreadProvider.notifier).reload();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: restartedContainer,
          child: const CircuitIDEApp(),
        ),
      );
      await _pumpUntil(
        tester,
        () => _railRowFor(appliedThread.title).evaluate().isNotEmpty,
      );
      final persistedThread = _threadById(restartedContainer, appliedThread.id);
      expect(persistedThread.archived, isFalse);
      // The thread retains the original request, the applied code change, and
      // the separately approved verification run.  Verifying the exact set
      // protects persistence without treating the completed verification turn
      // as an accidental extra message.
      expect(persistedThread.turns, hasLength(3));
      expect(
        persistedThread.turns.any(
          (turn) => turn.displayPrompt.contains('Explain lib/main.dart'),
        ),
        isTrue,
      );
      expect(
        persistedThread.turns.any(
          (turn) => turn.displayPrompt.contains('JourneyMarker widget'),
        ),
        isTrue,
      );
      final persistedVerificationTurn = persistedThread.turns.singleWhere(
        (turn) => turn.intent.name == 'verify',
      );
      expect(persistedVerificationTurn.status.name, 'completed');

      final restartedRow = _railRowFor(appliedThread.title);
      expect(restartedRow, findsOneWidget);
      await tester.tap(restartedRow);
      await tester.pumpAndSettle();
      expect(
        restartedContainer.read(studioThreadProvider).selectedThreadId,
        appliedThread.id,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      disposeRestartedResources();
    },
  );
}

StudioThread _threadById(ProviderContainer container, String id) => container
    .read(studioThreadProvider)
    .threads
    .singleWhere((thread) => thread.id == id);

Finder _railRowFor(String title) => find.byWidgetPredicate(
  (widget) => widget is StudioRailRow && widget.label == title,
);

Future<void> _waitForPersistedThread(
  String projectPath, {
  required String threadId,
  required bool archived,
}) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    final threads = await StudioThreadStore().load(projectPath);
    final thread = threads.where((item) => item.id == threadId).firstOrNull;
    if (thread?.archived == archived) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Timed out waiting for the Studio task to persist before restart.');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 80,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (condition()) return;
  }
  fail('Timed out waiting for the desktop Studio journey to settle.');
}

class _DesktopJourneyDirectoryPicker implements ProjectDirectoryPicker {
  final String path;
  int chooseCount = 0;

  _DesktopJourneyDirectoryPicker(this.path);

  @override
  Future<String?> chooseDirectory({String? initialDirectory}) async {
    chooseCount++;
    return path;
  }
}

class _DesktopJourneyProvider implements AIProvider {
  final requests = <List<ChatMessage>>[];
  final exposedTools = <List<String>>[];
  var _round = 0;

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano', contextWindow: 1000),
  ];

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'desktop-journey',
    displayName: 'Desktop journey fixture',
    shortName: 'journey',
  );

  @override
  bool get isConnected => true;

  @override
  String get name => 'desktop-journey';

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    requests.add(List<ChatMessage>.from(messages));
    exposedTools.add(tools.map((tool) => tool.name).toList(growable: false));
    final round = _round++;
    if (round == 1) {
      yield const ChatChunk(
        toolCallIndex: 0,
        toolCallId: 'desktop-journey-inspect',
        toolCallName: 'read_file',
        toolCallArguments: '{"path":"lib/main.dart"}',
      );
      yield const ChatChunk(isDone: true, finishReason: 'tool_calls');
      return;
    }
    if (round > 1) {
      yield const ChatChunk(
        toolCallIndex: 0,
        toolCallId: 'desktop-journey-patch',
        toolCallName: 'propose_patch',
        toolCallArguments:
            '{"title":"Create desktop journey marker","summary":"Add the requested local marker.","verification_steps":["npm --version"],"files":[{"path":"lib/journey_marker.dart","intent":"Create a local desktop integration marker","operation":"create","content":"const desktopJourneyMarker = true;\\n"}]}',
      );
      yield const ChatChunk(isDone: true, finishReason: 'tool_calls');
      return;
    }
    yield const ChatChunk(content: 'The project entrypoint is ready ');
    await Future<void>.delayed(const Duration(milliseconds: 15));
    yield const ChatChunk(content: 'for the next change.');
    yield const ChatChunk(isDone: true, finishReason: 'stop');
  }

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void disconnect() {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime.now(),
  );

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'gpt-5-nano', displayName: 'GPT-5 nano'),
  ];
}
