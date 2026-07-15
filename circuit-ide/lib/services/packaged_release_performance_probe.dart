import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/utils/platform_utils.dart';
import '../models/agent_workspace.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import '../models/turn_intent.dart';
import '../state/agent_workspace_provider.dart';
import '../state/file_tree_provider.dart';
import '../state/studio_shell_provider.dart';
import '../state/studio_thread_provider.dart';
import '../state/studio_turn_provider.dart';
import 'project_history_path_scanner.dart';
import 'semantic_index.dart';
import 'studio_transcript_scroll_probe.dart';

/// Mounts the production shell before the probe manipulates its real state.
typedef PackagedReleasePerformanceProbeShellMount =
    FutureOr<void> Function(ProviderContainer container);

typedef PackagedReleasePerformanceProbeFrameWait = Future<void> Function();

/// One measured Flutter frame from the private packaged performance probe.
///
/// The probe retains only timing values. It never records widget contents,
/// project paths, prompts, or rendered pixels.
@immutable
class PackagedReleaseFrameTimingSample {
  final Duration build;
  final Duration raster;
  final Duration total;

  const PackagedReleaseFrameTimingSample({
    required this.build,
    required this.raster,
    required this.total,
  });

  factory PackagedReleaseFrameTimingSample.fromFrameTiming(
    FrameTiming timing,
  ) => PackagedReleaseFrameTimingSample(
    build: timing.buildDuration,
    raster: timing.rasterDuration,
    total: timing.totalSpan,
  );
}

/// Redacted frame-timeline summary retained by the packaged evidence route.
///
/// Values use nearest-rank p95, matching the release-series aggregation. The
/// timeline is a measurement, not a hardware-independent release verdict.
@immutable
class PackagedReleaseFrameTimingSummary {
  final int sampleCount;
  final Duration buildP95;
  final Duration rasterP95;
  final Duration totalP95;

  const PackagedReleaseFrameTimingSummary._({
    required this.sampleCount,
    required this.buildP95,
    required this.rasterP95,
    required this.totalP95,
  });

  factory PackagedReleaseFrameTimingSummary.fromSamples(
    Iterable<PackagedReleaseFrameTimingSample> samples,
  ) {
    final collected = samples.toList(growable: false);
    if (collected.isEmpty) {
      throw const FormatException(
        'A frame timing summary requires at least one rendered frame.',
      );
    }
    Duration p95(Iterable<Duration> values) {
      final sorted = values.toList()..sort();
      final nearestRank = (sorted.length * 0.95).ceil();
      return sorted[nearestRank - 1];
    }

    return PackagedReleaseFrameTimingSummary._(
      sampleCount: collected.length,
      buildP95: p95([for (final sample in collected) sample.build]),
      rasterP95: p95([for (final sample in collected) sample.raster]),
      totalP95: p95([for (final sample in collected) sample.total]),
    );
  }
}

class _PackagedReleaseFrameTimeline {
  final List<PackagedReleaseFrameTimingSample> _samples = [];
  int? _minimumBuildStartMicroseconds;

  int get sampleCount => _samples.length;

  void add(Iterable<FrameTiming> timings) {
    final minimumBuildStartMicroseconds = _minimumBuildStartMicroseconds;
    for (final timing in timings) {
      // Release callbacks can arrive in a delayed batch. Compare the raw
      // engine build timestamp rather than callback arrival time so setup
      // frames cannot leak into a later measurement window.
      if (minimumBuildStartMicroseconds != null &&
          timing.timestampInMicroseconds(FramePhase.buildStart) <=
              minimumBuildStartMicroseconds) {
        continue;
      }
      _samples.add(PackagedReleaseFrameTimingSample.fromFrameTiming(timing));
    }
  }

  void clear() {
    _samples.clear();
    _minimumBuildStartMicroseconds = null;
  }

  void startAfter(Duration frameTimeStamp) {
    _samples.clear();
    _minimumBuildStartMicroseconds = frameTimeStamp.inMicroseconds;
  }

  PackagedReleaseFrameTimingSummary? summaryOrNull() => _samples.isEmpty
      ? null
      : PackagedReleaseFrameTimingSummary.fromSamples(_samples);
}

/// A small, private release-bundle measurement scenario.
///
/// This is deliberately an evidence collector, not a benchmark verdict. It
/// runs only through the package harness, never through product UI, a model,
/// or a tool. The emitted JSON contains durations, counts, and RSS only; it
/// contains no project paths, prompts, task titles, provider data, or source
/// contents. The retained report is useful when taking the repeated
/// reference-hardware traces required by `PERFORMANCE_BUDGETS.md`.
class PackagedReleasePerformanceProbe {
  static const readyMarker = 'PACKAGED_RELEASE_PERFORMANCE=';

