import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/core/utils/platform_utils.dart';
import 'package:circuit_ide/agent/security/macos_execution_boundary.dart';
import 'package:circuit_ide/models/accepted_plan_context.dart';
import 'package:circuit_ide/models/command_run.dart';
import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/models/reviewed_edit.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/command_run_provider.dart';
import 'package:circuit_ide/state/patch_proposal_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String? _configuredBrokerPath;

const _soakArtifactKinds = [
  GeneratedArtifactKind.markdown,
  GeneratedArtifactKind.pdf,
  GeneratedArtifactKind.docx,
  GeneratedArtifactKind.excel,
  GeneratedArtifactKind.powerPoint,
];

const _soakArtifactContent = '''
# Soak Delivery Review

This deterministic artifact verifies durable output generation, publication,
and restart recovery without using customer content.

## Decision

Keep the scoped marker after the verification command succeeds.

## Evidence

| Check | Result | Owner |
| --- | --- | --- |
| Reviewed patch | Applied | Studio |
| Verification command | Passed | Command boundary |
| Durable restart | Pending reload | Persistence |

## Next Steps

- Reload the thread and validate the generated artifact metadata.
- Confirm the generated file remains readable before temporary cleanup.

## Sources

- Deterministic local soak fixture
''';

void main() {
  setUpAll(() {
    final candidate = Platform.environment['CIRCUIT_SOAK_BROKER_PATH']?.trim();
    if (candidate == null || candidate.isEmpty) return;
    if (!Platform.isMacOS || !File(candidate).existsSync()) {
      throw StateError('soak_broker_missing');
    }
    _configuredBrokerPath = candidate;
    MacOsExecutionBoundary.debugBrokerExecutableOverride = candidate;
  });

  tearDownAll(() {
    _configuredBrokerPath = null;
    MacOsExecutionBoundary.debugBrokerExecutableOverride = null;
  });

  test('soak report fails an exceeded RSS-growth budget without user data', () {
    final report = _SoakReport(
      startedAt: DateTime.utc(2026),
      finishedAt: DateTime.utc(2026, 1, 1, 0, 1),
      requestedCycles: 3,
      requestedDuration: const Duration(minutes: 3),
      completedCycles: 3,
      startRssBytes: 100,
      maxRssBytes: 180,
      endRssBytes: 140,
      maxRssGrowthBytes: 64,
      rssSamplesBytes: const [120, 130, 140],
      warmupCycles: 2,
      maxPostWarmupRssGrowthBytes: 16,
      usesBundledBroker: false,
      failures: const [],
    );

    expect(report.peakRssGrowthBytes, 80);
    expect(report.endRssGrowthBytes, 40);
    expect(report.rssGrowthWithinBudget, isFalse);
    expect(report.postWarmupTrendEvaluated, isTrue);
    expect(report.postWarmupPeakRssGrowthBytes, 10);
    expect(report.postWarmupRssGrowthWithinBudget, isTrue);
    expect(report.rssStabilityWithinBudget, isFalse);
    expect(report.toJson(), containsPair('rssGrowthWithinBudget', isFalse));
    expect(report.toJson(), containsPair('rssStabilityWithinBudget', isFalse));
  });

  test('soak report fails sustained post-warmup RSS growth', () {
    final report = _SoakReport(
      startedAt: DateTime.utc(2026),
      finishedAt: DateTime.utc(2026, 1, 1, 0, 1),
      requestedCycles: 7,
      requestedDuration: const Duration(minutes: 3),
      completedCycles: 7,
      startRssBytes: 100,
      maxRssBytes: 170,
      endRssBytes: 170,
      maxRssGrowthBytes: 128,
      rssSamplesBytes: const [110, 120, 130, 145, 160, 170, 170],
      warmupCycles: 3,
      maxPostWarmupRssGrowthBytes: 32,
      usesBundledBroker: false,
      failures: const [],
    );

    expect(report.rssGrowthWithinBudget, isTrue);
    expect(report.postWarmupTrendEvaluated, isTrue);
    expect(report.postWarmupBaselineRssBytes, 130);
    expect(report.postWarmupPeakRssGrowthBytes, 40);
    expect(report.postWarmupEndRssGrowthBytes, 40);
    expect(report.postWarmupRssGrowthWithinBudget, isFalse);
    expect(report.rssStabilityWithinBudget, isFalse);
  });

  test(
    'Studio soak harness repeats durable lifecycle work and emits a redacted report',
    () async {
      final configuration = _SoakConfiguration.fromEnvironment();
      final startedAt = DateTime.now().toUtc();
      final startRss = ProcessInfo.currentRss;
      var maxRss = startRss;
      final rssSamples = <int>[];
      var completedCycles = 0;
      final failures = <String>[];

      while (configuration.shouldContinue(completedCycles, startedAt)) {
        try {
          await _runCycle(completedCycles);
          completedCycles += 1;
          final cycleRss = ProcessInfo.currentRss;
          rssSamples.add(cycleRss);
          maxRss = _max(maxRss, cycleRss);
        } catch (error) {
          // The cycle stages are fixed identifiers rather than prompts, paths,
          // command output, or artifact content. Retaining a StateError stage
          // makes a redacted broker failure actionable without broadening the
          // report's data surface.
          final failure = error is StateError
              ? error.message
              : error.runtimeType.toString();
          failures.add('cycle-${completedCycles + 1}:$failure');
          break;
        }
        if (configuration.pause > Duration.zero) {
          await Future<void>.delayed(configuration.pause);
        }
      }

      final report = _SoakReport(
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        requestedCycles: configuration.cycles,
        requestedDuration: configuration.duration,
        completedCycles: completedCycles,
        startRssBytes: startRss,
        maxRssBytes: maxRss,
        endRssBytes: ProcessInfo.currentRss,
        maxRssGrowthBytes: configuration.maxRssGrowthBytes,
        rssSamplesBytes: rssSamples,
        warmupCycles: configuration.warmupCycles,
        maxPostWarmupRssGrowthBytes: configuration.maxPostWarmupRssGrowthBytes,
        usesBundledBroker: _configuredBrokerPath != null,
        failures: failures,
      );
      await _writeReport(report);
      // The line is deliberately identifier/count/timing-only so a nightly
      // runner can retain the result without exposing prompts, paths, output,
      // or other user data in its logs.
      // ignore: avoid_print
      print('STUDIO_SOAK_REPORT=${jsonEncode(report.toJson())}');

      expect(failures, isEmpty, reason: jsonEncode(report.toJson()));
      expect(completedCycles, greaterThanOrEqualTo(configuration.cycles));
      expect(
        report.postWarmupTrendEvaluated,
        isTrue,
        reason:
            'A soak run must retain post-warmup samples before it can claim RSS stability: ${jsonEncode(report.toJson())}',
      );
      expect(
        report.rssStabilityWithinBudget,
        isTrue,
        reason: jsonEncode(report.toJson()),
      );
    },
    timeout: Timeout.none,
  );
}

