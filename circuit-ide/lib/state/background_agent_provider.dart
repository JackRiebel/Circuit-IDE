import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/context/smart_rules_matcher.dart';
import '../core/utils/logger.dart';
import '../enums/event_type.dart';
import '../models/agent_config_model.dart';
import '../models/agent_trigger.dart';
import 'agent_manager_provider.dart';
import 'connection_provider.dart';

const _backgroundAgentsPausedMessage =
    'Background agents are paused while Studio uses the request-local turn runtime. '
    'Run this task from Studio so it inherits intent routing, scoped approvals, and deterministic patch review.';

class BackgroundAgentState {
  final int runningCount;
  final List<BackgroundAgentResult> recentResults;

  const BackgroundAgentState({
    this.runningCount = 0,
    this.recentResults = const [],
  });

  BackgroundAgentState copyWith({
    int? runningCount,
    List<BackgroundAgentResult>? recentResults,
  }) {
    return BackgroundAgentState(
      runningCount: runningCount ?? this.runningCount,
      recentResults: recentResults ?? this.recentResults,
    );
  }
}

class BackgroundAgentResult {
  final String agentName;
  final String summary;
  final DateTime timestamp;
  final bool success;

  const BackgroundAgentResult({
    required this.agentName,
    required this.summary,
    required this.timestamp,
    this.success = true,
  });
}

class BackgroundAgentNotifier extends Notifier<BackgroundAgentState> {
  final _cooldowns = <String, DateTime>{};
  static const _cooldownDuration = Duration(seconds: 30);
  StreamSubscription? _eventSub;
  Timer? _periodicTimer;
  bool get _backgroundAgentsEnabled => false;

  @override
  BackgroundAgentState build() {
    ref.onDispose(() {
      _eventSub?.cancel();
      _periodicTimer?.cancel();
    });

    // Listen for agent completion events to update running count
    Future.microtask(_setupListeners);

    return const BackgroundAgentState();
  }