  static Future<PackagedReleasePerformanceProbeResult> run({
    required Duration dartMainElapsed,
    PackagedReleasePerformanceProbeShellMount? onContainerReady,
    PackagedReleasePerformanceProbeFrameWait? waitForFrame,
  }) async {
    final originalConfigDir = PlatformUtils.configDirOverride;
    final originalDebounce =
        StudioThreadController.debugPersistDebounceOverride;
    final frameWait = waitForFrame ?? _waitForFrame;
    final frameTimeline = _PackagedReleaseFrameTimeline();
    final needsRenderedFrameEvidence = onContainerReady != null;
    if (needsRenderedFrameEvidence) {
      StudioTranscriptScrollProbe.beginPackagedProbe();
    }
    void receiveFrameTimings(List<FrameTiming> timings) {
      frameTimeline.add(timings);
    }

    Directory? root;
    ProviderContainer? container;
    // Failure output is retained in CI/release evidence, so it may name only
    // this fixed lifecycle phase. Never expose the exception or its message:
    // those can contain filesystem, provider, or customer-derived details.
    var activePhase = 'prepare_workspace';
    WidgetsBinding.instance.addTimingsCallback(receiveFrameTimings);
    try {
      root = await Directory.systemTemp.createTemp(
        'circuit-release-performance-',
      );
      activePhase = 'prepare_config';
      final config = await Directory(p.join(root.path, 'config')).create();
      final project = await Directory(p.join(root.path, 'project')).create();
      PlatformUtils.configDirOverride = config.path;
      StudioThreadController.debugPersistDebounceOverride = Duration.zero;
      container = ProviderContainer();
      activePhase = 'mount_shell';
      await onContainerReady?.call(container);

      activePhase = 'project_bind';
      final projectBind = Stopwatch()..start();
      await container
          .read(fileTreeProvider.notifier)
          .openDirectory(project.path);
      await container.read(studioThreadProvider.notifier).reload();
      projectBind.stop();

      activePhase = 'history_fixture';
      final historyFixture = await _measureHistoryFixture(
        configDirectory: config,
        project: project,
      );
      activePhase = 'project_history_recovery';
      final projectRecoveryAndMetadata500 =
          await _measureProjectRecoveryAndMetadataFixture(
            configDirectory: config,
            workspaceRoot: root,
          );
      activePhase = 'semantic_index';
      final semanticIndexRebuild1200 = await _measureSemanticIndexFixture(
        project: project,
      );

      activePhase = 'primary_stream';
      final threads = container.read(studioThreadProvider.notifier);
      final turns = container.read(studioTurnProvider.notifier);
      final firstThread = threads.createBlankThread(
        title: 'Release performance probe primary task',
      );
      container.read(studioShellProvider.notifier).openThread(firstThread.id);
      turns.registerTurn(
        requestId: 'release-performance-primary',
        threadId: firstThread.id,
        taskId: null,
        userMessageId: 'release-performance-message',
        prompt: 'Measure the local release frame path.',
        model: 'release-performance-fixture',
        intent: TurnIntent.ask,
        contextSummary: StudioContextSummary(
          rootPath: project.path,
          projectLabel: 'Release performance fixture',
          includedItemCount: 0,
          estimatedTokens: 0,
        ),
      );
      await frameWait();

      const firstDelta = 'First streamed release-performance fixture delta.';
      frameTimeline.clear();
      activePhase = 'first_stream_frame';
      final firstStreamFrame = Stopwatch()..start();
      turns.appendAssistantDelta('release-performance-primary', firstDelta);
      await frameWait();
      firstStreamFrame.stop();
      await _waitForFrameTimeline(
        frameTimeline,
        minimumSampleCount: needsRenderedFrameEvidence ? 1 : 0,
      );

      var tenThousandDeltaStateUpdates = 0;
      activePhase = 'stream_burst';
      final tenThousandDeltaSubscription = container.listen<StudioThreadState>(
        studioThreadProvider,
        (_, _) => tenThousandDeltaStateUpdates++,
      );
      final tenThousandDeltaBurst = Stopwatch()..start();
      for (var index = 0; index < 10000; index++) {
        turns.appendAssistantDelta('release-performance-primary', 'x');
      }
      await Future<void>.delayed(const Duration(milliseconds: 160));
      tenThousandDeltaBurst.stop();
      tenThousandDeltaSubscription.close();
      final streamedThread = container
          .read(studioThreadProvider)
          .threads
          .where((thread) => thread.id == firstThread.id)
          .firstOrNull;
      final streamedTurn = streamedThread?.turns
          .where((turn) => turn.requestId == 'release-performance-primary')
          .firstOrNull;
      _require(
        streamedTurn?.assistantDraft.length == firstDelta.length + 10000 &&
            tenThousandDeltaStateUpdates <= 4,
        'stream_burst',
      );

      // The burst above verifies coalescing. This second trace deliberately
      // lets the normal throttled draft updates render, giving the packaged
      // Release process a real build/raster timeline rather than only elapsed
      // wall-clock work. It contains no model or workspace content.
      const pacedRequestId = 'release-performance-paced-stream';
      activePhase = 'paced_stream';
      final pacedThread = threads.createBlankThread(
        title: 'Release performance paced stream',
      );
      container.read(studioShellProvider.notifier).openThread(pacedThread.id);
      turns.registerTurn(
        requestId: pacedRequestId,
        threadId: pacedThread.id,
        taskId: null,
        userMessageId: 'release-performance-paced-message',
        prompt: 'Measure paced release frame timings.',
        model: 'release-performance-fixture',
        intent: TurnIntent.ask,
        contextSummary: StudioContextSummary(
          rootPath: project.path,
          projectLabel: 'Release performance fixture',
          includedItemCount: 0,
          estimatedTokens: 0,
        ),
      );
      await frameWait();
      frameTimeline.clear();
      const pacedPackets = 8;
      const deltasPerPacket = 768;
      for (var packet = 0; packet < pacedPackets; packet++) {
        for (var delta = 0; delta < deltasPerPacket; delta++) {
          turns.appendAssistantDelta(pacedRequestId, 'x');
        }
        await Future<void>.delayed(const Duration(milliseconds: 140));
        await frameWait();
      }
      await _waitForFrameTimeline(
        frameTimeline,
        minimumSampleCount: needsRenderedFrameEvidence ? 5 : 0,
      );
      final streamFrameTimeline = frameTimeline.summaryOrNull();
      final pacedTurn = container
          .read(studioThreadProvider)
          .threads
          .where((thread) => thread.id == pacedThread.id)
          .firstOrNull
          ?.turns
          .where((turn) => turn.requestId == pacedRequestId)
          .firstOrNull;
      _require(
        pacedTurn?.assistantDraft.length == pacedPackets * deltasPerPacket,
        'paced_stream',
      );
      if (needsRenderedFrameEvidence) {
        _require(
          streamFrameTimeline != null && streamFrameTimeline.sampleCount >= 5,
          'stream_frame_timeline',
        );
      }

      final secondThread = threads.createBlankThread(
        title: 'Release performance probe secondary task',
      );
      activePhase = 'task_switch';
      final taskSwitch = Stopwatch()..start();
      threads.selectThread(secondThread.id);
      container.read(studioShellProvider.notifier).openThread(secondThread.id);
      await frameWait();
      taskSwitch.stop();

      activePhase = 'durable_reload';
      final persistence = Stopwatch()..start();
      turns.complete(
        'release-performance-primary',
        content: 'Release probe complete.',
        summary: 'Captured bounded local release metrics.',
      );
      await _settlePersistence();
      final store = StudioThreadStore(
        baseDir: p.join(config.path, 'studio_threads'),
      );
      final reloaded = await store.load(project.path);
      persistence.stop();
      _require(
        reloaded.any((thread) => thread.id == firstThread.id),
        'durable_reload',
      );
      activePhase = 'checkpoint_persistence';
      final durableCheckpointPersistence =
          await _measureCheckpointPersistenceFixture(
            configDirectory: config,
            project: project,
          );
      activePhase = 'transcript_scroll';
      final transcriptScrollFrameTimeline = needsRenderedFrameEvidence
          ? await _measureTranscriptScrollFrameTimeline(
              frameTimeline: frameTimeline,
              threads: threads,
              container: container,
              configDirectory: config,
              project: project,
              waitForFrame: frameWait,
            )
          : null;

      return PackagedReleasePerformanceProbeResult.passed(
        dartMainToFirstFrame: dartMainElapsed,
        projectBind: projectBind.elapsed,
        firstStreamFrame: firstStreamFrame.elapsed,
        tenThousandDeltaBurst: tenThousandDeltaBurst.elapsed,
        tenThousandDeltaStateUpdates: tenThousandDeltaStateUpdates,
        taskSwitch: taskSwitch.elapsed,
        durableReload: persistence.elapsed,
        taskSummaryPage5000: historyFixture.taskSummaryPage5000,
        threadSummaryPage1000: historyFixture.threadSummaryPage1000,
        threadHydration1000: historyFixture.threadHydration1000,
        projectRecoveryAndMetadata500: projectRecoveryAndMetadata500,
        semanticIndexRebuild1200: semanticIndexRebuild1200,
        durableCheckpointPersistence: durableCheckpointPersistence,
        residentSetBytes: ProcessInfo.currentRss,
        streamFrameTimeline: streamFrameTimeline,
        transcriptScrollFrameTimeline: transcriptScrollFrameTimeline,
      );
    } on _PackagedReleasePerformanceProbeFailure catch (error) {
      return PackagedReleasePerformanceProbeResult.failed(error.stage);
    } catch (_) {
      return PackagedReleasePerformanceProbeResult.failed(
        'unexpected_$activePhase',
      );
    } finally {
      WidgetsBinding.instance.removeTimingsCallback(receiveFrameTimings);
      StudioTranscriptScrollProbe.endPackagedProbe();
      container?.dispose();
      await _settlePersistence();
      PlatformUtils.configDirOverride = originalConfigDir;
      StudioThreadController.debugPersistDebounceOverride = originalDebounce;
      if (root != null && await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  }

  static Future<void> _waitForFrame() =>
      WidgetsBinding.instance.endOfFrame.timeout(const Duration(seconds: 5));

  static Future<void> _settlePersistence() =>
      Future<void>.delayed(const Duration(milliseconds: 160));

  static Future<void> _waitForFrameTimeline(
    _PackagedReleaseFrameTimeline timeline, {
    required int minimumSampleCount,
  }) async {
    if (minimumSampleCount <= 0) return;
    const retryDelay = Duration(milliseconds: 100);
    const retries = 15;
    for (var retry = 0; retry < retries; retry++) {
      if (timeline.sampleCount >= minimumSampleCount) return;
      await Future<void>.delayed(retryDelay);
    }
  }

  /// Generates no product-facing content and measures the same durable-history
  /// shapes used by the CI fixture from a packaged Release process. The values
  /// are evidence only: no pass/fail budget is inferred from one run.
  static Future<_HistoryFixtureMetrics> _measureHistoryFixture({
    required Directory configDirectory,
    required Directory project,
  }) async {
    final taskStore = AgentWorkspaceStore(
      baseDir: p.join(configDirectory.path, 'agent_workspace'),
    );
    final threadStore = StudioThreadStore(
      baseDir: p.join(configDirectory.path, 'studio_threads'),
    );
    final timestamp = DateTime.utc(2026, 7, 13);
    final tasks = List<AgentTask>.generate(
      5000,
      (index) => AgentTask(
        id: 'release-history-task-$index',
        mascotAlias: 'Circuit',
        profile: AgentTaskProfile.investigate,
        goal: 'Release history task $index',
        createdAt: timestamp.add(Duration(seconds: index)),
      ),
      growable: false,
    );
    await taskStore.save(project.path, tasks);

    final hydratedThread = StudioThread(
      id: 'release-history-hydrated-thread',
      title: 'Release history fixture',
      createdAt: timestamp,
      updatedAt: timestamp.add(const Duration(seconds: 999)),
      turns: List<StudioTurn>.generate(
        1000,
        (index) => StudioTurn(
          id: 'release-history-turn-$index',
          threadId: 'release-history-hydrated-thread',
          requestId: 'release-history-request-$index',
          userMessageId: 'release-history-message-$index',
          prompt: 'Release history fixture turn $index',
          model: 'release-history-fixture',
          contextSummary: const StudioContextSummary(
            projectLabel: 'Release history fixture',
          ),
          status: StudioTurnStatus.completed,
          createdAt: timestamp.add(Duration(seconds: index)),
          updatedAt: timestamp.add(Duration(seconds: index)),
          completedAt: timestamp.add(Duration(seconds: index)),
        ),
        growable: false,
      ),
    );
    await threadStore.save(project.path, [hydratedThread]);
    final summaryIndex = File(threadStore.summaryIndexPath(project.path));
    await summaryIndex.writeAsString(
      [
        jsonEncode({
          'kind': 'circuit.studio-thread-summary-index',
          'version': 1,
          'totalCount': 1000,
        }),
        for (var index = 0; index < 1000; index++)
          jsonEncode(
            StudioThread(
              id: 'release-history-summary-$index',
              title: 'Release history summary $index',
              createdAt: timestamp.add(Duration(seconds: index)),
              updatedAt: timestamp.add(Duration(seconds: index)),
            ).toJson(),
          ),
      ].join('\n'),
    );

    final taskPageWatch = Stopwatch()..start();
    final taskPage = await taskStore.loadSummaryPage(project.path, limit: 24);
    taskPageWatch.stop();
    _require(
      taskPage.totalCount == 5000 && taskPage.tasks.length == 24,
      'history_task_page',
    );

    final threadPageWatch = Stopwatch()..start();
    final threadPage = await threadStore.loadSummaryPage(
      project.path,
      limit: 24,
    );
    threadPageWatch.stop();
    _require(
      threadPage.totalCount == 1000 && threadPage.threads.length == 24,
      'history_thread_page',
    );

    final hydrationWatch = Stopwatch()..start();
    final loadedThread = await threadStore.loadThread(
      project.path,
      hydratedThread.id,
    );
    hydrationWatch.stop();
    _require(loadedThread?.turns.length == 1000, 'history_hydration');

    return _HistoryFixtureMetrics(
      taskSummaryPage5000: taskPageWatch.elapsed,
      threadSummaryPage1000: threadPageWatch.elapsed,
      threadHydration1000: hydrationWatch.elapsed,
    );
  }

  /// Measures the project-rail recovery path with 500 durable projects.
  ///
  /// Fixture creation is outside the stopwatch. The timed path is identical
  /// to [StudioProjectHistoryController]'s recovery: discover durable project
  /// paths in the worker, then page the first task and thread metadata rows
  /// without opening full histories. The redacted result retains only elapsed
  /// milliseconds, never recovered paths or history contents.
  static Future<Duration> _measureProjectRecoveryAndMetadataFixture({
    required Directory configDirectory,
    required Directory workspaceRoot,
  }) async {
    const projectCount = 500;
    const entriesPerProject = 10;
    const pageSize = 2;
    final taskStore = AgentWorkspaceStore(
      baseDir: p.join(configDirectory.path, 'project_history_fixture_tasks'),
    );
    final threadStore = StudioThreadStore(
      baseDir: p.join(configDirectory.path, 'project_history_fixture_threads'),
    );
    final projectsRoot = await Directory(
      p.join(workspaceRoot.path, 'release_project_history_fixture'),
    ).create();
    final timestamp = DateTime.utc(2026, 7, 13);
    for (var projectIndex = 0; projectIndex < projectCount; projectIndex++) {
      final project = await Directory(
        p.join(projectsRoot.path, 'project-$projectIndex'),
      ).create();
      await taskStore.save(project.path, [
        for (var entryIndex = 0; entryIndex < entriesPerProject; entryIndex++)
          AgentTask(
            id: 'release-project-$projectIndex-task-$entryIndex',
            mascotAlias: 'Circuit',
            profile: AgentTaskProfile.investigate,
            goal: 'Release project $projectIndex task $entryIndex',
            createdAt: timestamp.add(Duration(seconds: entryIndex)),
          ),
      ]);
      await threadStore.save(project.path, [
        for (var entryIndex = 0; entryIndex < entriesPerProject; entryIndex++)
          StudioThread(
            id: 'release-project-$projectIndex-thread-$entryIndex',
            title: 'Release project $projectIndex conversation $entryIndex',
            createdAt: timestamp.add(Duration(seconds: entryIndex)),
            updatedAt: timestamp.add(Duration(seconds: entryIndex)),
          ),
      ]);
    }

    final recovery = Stopwatch()..start();
    final recovered = await const ProjectHistoryPathScanner().recover(
      storageDirectories: [taskStore.baseDir, threadStore.baseDir],
    );
    _require(
      recovered.length == projectCount &&
          recovered.toSet().length == projectCount,
      'project_history_recovery',
    );
    var taskRowCount = 0;
    var threadRowCount = 0;
    for (final projectPath in recovered) {
      final taskPage = await taskStore.loadSummaryPage(
        projectPath,
        limit: pageSize,
      );
      final threadPage = await threadStore.loadSummaryPage(
        projectPath,
        limit: pageSize,
      );
      _require(
        taskPage.totalCount == entriesPerProject &&
            threadPage.totalCount == entriesPerProject,
        'project_history_metadata',
      );
      taskRowCount += taskPage.tasks.length;
      threadRowCount += threadPage.threads.length;
    }
    recovery.stop();
    _require(
      taskRowCount == projectCount * pageSize &&
          threadRowCount == projectCount * pageSize,
      'project_history_metadata',
    );
    return recovery.elapsed;
  }

  /// Measures the production semantic-index worker over the release target's
  /// 1,200 bounded source-file shape. Fixture creation happens before the
  /// stopwatch, and only the elapsed rebuild duration leaves the probe.
  static Future<Duration> _measureSemanticIndexFixture({
    required Directory project,
  }) async {
    const fileCount = 1200;
    const filesPerDirectory = 100;
    final sourceRoot = await Directory(
      p.join(project.path, 'release_index_fixture'),
    ).create();
    for (var index = 0; index < fileCount; index++) {
      final bucket = index ~/ filesPerDirectory;
      final directory = Directory(p.join(sourceRoot.path, 'lib_$bucket'));
      if (!await directory.exists()) await directory.create();
      await File(p.join(directory.path, 'fixture_$index.dart')).writeAsString(
        'class ReleaseIndexFixture$index {\n'
        '  const ReleaseIndexFixture$index();\n'
        '  int get value => $index;\n'
        '}\n',
      );
    }

    final index = SemanticIndex();
    final rebuild = Stopwatch()..start();
    await index.buildIndex(project.path);
    rebuild.stop();
    _require(index.chunkCount >= fileCount, 'semantic_index_rebuild');
    return rebuild.elapsed;
  }

  /// Measures a direct atomic persistence checkpoint containing task metadata
  /// and the selected thread. The subsequent reload check is intentionally
  /// outside the stopwatch; durable reload has its own probe metric.
  static Future<Duration> _measureCheckpointPersistenceFixture({
    required Directory configDirectory,
    required Directory project,
  }) async {
    final checkpointProject = await Directory(
      p.join(project.path, 'release_checkpoint_fixture'),
    ).create();
    final taskStore = AgentWorkspaceStore(
      baseDir: p.join(configDirectory.path, 'agent_workspace'),
    );
    final threadStore = StudioThreadStore(
      baseDir: p.join(configDirectory.path, 'studio_threads'),
    );
    final timestamp = DateTime.utc(2026, 7, 13, 18);
    final task = AgentTask(
      id: 'release-checkpoint-task',
      mascotAlias: 'Circuit',
      profile: AgentTaskProfile.investigate,
      goal: 'Persist the release checkpoint fixture.',
      createdAt: timestamp,
    );
    final thread = StudioThread(
      id: 'release-checkpoint-thread',
      title: 'Release checkpoint fixture',
      createdAt: timestamp,
      updatedAt: timestamp,
      turns: [
        StudioTurn(
          id: 'release-checkpoint-turn',
          threadId: 'release-checkpoint-thread',
          requestId: 'release-checkpoint-request',
          userMessageId: 'release-checkpoint-message',
          prompt: 'Persist the release checkpoint fixture.',
          model: 'release-performance-fixture',
          contextSummary: const StudioContextSummary(
            projectLabel: 'Release checkpoint fixture',
          ),
          status: StudioTurnStatus.completed,
          createdAt: timestamp,
          updatedAt: timestamp,
          completedAt: timestamp,
        ),
      ],
    );
    final persistence = Stopwatch()..start();
    await taskStore.save(checkpointProject.path, [task]);
    await threadStore.save(checkpointProject.path, [thread]);
    persistence.stop();

    final storedTasks = await taskStore.load(checkpointProject.path);
    final storedThread = await threadStore.loadThread(
      checkpointProject.path,
      thread.id,
    );
    _require(
      storedTasks.length == 1 &&
          storedTasks.single.id == task.id &&
          storedThread?.turns.length == 1 &&
          storedThread?.turns.single.id == 'release-checkpoint-turn',
      'durable_checkpoint_persistence',
    );
    return persistence.elapsed;
  }

  /// Mounts a 1,000-turn transcript in the production shell and measures the
  /// actual virtualized ListView while it scrolls from its tail into history.
  /// The fixture remains private to the temporary probe workspace; the frame
  /// summary keeps only counts and timing durations.
  static Future<PackagedReleaseFrameTimingSummary>
  _measureTranscriptScrollFrameTimeline({
    required _PackagedReleaseFrameTimeline frameTimeline,
    required StudioThreadController threads,
    required ProviderContainer container,
    required Directory configDirectory,
    required Directory project,
    required PackagedReleasePerformanceProbeFrameWait waitForFrame,
  }) async {
    const turnCount = 1000;
    final timestamp = DateTime.utc(2026, 7, 13, 19);
    final thread = StudioThread(
      id: 'release-scroll-thread',
      title: 'Release transcript scroll fixture',
      createdAt: timestamp,
      updatedAt: timestamp.add(const Duration(seconds: turnCount)),
      turns: List<StudioTurn>.generate(
        turnCount,
        (index) => StudioTurn(
          id: 'release-scroll-turn-$index',
          threadId: 'release-scroll-thread',
          requestId: 'release-scroll-request-$index',
          userMessageId: 'release-scroll-message-$index',
          prompt: 'Release transcript scroll fixture turn $index.',
          model: 'release-performance-fixture',
          contextSummary: const StudioContextSummary(
            projectLabel: 'Release transcript scroll fixture',
          ),
          status: StudioTurnStatus.completed,
          createdAt: timestamp.add(Duration(seconds: index)),
          updatedAt: timestamp.add(Duration(seconds: index)),
          completedAt: timestamp.add(Duration(seconds: index)),
        ),
        growable: false,
      ),
    );

    // Allow the controller's preceding real lifecycle writes to settle before
    // replacing the private fixture store, so a delayed persistence callback
    // cannot race the scroll scenario.
    await _settlePersistence();
    final store = StudioThreadStore(
      baseDir: p.join(configDirectory.path, 'studio_threads'),
    );
    await store.save(project.path, [thread]);
    await threads.reload();
    threads.selectThread(thread.id);
    container.read(studioShellProvider.notifier).openThread(thread.id);
    await waitForFrame();
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await waitForFrame();
    _require(StudioTranscriptScrollProbe.isReady, 'transcript_scroll_probe');

    // Reset to the tail before starting collection, then allow that setup
    // frame to settle. The measured window below contains only the real
    // animated history scroll, not a navigation or reset frame.
    _require(
      await StudioTranscriptScrollProbe.prepare(),
      'transcript_scroll_prepare',
    );
    await waitForFrame();
    await Future<void>.delayed(const Duration(milliseconds: 34));
    await waitForFrame();
    frameTimeline.startAfter(
      WidgetsBinding.instance.currentSystemFrameTimeStamp,
    );
    final scrolled = await StudioTranscriptScrollProbe.drive(stepCount: 8);
    await _waitForFrameTimeline(frameTimeline, minimumSampleCount: 5);
    final summary = frameTimeline.summaryOrNull();
    _require(
      scrolled && summary != null && summary.sampleCount >= 5,
      'transcript_scroll_timeline',
    );
    return summary!;
  }

  static void _require(bool condition, String stage) {
    if (!condition) throw _PackagedReleasePerformanceProbeFailure(stage);
  }
}

class _HistoryFixtureMetrics {
  final Duration taskSummaryPage5000;
  final Duration threadSummaryPage1000;
  final Duration threadHydration1000;

  const _HistoryFixtureMetrics({
    required this.taskSummaryPage5000,
    required this.threadSummaryPage1000,
    required this.threadHydration1000,
  });
}

class PackagedReleasePerformanceProbeResult {
  final bool passed;
  final String stage;
  final Duration? dartMainToFirstFrame;
  final Duration? projectBind;
  final Duration? firstStreamFrame;
  final Duration? tenThousandDeltaBurst;
  final int? tenThousandDeltaStateUpdates;
  final Duration? taskSwitch;
  final Duration? durableReload;
  final Duration? taskSummaryPage5000;
  final Duration? threadSummaryPage1000;
  final Duration? threadHydration1000;
  final Duration? projectRecoveryAndMetadata500;
  final Duration? semanticIndexRebuild1200;
  final Duration? durableCheckpointPersistence;
  final int? residentSetBytes;
  final PackagedReleaseFrameTimingSummary? streamFrameTimeline;
  final PackagedReleaseFrameTimingSummary? transcriptScrollFrameTimeline;

  const PackagedReleasePerformanceProbeResult._({
    required this.passed,
    required this.stage,
    this.dartMainToFirstFrame,
    this.projectBind,
    this.firstStreamFrame,
    this.tenThousandDeltaBurst,
    this.tenThousandDeltaStateUpdates,
    this.taskSwitch,
    this.durableReload,
    this.taskSummaryPage5000,
    this.threadSummaryPage1000,
    this.threadHydration1000,
    this.projectRecoveryAndMetadata500,
    this.semanticIndexRebuild1200,
    this.durableCheckpointPersistence,
    this.residentSetBytes,
    this.streamFrameTimeline,
    this.transcriptScrollFrameTimeline,
  });

  const PackagedReleasePerformanceProbeResult.failed(String stage)
    : this._(passed: false, stage: stage);

  factory PackagedReleasePerformanceProbeResult.passed({
    required Duration dartMainToFirstFrame,
    required Duration projectBind,
    required Duration firstStreamFrame,
    required Duration tenThousandDeltaBurst,
    required int tenThousandDeltaStateUpdates,
    required Duration taskSwitch,
    required Duration durableReload,
    required Duration taskSummaryPage5000,
    required Duration threadSummaryPage1000,
    required Duration threadHydration1000,
    required Duration projectRecoveryAndMetadata500,
    required Duration semanticIndexRebuild1200,
    required Duration durableCheckpointPersistence,
    required int residentSetBytes,
    PackagedReleaseFrameTimingSummary? streamFrameTimeline,
    PackagedReleaseFrameTimingSummary? transcriptScrollFrameTimeline,
  }) => PackagedReleasePerformanceProbeResult._(
    passed: true,
    stage: 'ok',
    dartMainToFirstFrame: dartMainToFirstFrame,
    projectBind: projectBind,
    firstStreamFrame: firstStreamFrame,
    tenThousandDeltaBurst: tenThousandDeltaBurst,
    tenThousandDeltaStateUpdates: tenThousandDeltaStateUpdates,
    taskSwitch: taskSwitch,
    durableReload: durableReload,
    taskSummaryPage5000: taskSummaryPage5000,
    threadSummaryPage1000: threadSummaryPage1000,
    threadHydration1000: threadHydration1000,
    projectRecoveryAndMetadata500: projectRecoveryAndMetadata500,
    semanticIndexRebuild1200: semanticIndexRebuild1200,
    durableCheckpointPersistence: durableCheckpointPersistence,
    residentSetBytes: residentSetBytes,
    streamFrameTimeline: streamFrameTimeline,
    transcriptScrollFrameTimeline: transcriptScrollFrameTimeline,
  );

  /// Keep the host output safe to retain in a CI summary or release record.
  Map<String, Object> toJson() {
    final startup = dartMainToFirstFrame;
    final bind = projectBind;
    final stream = firstStreamFrame;
    final streamBurst = tenThousandDeltaBurst;
    final streamBurstUpdates = tenThousandDeltaStateUpdates;
    final switchDuration = taskSwitch;
    final reload = durableReload;
    final taskPage = taskSummaryPage5000;
    final threadPage = threadSummaryPage1000;
    final threadHydration = threadHydration1000;
    final projectRecovery = projectRecoveryAndMetadata500;
    final indexRebuild = semanticIndexRebuild1200;
    final checkpointPersistence = durableCheckpointPersistence;
    final rss = residentSetBytes;
    final frameTimeline = streamFrameTimeline;
    final scrollFrameTimeline = transcriptScrollFrameTimeline;
    return {
      'passed': passed,
      'stage': stage,
      if (startup != null)
        'dartMainToFirstFrameMilliseconds': startup.inMilliseconds,
      if (bind != null) 'projectBindMilliseconds': bind.inMilliseconds,
      if (stream != null) 'firstStreamFrameMilliseconds': stream.inMilliseconds,
      if (streamBurst != null)
        'streamTenThousandDeltaBurstMilliseconds': streamBurst.inMilliseconds,
      if (streamBurstUpdates case final int streamBurstUpdates)
        'streamTenThousandDeltaStateUpdates': streamBurstUpdates,
      if (switchDuration != null)
        'taskSwitchMilliseconds': switchDuration.inMilliseconds,
      if (reload != null) 'durableReloadMilliseconds': reload.inMilliseconds,
      if (taskPage != null)
        'taskSummaryPage5000Milliseconds': taskPage.inMilliseconds,
      if (threadPage != null)
        'threadSummaryPage1000Milliseconds': threadPage.inMilliseconds,
      if (threadHydration != null)
        'threadHydration1000Milliseconds': threadHydration.inMilliseconds,
      if (projectRecovery != null)
        'projectRecoveryAndMetadata500Milliseconds':
            projectRecovery.inMilliseconds,
      if (indexRebuild != null)
        'semanticIndexRebuild1200Milliseconds': indexRebuild.inMilliseconds,
      if (checkpointPersistence != null)
        'durableCheckpointPersistenceMilliseconds':
            checkpointPersistence.inMilliseconds,
      if (rss case final int residentSetBytes)
        'residentSetBytes': residentSetBytes,
      if (frameTimeline
          case final PackagedReleaseFrameTimingSummary timeline) ...{
        'streamFrameTimingSampleCount': timeline.sampleCount,
        'streamFrameBuildP95Milliseconds': timeline.buildP95.inMilliseconds,
        'streamFrameRasterP95Milliseconds': timeline.rasterP95.inMilliseconds,
        'streamFrameTotalP95Milliseconds': timeline.totalP95.inMilliseconds,
      },
      if (scrollFrameTimeline
          case final PackagedReleaseFrameTimingSummary timeline) ...{
        'transcriptScrollFrameTimingSampleCount': timeline.sampleCount,
        'transcriptScrollFrameBuildP95Milliseconds':
            timeline.buildP95.inMilliseconds,
        'transcriptScrollFrameRasterP95Milliseconds':
            timeline.rasterP95.inMilliseconds,
        'transcriptScrollFrameTotalP95Milliseconds':
            timeline.totalP95.inMilliseconds,
      },
    };
  }

  String toMachineLine() =>
      '${PackagedReleasePerformanceProbe.readyMarker}${jsonEncode(toJson())}';
}

class _PackagedReleasePerformanceProbeFailure implements Exception {
  final String stage;

  const _PackagedReleasePerformanceProbeFailure(this.stage);
}
