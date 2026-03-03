import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/logger.dart';
import '../enums/event_type.dart';
import '../models/vericoding_models.dart';
import '../services/project_detector.dart';
import '../services/vericode_config_storage.dart';
import '../services/vericode_engine.dart';
import 'connection_provider.dart';
import 'file_tree_provider.dart';

class VericodeState {
  final VericodeConfig config;
  final VericodeRun? currentRun;
  final List<VericodeRun> history;
  final bool isLoading;
  final ProjectType? detectedProjectType;
  final Map<String, bool> detectedFeatures;

  const VericodeState({
    this.config = const VericodeConfig(),
    this.currentRun,
    this.history = const [],
    this.isLoading = false,
    this.detectedProjectType,
    this.detectedFeatures = const {},
  });

  VericodeState copyWith({
    VericodeConfig? config,
    VericodeRun? currentRun,
    bool clearCurrentRun = false,
    List<VericodeRun>? history,
    bool? isLoading,
    ProjectType? detectedProjectType,
    Map<String, bool>? detectedFeatures,
  }) {
    return VericodeState(
      config: config ?? this.config,
      currentRun: clearCurrentRun ? null : (currentRun ?? this.currentRun),
      history: history ?? this.history,
      isLoading: isLoading ?? this.isLoading,
      detectedProjectType: detectedProjectType ?? this.detectedProjectType,
      detectedFeatures: detectedFeatures ?? this.detectedFeatures,
    );
  }
}

class VericodeNotifier extends Notifier<VericodeState> {
  final _storage = VericodeConfigStorage();
  VericodeEngine? _engine;
  bool _cancelled = false;

  @override
  VericodeState build() {
    Future.microtask(() async {
      await loadConfig();
      _wireAutoTrigger();
    });
    return const VericodeState(isLoading: true);
  }

  void _wireAutoTrigger() {
    try {
      final service = ref.read(agentServiceProvider);
      service.events.on(EventType.vericodeTriggered, (_) {
        if (state.config.enabled && state.config.autoRunAfterEdit) {
          verify(triggerSource: 'auto');
        }
      });
    } catch (_) {
      // Service not ready yet — will be wired when user connects
    }
  }

  Future<void> loadConfig() async {
    state = state.copyWith(isLoading: true);
    try {
      final hasSavedConfig = await _storage.hasSavedConfig();
      if (hasSavedConfig) {
        final config = await _storage.load();
        state = state.copyWith(config: config, isLoading: false);
      } else {
        // No saved config — auto-detect from project
        state = state.copyWith(isLoading: false);
        await autoDetectChecks();
      }
    } catch (e) {
      Logger.error('Failed to load vericode config', e);
      state = state.copyWith(isLoading: false);
    }
  }

  /// Scan the project directory and auto-configure checks based on what's found.
  Future<void> autoDetectChecks() async {
    String? rootPath;
    try {
      rootPath = ref.read(fileTreeProvider).rootPath;
    } catch (_) {}

    // Fall back to agent service working dir
    if (rootPath == null) {
      try {
        rootPath = ref.read(agentServiceProvider).state.workingDir;
      } catch (_) {}
    }

    if (rootPath == null || rootPath.isEmpty) {
      Logger.info(
          'No project path available for auto-detect', 'VericodeNotifier');
      // Fall back to default checks
      state = state.copyWith(
        config: VericodeConfig(checks: VericodeEngine.defaultChecks()),
      );
      return;
    }

    try {
      final detector = ProjectDetector(rootPath: rootPath);
      final result = await detector.detect();

      final checks = result.suggestedChecks.isNotEmpty
          ? result.suggestedChecks
          : VericodeEngine.defaultChecks();

      final config = state.config.copyWith(checks: checks);
      state = state.copyWith(
        config: config,
        detectedProjectType: result.primaryType,
        detectedFeatures: result.detectedFeatures,
      );
      await _storage.save(config);

      Logger.info(
          'Auto-detected ${result.primaryType.label} project with '
          '${checks.length} checks',
          'VericodeNotifier');
    } catch (e) {
      Logger.error('Auto-detect failed', e);
      state = state.copyWith(
        config: VericodeConfig(checks: VericodeEngine.defaultChecks()),
      );
    }
  }