Future<void> _runCycle(int index) async {
  final originalConfigDir = PlatformUtils.configDirOverride;
  final originalDebounce = StudioThreadController.debugPersistDebounceOverride;
  Directory? root;
  ProviderContainer? container;
  try {
    root = await Directory.systemTemp.createTemp('circuit-studio-soak-');
    final config = await Directory(p.join(root.path, 'config')).create();
    final projectA = await Directory(p.join(root.path, 'project-a')).create();
    final projectB = await Directory(p.join(root.path, 'project-b')).create();
    PlatformUtils.configDirOverride = config.path;
    StudioThreadController.debugPersistDebounceOverride = Duration.zero;
    final patchStore = PatchProposalStore(
      baseDir: p.join(root.path, 'patches'),
    );
    container = ProviderContainer(
      overrides: [patchProposalStoreProvider.overrideWithValue(patchStore)],
    );
    final fileTree = container.read(fileTreeProvider.notifier);
    final threads = container.read(studioThreadProvider.notifier);
    await fileTree.openDirectory(projectA.path);
    await threads.reload();
    // Exercise the project-bound persistence listeners before the normal
    // streaming/patch lifecycle returns to the original project.
    await fileTree.openDirectory(projectB.path);
    await threads.reload();
    await fileTree.openDirectory(projectA.path);
    await threads.reload();

    final thread = threads.createBlankThread(title: 'Soak cycle ${index + 1}');
    final requestId = 'soak-$index';
    final acceptedPlan = AcceptedPlanContext(
      patchSetId: 'soak-plan-$index',
      title: 'Soak lifecycle plan',
      summary: 'Create and verify one isolated marker.',
      markdown: '# Soak lifecycle plan\n\n- Create a marker\n- Verify it',
      plannedTargets: [
        PlannedFileTarget(
          path: 'lib/soak_$index.dart',
          intent: 'Create a deterministic soak marker',
          operation: ProposedFileEditType.create,
        ),
      ],
      verificationRequested: true,
    );
    container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: requestId,
          threadId: thread.id,
          taskId: null,
          userMessageId: 'soak-message-$index',
          prompt: 'Run durable Studio soak cycle ${index + 1}.',
          model: 'soak-fixture',
          intent: TurnIntent.code,
          acceptedPlanState: AcceptedPlanState.accepted,
          acceptedPlanContext: acceptedPlan,
          contextSummary: StudioContextSummary(
            rootPath: projectA.path,
            projectLabel: 'project-a',
            includedItemCount: 1,
            estimatedTokens: 64,
          ),
        );
    final turnController = container.read(studioTurnProvider.notifier);
    for (var chunk = 0; chunk < 24; chunk += 1) {
      turnController.appendAssistantDelta(requestId, 'stream-$chunk ');
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    final streamed = _turnFor(container, thread.id, requestId);
    _require(streamed.assistantDraft.contains('stream-23'), 'streaming');

    final patch = container
        .read(patchProposalProvider.notifier)
        .propose(
          title: 'Soak marker $index',
          runId: requestId,
          verificationRequested: true,
          edits: [
            ProposedFileEdit(
              path: 'lib/soak_$index.dart',
              type: ProposedFileEditType.create,
              after: 'const soakMarker$index = true;\n',
            ),
          ],
        );
    final apply = await container
        .read(patchProposalProvider.notifier)
        .apply(patch.id);
    _require(apply.applied, 'patch_apply');
    _require(
      await File(p.join(projectA.path, 'lib', 'soak_$index.dart')).exists(),
      'patch_file',
    );
    if (_configuredBrokerPath != null) {
      final launch = MacOsExecutionBoundary.forShellCommand(
        shell: PlatformUtils.shell,
        shellArgs: PlatformUtils.shellArgs,
        command: 'test -f lib/soak_$index.dart',
        workingDirectory: projectA.path,
        cpuLimitSeconds: 10,
        allowNetwork: false,
      );
      _require(launch.brokered, 'bundled_broker_selection');
    }
    // Run the real verification path rather than recording a fabricated
    // result. In test/CI this exercises the no-network macOS boundary; a
    // packaged app uses the bundled broker selected by that same boundary.
    final commandRun = await container
        .read(commandRunProvider.notifier)
        .runVerificationCommand(
          id: 'soak-command-$index',
          command: 'test -f lib/soak_$index.dart',
          workingDir: projectA.path,
          requestId: requestId,
          timeout: 10,
          userApproved: true,
        );
    final brokerEventSummary = [
      if (commandRun.processId != null) 'process',
      if (commandRun.events.any(
        (event) => event.type == CommandRunEventType.started,
      ))
        'started',
      if (commandRun.events.any(
        (event) => event.type == CommandRunEventType.exited,
      ))
        'exited',
      if (commandRun.exitCode != null) 'exit_${commandRun.exitCode}',
    ].join('_');
    _require(
      commandRun.status == CommandRunStatus.succeeded,
      'brokered_verification_status_${commandRun.status.name}_$brokerEventSummary',
    );
    _require(
      commandRun.exitCode == 0,
      'brokered_verification_exit_${commandRun.exitCode ?? 'missing'}',
    );
    _require(commandRun.processId != null, 'brokered_verification_process_id');
    _require(commandRun.endedAt != null, 'brokered_verification_ended_at');
    _require(
      commandRun.events.any(
        (event) => event.type == CommandRunEventType.started,
      ),
      'brokered_verification_started_event',
    );
    _require(
      commandRun.events.any(
        (event) => event.type == CommandRunEventType.exited,
      ),
      'brokered_verification_exited_event',
    );
    final targetArtifactKind =
        _soakArtifactKinds[index % _soakArtifactKinds.length];
    final generatedArtifact = await const GeneratedArtifactWriter()
        .writeStructuredArtifact(
          rootPath: projectA.path,
          prompt: _soakArtifactPrompt(targetArtifactKind),
          content: _soakArtifactContent,
          targetKind: targetArtifactKind,
          turnId: 'soak-artifact-$index',
          threadId: thread.id,
          requestId: requestId,
        );
    if (generatedArtifact == null) {
      throw StateError('artifact_generation');
    }
    _require(
      generatedArtifact.kind == targetArtifactKind &&
          generatedArtifact.status == GeneratedArtifactStatus.ready &&
          generatedArtifact.byteSize > 0 &&
          generatedArtifact.outputHash.length == 64 &&
          generatedArtifact.canRegenerate &&
          await File(generatedArtifact.filePath).exists(),
      'artifact_generation',
    );
    threads.upsertSourceArtifact(
      thread.id,
      generatedArtifact.toSourceArtifact(),
    );
    turnController.complete(
      requestId,
      content: 'Cycle completed.',
      summary: 'Applied, verified, and persisted the local marker.',
    );

    final failedThread = threads.createBlankThread(
      title: 'Soak failure ${index + 1}',
    );
    final failedRequestId = 'soak-failure-$index';
    turnController.registerTurn(
      requestId: failedRequestId,
      threadId: failedThread.id,
      taskId: null,
      userMessageId: 'soak-failure-message-$index',
      prompt: 'Exercise provider failure recovery.',
      model: 'soak-fixture',
      intent: TurnIntent.ask,
      contextSummary: StudioContextSummary(
        rootPath: projectA.path,
        projectLabel: 'project-a',
        includedItemCount: 0,
        estimatedTokens: 0,
      ),
    );
    turnController.appendAssistantDelta(failedRequestId, 'partial response');
    turnController.fail(failedRequestId, 'Synthetic provider failure.');
    _require(
      _turnFor(container, failedThread.id, failedRequestId).status ==
          StudioTurnStatus.failed,
      'provider_failure',
    );

    threads.archiveThread(thread.id);
    _require(
      container
          .read(studioThreadProvider)
          .threads
          .singleWhere((candidate) => candidate.id == thread.id)
          .archived,
      'archive',
    );
    _require(threads.restoreThread(thread.id), 'restore');
    // Assert restart recovery only after the production persistence boundary
    // has flushed; a timed delay makes this soak check scheduler-dependent.
    await threads.flushPendingPersistence();
    final store = StudioThreadStore(
      baseDir: p.join(config.path, 'studio_threads'),
    );
    final reloaded = await store.load(projectA.path);
    final restored = reloaded.singleWhere(
      (candidate) => candidate.id == thread.id,
    );
    _require(!restored.archived, 'restart_restore');
    final persistedArtifact = restored.sourceArtifacts.singleWhere(
      (artifact) => artifact.id == 'generated-soak-artifact-$index',
    );
    final reloadedArtifact = GeneratedArtifact.fromSourceArtifact(
      persistedArtifact,
    );
    _require(
      reloadedArtifact != null &&
          reloadedArtifact.kind == targetArtifactKind &&
          reloadedArtifact.status == GeneratedArtifactStatus.ready &&
          reloadedArtifact.filePath == generatedArtifact.filePath &&
          reloadedArtifact.outputHash == generatedArtifact.outputHash &&
          reloadedArtifact.canRegenerate &&
          await File(reloadedArtifact.filePath).exists(),
      'artifact_persistence',
    );
    _require(
      restored.turns
              .singleWhere((turn) => turn.requestId == requestId)
              .status ==
          StudioTurnStatus.completed,
      'restart_completed_turn',
    );
    _require(_eventIdsAreUnique(container), 'duplicate_events');
    _require(
      !container
          .read(studioThreadProvider)
          .threads
          .any((candidate) => candidate.isActive),
      'stale_working',
    );
  } finally {
    if (container != null) {
      await container
          .read(studioThreadProvider.notifier)
          .flushPendingPersistence();
      container.dispose();
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    PlatformUtils.configDirOverride = originalConfigDir;
    StudioThreadController.debugPersistDebounceOverride = originalDebounce;
    if (root != null && await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

StudioTurn _turnFor(
  ProviderContainer container,
  String threadId,
  String requestId,
) {
  return container
      .read(studioThreadProvider)
      .threads
      .singleWhere((thread) => thread.id == threadId)
      .turns
      .singleWhere((turn) => turn.requestId == requestId);
}

String _soakArtifactPrompt(GeneratedArtifactKind kind) {
  return switch (kind) {
    GeneratedArtifactKind.markdown => 'Create a Markdown delivery review',
    GeneratedArtifactKind.pdf => 'Create a PDF delivery review',
    GeneratedArtifactKind.docx => 'Create a DOCX delivery review',
    GeneratedArtifactKind.excel => 'Create an Excel delivery workbook',
    GeneratedArtifactKind.powerPoint => 'Create a PowerPoint delivery review',
    _ => 'Create a delivery review',
  };
}

bool _eventIdsAreUnique(ProviderContainer container) {
  final ids = <String>{};
  for (final event
      in container
          .read(studioThreadProvider)
          .threads
          .expand((thread) => thread.turns)
          .expand((turn) => turn.events)) {
    if (!ids.add(event.id)) return false;
  }
  return true;
}

int _max(int left, int right) => left > right ? left : right;

void _require(bool condition, String stage) {
  if (!condition) throw StateError(stage);
}

Future<void> _writeReport(_SoakReport report) async {
  final path = Platform.environment['STUDIO_SOAK_REPORT_PATH']?.trim();
  if (path == null || path.isEmpty) return;
  final target = File(path);
  await target.parent.create(recursive: true);
  final temporary = File('${target.path}.tmp');
  await temporary.writeAsString(
    '${jsonEncode(report.toJson())}\n',
    flush: true,
  );
  await temporary.rename(target.path);
}

class _SoakConfiguration {
  final int cycles;
  final Duration? duration;
  final Duration pause;
  final int maxRssGrowthBytes;
  final int warmupCycles;
  final int maxPostWarmupRssGrowthBytes;

  const _SoakConfiguration({
    required this.cycles,
    required this.duration,
    required this.pause,
    required this.maxRssGrowthBytes,
    required this.warmupCycles,
    required this.maxPostWarmupRssGrowthBytes,
  });

  factory _SoakConfiguration.fromEnvironment() {
    // Keep three full samples after the default three-cycle warmup. A bounded
    // local run that ends at warmup cannot establish a sustained-memory trend.
    final cycles = _boundedInt('CIRCUIT_SOAK_CYCLES', fallback: 6, max: 1000);
    final durationMinutes = _boundedInt(
      'CIRCUIT_SOAK_DURATION_MINUTES',
      fallback: 0,
      max: 480,
    );
    return _SoakConfiguration(
      cycles: cycles,
      duration: durationMinutes == 0
          ? null
          : Duration(minutes: durationMinutes),
      pause: Duration(
        milliseconds: _boundedInt(
          'CIRCUIT_SOAK_PAUSE_MS',
          fallback: 0,
          max: 60000,
        ),
      ),
      // The bounded local run typically observes one-time Dart/Flutter cache
      // allocation before settling. This deliberately generous peak limit
      // catches sustained or runaway growth without treating warmup as a leak.
      maxRssGrowthBytes:
          _boundedInt(
            'CIRCUIT_SOAK_MAX_RSS_GROWTH_MB',
            fallback: 256,
            max: 2048,
          ) *
          1024 *
          1024,
      // Whole-run growth permits expected Flutter/Dart cache warmup. Once that
      // warmup is complete, require later cycles to remain within their own
      // stricter ceiling so a slow leak cannot hide under the broad peak cap.
      warmupCycles: _boundedInt(
        'CIRCUIT_SOAK_WARMUP_CYCLES',
        fallback: 3,
        max: 100,
      ),
      maxPostWarmupRssGrowthBytes:
          _boundedInt(
            'CIRCUIT_SOAK_MAX_POST_WARMUP_RSS_GROWTH_MB',
            fallback: 64,
            max: 2048,
          ) *
          1024 *
          1024,
    );
  }

  bool shouldContinue(int completedCycles, DateTime startedAt) {
    final deadline = duration == null ? null : startedAt.add(duration!);
    return completedCycles < cycles ||
        (deadline != null && DateTime.now().toUtc().isBefore(deadline));
  }

  static int _boundedInt(
    String key, {
    required int fallback,
    required int max,
  }) {
    final value = int.tryParse(Platform.environment[key] ?? '');
    if (value == null) return fallback;
    return value.clamp(1, max);
  }
}

class _SoakReport {
  final DateTime startedAt;
  final DateTime finishedAt;
  final int requestedCycles;
  final Duration? requestedDuration;
  final int completedCycles;
  final int startRssBytes;
  final int maxRssBytes;
  final int endRssBytes;
  final int maxRssGrowthBytes;
  final List<int> rssSamplesBytes;
  final int warmupCycles;
  final int maxPostWarmupRssGrowthBytes;
  final bool usesBundledBroker;
  final List<String> failures;

  const _SoakReport({
    required this.startedAt,
    required this.finishedAt,
    required this.requestedCycles,
    required this.requestedDuration,
    required this.completedCycles,
    required this.startRssBytes,
    required this.maxRssBytes,
    required this.endRssBytes,
    required this.maxRssGrowthBytes,
    required this.rssSamplesBytes,
    required this.warmupCycles,
    required this.maxPostWarmupRssGrowthBytes,
    required this.usesBundledBroker,
    required this.failures,
  });

  int get peakRssGrowthBytes => maxRssBytes - startRssBytes;
  int get endRssGrowthBytes => endRssBytes - startRssBytes;
  bool get rssGrowthWithinBudget => peakRssGrowthBytes <= maxRssGrowthBytes;
  bool get postWarmupTrendEvaluated => rssSamplesBytes.length > warmupCycles;
  int get postWarmupBaselineRssBytes => postWarmupTrendEvaluated
      ? rssSamplesBytes[warmupCycles - 1]
      : endRssBytes;
  int get postWarmupPeakRssGrowthBytes {
    if (!postWarmupTrendEvaluated) return 0;
    final peak = rssSamplesBytes
        .skip(warmupCycles)
        .fold(postWarmupBaselineRssBytes, _max);
    return _max(0, peak - postWarmupBaselineRssBytes);
  }

  int get postWarmupEndRssGrowthBytes => postWarmupTrendEvaluated
      ? _max(0, endRssBytes - postWarmupBaselineRssBytes)
      : 0;
  bool get postWarmupRssGrowthWithinBudget =>
      !postWarmupTrendEvaluated ||
      postWarmupPeakRssGrowthBytes <= maxPostWarmupRssGrowthBytes;
  bool get rssStabilityWithinBudget =>
      rssGrowthWithinBudget && postWarmupRssGrowthWithinBudget;

  Map<String, Object> toJson() => {
    'schemaVersion': 2,
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt.toIso8601String(),
    'requestedCycles': requestedCycles,
    'requestedDurationSeconds': requestedDuration?.inSeconds ?? 0,
    'completedCycles': completedCycles,
    'startRssBytes': startRssBytes,
    'maxRssBytes': maxRssBytes,
    'endRssBytes': endRssBytes,
    'maxRssGrowthBytes': maxRssGrowthBytes,
    'peakRssGrowthBytes': peakRssGrowthBytes,
    'endRssGrowthBytes': endRssGrowthBytes,
    'rssGrowthWithinBudget': rssGrowthWithinBudget,
    'rssSampleCount': rssSamplesBytes.length,
    'warmupCycles': warmupCycles,
    'postWarmupTrendEvaluated': postWarmupTrendEvaluated,
    'postWarmupBaselineRssBytes': postWarmupBaselineRssBytes,
    'maxPostWarmupRssGrowthBytes': maxPostWarmupRssGrowthBytes,
    'postWarmupPeakRssGrowthBytes': postWarmupPeakRssGrowthBytes,
    'postWarmupEndRssGrowthBytes': postWarmupEndRssGrowthBytes,
    'postWarmupRssGrowthWithinBudget': postWarmupRssGrowthWithinBudget,
    'rssStabilityWithinBudget': rssStabilityWithinBudget,
    'usesBundledBroker': usesBundledBroker,
    'failures': failures,
  };
}
