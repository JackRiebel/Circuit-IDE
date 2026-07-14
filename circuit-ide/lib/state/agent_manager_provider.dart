import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../agent/memory/agent_config_storage.dart';
import '../core/utils/logger.dart';
import '../models/agent_config_model.dart';
import '../models/chat_message.dart';
import '../services/event_bus.dart';

const _uuid = Uuid();
const _advancedAgentsPausedMessage =
    'Custom agents run only from the Studio composer. Select an agent there so the request receives its declared context, tools, limits, and scoped approvals.';

enum AgentRunStatus { running, completed, error, cancelled }

class AgentInstance {
  final String instanceId;
  final String configId;
  final String name;
  final EventBus events;
  final List<ChatMessage> messages;
  final AgentRunStatus status;
  final String task;
  final String? error;
  final String streamingContent;

  const AgentInstance({
    required this.instanceId,
    required this.configId,
    required this.name,
    required this.events,
    this.messages = const [],
    this.status = AgentRunStatus.running,
    required this.task,
    this.error,
    this.streamingContent = '',
  });

  AgentInstance copyWith({
    List<ChatMessage>? messages,
    AgentRunStatus? status,
    String? error,
    String? streamingContent,
  }) {
    return AgentInstance(
      instanceId: instanceId,
      configId: configId,
      name: name,
      events: events,
      messages: messages ?? this.messages,
      status: status ?? this.status,
      task: task,
      error: error ?? this.error,
      streamingContent: streamingContent ?? this.streamingContent,
    );
  }
}

class AgentManagerState {
  final List<AgentConfigModel> configs;
  final Map<String, AgentInstance> running;
  final bool isLoading;

  const AgentManagerState({
    this.configs = const [],
    this.running = const {},
    this.isLoading = false,
  });

  AgentManagerState copyWith({
    List<AgentConfigModel>? configs,
    Map<String, AgentInstance>? running,
    bool? isLoading,
  }) {
    return AgentManagerState(
      configs: configs ?? this.configs,
      running: running ?? this.running,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AgentManagerNotifier extends Notifier<AgentManagerState> {
  final AgentConfigStorage _storage;
  final _managedEvents = <EventBus>{};

  AgentManagerNotifier({AgentConfigStorage? storage})
    : _storage = storage ?? AgentConfigStorage();

  @override
  AgentManagerState build() {
    ref.onDispose(_disposeAll);
    Future.microtask(() => loadConfigs());
    return const AgentManagerState(isLoading: true);
  }

  // --- Config CRUD ---

  Future<void> loadConfigs() async {
    if (!ref.mounted) return;
    state = state.copyWith(isLoading: true);
    try {
      final configs = await _storage.loadAll();
      if (!ref.mounted) return;
      state = state.copyWith(configs: configs, isLoading: false);
    } catch (e) {
      Logger.error('Failed to load agent configs', e);
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> saveConfig(AgentConfigModel config) async {
    await _storage.save(config);
    if (!ref.mounted) return;
    final configs = List<AgentConfigModel>.from(state.configs);
    final idx = configs.indexWhere((c) => c.id == config.id);
    if (idx >= 0) {
      configs[idx] = config;
    } else {
      configs.insert(0, config);
    }
    state = state.copyWith(configs: configs);
  }

  Future<void> deleteConfig(String id) async {
    await _storage.delete(id);
    if (!ref.mounted) return;
    state = state.copyWith(
      configs: state.configs.where((c) => c.id != id).toList(),
    );
  }

  /// Creates an independently reviewable draft. Clones never inherit active
  /// status, so a changed prompt or capability set must be inspected before it
  /// can be selected in Studio.
  Future<AgentConfigModel?> cloneConfig(String id) async {
    final source = _configForId(id);
    if (source == null) return null;
    final clone = source.copyWith(
      id: _uuid.v4(),
      name: '${source.name} copy',
      enabled: false,
      createdAt: DateTime.now(),
      author: AgentAuthorMetadata(author: source.author.author, revision: '1'),
    );
    await saveConfig(clone);
    return clone;
  }

  /// Updates only activation state after the library has shown the requested
  /// tools, connectors, and risk summary. Invalid packages can never enable.
  Future<String?> setConfigEnabled(String id, bool enabled) async {
    final config = _configForId(id);
    if (config == null) return 'This agent is no longer available.';
    if (enabled) {
      final errors = config.validate();
      if (errors.isNotEmpty) return errors.first;
      final evaluation = config.evaluationReport;
      if (!evaluation.passedGate) {
        return 'Evaluation gate failed: ${evaluation.failures.first}';
      }
    }
    await saveConfig(
      config.copyWith(
        enabled: enabled,
        enabledAt: enabled ? DateTime.now() : config.enabledAt,
      ),
    );
    return null;
  }

  AgentConfigModel? _configForId(String id) {
    for (final config in state.configs) {
      if (config.id == id) return config;
    }
    return null;
  }

  // --- Agent lifecycle ---

  Future<void> spawnAgent(String configId, String task) async {
    AgentConfigModel? config;
    for (final candidate in state.configs) {
      if (candidate.id == configId) {
        config = candidate;
        break;
      }
    }
    if (config == null) {
      Logger.error('Cannot select a missing custom agent', null);
      return;
    }
    final instanceId = _uuid.v4();
    final events = EventBus();
    _managedEvents.add(events);
    final instance = AgentInstance(
      instanceId: instanceId,
      configId: configId,
      name: config.name,
      events: events,
      task: task,
      status: AgentRunStatus.error,
      error: _advancedAgentsPausedMessage,
    );
    final running = Map<String, AgentInstance>.from(state.running);
    running[instanceId] = instance;
    state = state.copyWith(running: running);
    Logger.info(
      'Custom agent launch redirected to Studio: ${config.name}',
      'AgentManager',
    );
  }

  Future<void> spawnMultiple(
    List<(String configId, String task)> agents,
  ) async {
    for (final (configId, task) in agents) {
      await spawnAgent(configId, task);
    }
  }

  /// Spawn an agent and await its response (for orchestration).
  Future<String> spawnAndAwait(String task, {String? name}) async {
    return 'Error: $_advancedAgentsPausedMessage';
  }

  void cancelAgent(String instanceId) {
    _updateInstance(
      instanceId,
      (i) => i.copyWith(status: AgentRunStatus.cancelled),
    );
  }

  void cancelAll() {
    for (final id in state.running.keys.toList()) {
      final instance = state.running[id];
      if (instance?.status == AgentRunStatus.running) {
        cancelAgent(id);
      }
    }
  }

  void removeAgent(String instanceId) {
    final events = state.running[instanceId]?.events;
    _managedEvents.remove(events);
    events?.dispose();
    final running = Map<String, AgentInstance>.from(state.running);
    running.remove(instanceId);
    state = state.copyWith(running: running);
  }

  void _updateInstance(
    String instanceId,
    AgentInstance Function(AgentInstance) updater,
  ) {
    final instance = state.running[instanceId];
    if (instance == null) return;
    final running = Map<String, AgentInstance>.from(state.running);
    running[instanceId] = updater(instance);
    state = state.copyWith(running: running);
  }

  void _disposeAll() {
    for (final events in _managedEvents) {
      events.dispose();
    }
    _managedEvents.clear();
  }
}

final agentManagerProvider =
    NotifierProvider<AgentManagerNotifier, AgentManagerState>(
      AgentManagerNotifier.new,
    );