  void _setupListeners() {
    if (!_backgroundAgentsEnabled) {
      Logger.info(
        'Background agent listeners paused while Studio uses the request-local turn runtime.',
        'BackgroundAgent',
      );
      return;
    }
    final service = ref.read(agentServiceProvider);

    // Monitor agent manager for completion
    ref.listen(agentManagerProvider, (prev, next) {
      final running = next.running.values
          .where((i) => i.status == AgentRunStatus.running)
          .length;
      if (running != state.runningCount) {
        state = state.copyWith(runningCount: running);
      }

      // Check for newly completed agents
      if (prev != null) {
        for (final entry in next.running.entries) {
          final prevInstance = prev.running[entry.key];
          if (prevInstance?.status == AgentRunStatus.running &&
              entry.value.status != AgentRunStatus.running) {
            _onAgentCompleted(entry.value);
          }
        }
      }
    });

    // Listen for file save events
    service.events.on(EventType.toolCallCompleted, (event) {
      final toolName = event.data['tool'] as String?;
      if (toolName == 'write_file' || toolName == 'edit_file') {
        final filePath = event.data['path'] as String?;
        if (filePath != null) {
          _handleFileSaveTrigger(filePath);
        }
      }
    });

    // Start periodic timer for periodic triggers
    _periodicTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _handlePeriodicTriggers();
    });
  }

  void _onAgentCompleted(AgentInstance instance) {
    final summary = instance.messages.isNotEmpty
        ? instance.messages.last.content.split('\n').first
        : 'Completed';

    final results = [
      BackgroundAgentResult(
        agentName: instance.name,
        summary: summary.length > 100
            ? '${summary.substring(0, 100)}...'
            : summary,
        timestamp: DateTime.now(),
        success: instance.status == AgentRunStatus.completed,
      ),
      ...state.recentResults,
    ].take(10).toList();

    state = state.copyWith(recentResults: results);
  }

  void _handleFileSaveTrigger(String filePath) {
    if (!_backgroundAgentsEnabled) return;
    final configs = ref.read(agentManagerProvider).configs;
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) return;

    for (final config in configs) {
      for (final trigger in config.triggers) {
        if (trigger.type != AgentTriggerType.onFileSave || !trigger.enabled) {
          continue;
        }

        // Check file pattern match
        bool matches =
            trigger.filePatterns.isEmpty ||
            trigger.filePatterns.any(
              (p) => SmartRulesMatcher.matchesPattern(filePath, p),
            );

        if (matches && _checkCooldown(config.id, trigger.type)) {
          _spawnBackground(config, 'File saved: $filePath');
        }
      }
    }
  }

  void handleGitCommitTrigger() {
    if (!_backgroundAgentsEnabled) return;
    final configs = ref.read(agentManagerProvider).configs;
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) return;

    for (final config in configs) {
      if (config.hasEnabledTrigger(AgentTriggerType.onGitCommit) &&
          _checkCooldown(config.id, AgentTriggerType.onGitCommit)) {
        _spawnBackground(config, 'Git commit detected');
      }
    }
  }

  void handleProjectOpenTrigger() {
    if (!_backgroundAgentsEnabled) return;
    final configs = ref.read(agentManagerProvider).configs;
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) return;

    for (final config in configs) {
      if (config.hasEnabledTrigger(AgentTriggerType.onProjectOpen) &&
          _checkCooldown(config.id, AgentTriggerType.onProjectOpen)) {
        _spawnBackground(config, 'Project opened');
      }
    }
  }

  void _handlePeriodicTriggers() {
    if (!_backgroundAgentsEnabled) return;
    final configs = ref.read(agentManagerProvider).configs;
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) return;

    for (final config in configs) {
      for (final trigger in config.triggers) {
        if (trigger.type != AgentTriggerType.periodic || !trigger.enabled) {
          continue;
        }
        if (_checkCooldown(
          config.id,
          AgentTriggerType.periodic,
          cooldown: trigger.interval ?? const Duration(minutes: 5),
        )) {
          _spawnBackground(config, 'Periodic trigger');
        }
      }
    }
  }

  bool _checkCooldown(
    String configId,
    AgentTriggerType type, {
    Duration cooldown = _cooldownDuration,
  }) {
    final key = '$configId:${type.name}';
    final lastRun = _cooldowns[key];
    if (lastRun != null && DateTime.now().difference(lastRun) < cooldown) {
      return false;
    }
    _cooldowns[key] = DateTime.now();
    return true;
  }

  void _spawnBackground(AgentConfigModel config, String context) {
    if (!_backgroundAgentsEnabled) {
      Logger.info(
        'Background agent launch paused: ${config.name} ($context)',
        'BackgroundAgent',
      );
      final results = [
        BackgroundAgentResult(
          agentName: config.name,
          summary: _backgroundAgentsPausedMessage,
          timestamp: DateTime.now(),
          success: false,
        ),
        ...state.recentResults,
      ].take(10).toList();
      state = state.copyWith(recentResults: results);
      return;
    }
    Logger.info(
      'Background agent triggered: ${config.name} ($context)',
      'BackgroundAgent',
    );
    ref
        .read(agentManagerProvider.notifier)
        .spawnAgent(
          config.id,
          '${config.description.isNotEmpty ? config.description : config.systemPrompt}\n\nContext: $context',
        );
    state = state.copyWith(runningCount: state.runningCount + 1);
  }

  void dismissResult(int index) {
    final results = List<BackgroundAgentResult>.from(state.recentResults);
    if (index < results.length) {
      results.removeAt(index);
      state = state.copyWith(recentResults: results);
    }
  }
}

final backgroundAgentProvider =
    NotifierProvider<BackgroundAgentNotifier, BackgroundAgentState>(
      BackgroundAgentNotifier.new,
    );