  Future<void> verify({String triggerSource = 'manual'}) async {
    if (!state.config.enabled) return;
    if (state.currentRun?.status == VericodeRunStatus.runningChecks ||
        state.currentRun?.status == VericodeRunStatus.fixing ||
        state.currentRun?.status == VericodeRunStatus.rerunning) {
      return; // Already running
    }

    final service = ref.read(agentServiceProvider);
    final workingDir = service.state.workingDir;
    _engine = VericodeEngine(workingDir: workingDir);
    _cancelled = false;

    final enabledChecks =
        state.config.checks.where((c) => c.enabled).toList();
    if (enabledChecks.isEmpty) return;

    var run = VericodeRun(
      triggerSource: triggerSource,
      maxRetries: state.config.maxRetries,
    );

    state = state.copyWith(
      currentRun: run.copyWith(status: VericodeRunStatus.runningChecks),
    );

    for (int attempt = 0; attempt <= state.config.maxRetries; attempt++) {
      if (_cancelled) break;

      // Run checks
      final isRerun = attempt > 0;
      state = state.copyWith(
        currentRun: state.currentRun!.copyWith(
          status: isRerun
              ? VericodeRunStatus.rerunning
              : VericodeRunStatus.runningChecks,
        ),
      );

      final results = await _engine!.runAllChecks(enabledChecks);
      if (_cancelled) break;

      final failures = results.where((r) => !r.passed).toList();

      state = state.copyWith(
        currentRun: state.currentRun!.copyWith(currentResults: results),
      );

      // All passed
      if (failures.isEmpty) {
        final completedRun = state.currentRun!.copyWith(
          status: VericodeRunStatus.passed,
          currentResults: results,
          completedAt: DateTime.now(),
        );
        _addToHistory(completedRun);
        state = state.copyWith(currentRun: completedRun);
        _emitEvent(EventType.vericodePassed, {
          'attempt': attempt + 1,
          'triggerSource': triggerSource,
        });
        Logger.info('Vericoding passed on attempt ${attempt + 1}',
            'VericodeNotifier');
        return;
      }

      // Record this attempt
      final fixAttempt = VericodeFixAttempt(
        attemptNumber: attempt + 1,
        results: results,
        timestamp: DateTime.now(),
      );
      final attempts = [
        ...state.currentRun!.attempts,
        fixAttempt,
      ];
      state = state.copyWith(
        currentRun: state.currentRun!.copyWith(attempts: attempts),
      );

      // Last attempt — no more retries
      if (attempt >= state.config.maxRetries) break;

      // Ask AI to fix
      if (!service.isConnected) break;

      state = state.copyWith(
        currentRun: state.currentRun!.copyWith(
          status: VericodeRunStatus.analyzingFailures,
        ),
      );

      final fixPrompt = _engine!.generateFixPrompt(
        failures,
        attemptNumber: attempt + 1,
        maxAttempts: state.config.maxRetries,
      );

      state = state.copyWith(
        currentRun: state.currentRun!.copyWith(
          status: VericodeRunStatus.fixing,
        ),
      );

      try {
        await service.sendMessage(fixPrompt);
      } catch (e) {
        Logger.error('Vericoding AI fix failed', e);
        break;
      }

      if (_cancelled) break;

      // Loop to re-run checks
    }

    // If we get here, we've exhausted retries
    if (!_cancelled) {
      final failedRun = state.currentRun!.copyWith(
        status: VericodeRunStatus.failed,
        completedAt: DateTime.now(),
      );
      _addToHistory(failedRun);
      state = state.copyWith(currentRun: failedRun);
      _emitEvent(EventType.vericodeFailed, {
        'attempts': state.config.maxRetries,
        'triggerSource': triggerSource,
      });
      Logger.info('Vericoding failed after max retries', 'VericodeNotifier');
    }
  }

  void _emitEvent(EventType type, Map<String, dynamic> data) {
    try {
      ref.read(agentServiceProvider).events.emit(type, data);
    } catch (_) {}
  }

  void cancel() {
    _cancelled = true;
    if (state.currentRun != null) {
      final cancelledRun = state.currentRun!.copyWith(
        status: VericodeRunStatus.failed,
        completedAt: DateTime.now(),
      );
      _addToHistory(cancelledRun);
      state = state.copyWith(currentRun: cancelledRun);
    }
  }

  Future<void> updateConfig(VericodeConfig config) async {
    state = state.copyWith(config: config);
    await _storage.save(config);
  }

  void _addToHistory(VericodeRun run) {
    final history = [run, ...state.history];
    if (history.length > 20) {
      state = state.copyWith(history: history.sublist(0, 20));
    } else {
      state = state.copyWith(history: history);
    }
  }
}

final vericodingProvider =
    NotifierProvider<VericodeNotifier, VericodeState>(VericodeNotifier.new);
