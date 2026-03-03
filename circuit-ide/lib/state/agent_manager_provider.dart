import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../agent/agent.dart';
import '../agent/memory/agent_config_storage.dart';
import '../core/utils/logger.dart';
import '../enums/event_type.dart';
import '../enums/message_role.dart';
import '../models/agent_config_model.dart';
import '../models/chat_message.dart';
import '../models/tool_call_info.dart';
import '../services/event_bus.dart';
import 'connection_provider.dart';

const _uuid = Uuid();

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
  final _storage = AgentConfigStorage();
  final _agents = <String, CircuitAgent>{};

  @override
  AgentManagerState build() {
    ref.onDispose(_disposeAll);
    Future.microtask(() => loadConfigs());
    return const AgentManagerState(isLoading: true);
  }

  // --- Config CRUD ---

  Future<void> loadConfigs() async {
    state = state.copyWith(isLoading: true);
    try {
      final configs = await _storage.loadAll();
      state = state.copyWith(configs: configs, isLoading: false);
    } catch (e) {
      Logger.error('Failed to load agent configs', e);
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> saveConfig(AgentConfigModel config) async {
    await _storage.save(config);
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
    state = state.copyWith(
      configs: state.configs.where((c) => c.id != id).toList(),
    );
  }

  // --- Agent lifecycle ---

  Future<void> spawnAgent(String configId, String task) async {
    final config = state.configs.firstWhere((c) => c.id == configId);
    final service = ref.read(agentServiceProvider);

    // Clone the provider from the main agent service
    // The agent manager reuses the same AI provider connection
    final mainAgent = service;
    if (!mainAgent.isConnected) {
      Logger.error('Cannot spawn agent — not connected', null);
      return;
    }

    final instanceId = _uuid.v4();
    final eventBus = EventBus();

    // Create the agent instance data first
    final instance = AgentInstance(
      instanceId: instanceId,
      configId: configId,
      name: config.name,
      events: eventBus,
      task: task,
    );

    final running = Map<String, AgentInstance>.from(state.running);
    running[instanceId] = instance;
    state = state.copyWith(running: running);

    // Now create and run the actual CircuitAgent
    _runAgent(instanceId, config, task, eventBus);
  }

  Future<void> spawnMultiple(
      List<(String configId, String task)> agents) async {
    for (final (configId, task) in agents) {
      await spawnAgent(configId, task);
    }
  }

  /// Spawn an agent and await its response (for orchestration).
  Future<String> spawnAndAwait(String task, {String? name}) async {
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) {
      return 'Error: Not connected to AI provider';
    }

    final instanceId = _uuid.v4();
    final eventBus = EventBus();

    final instance = AgentInstance(
      instanceId: instanceId,
      configId: 'orchestration',
      name: name ?? 'subagent',
      events: eventBus,
      task: task,
    );

    final running = Map<String, AgentInstance>.from(state.running);
    running[instanceId] = instance;
    state = state.copyWith(running: running);

    try {
      final agent = CircuitAgent(
        provider: service.provider!,
        workingDir: service.state.workingDir,
        events: eventBus,
        model: service.state.model,
        autoApprove: true, // Subagents auto-approve for autonomy
      );
      await agent.init();
      _agents[instanceId] = agent;
      _wireEvents(instanceId, eventBus);

      final response = await agent.chat(task);

      _updateInstance(instanceId, (i) => i.copyWith(
        status: AgentRunStatus.completed,
        streamingContent: '',
      ));

      return response;
    } catch (e) {
      _updateInstance(instanceId, (i) => i.copyWith(
        status: AgentRunStatus.error,
        error: e.toString().replaceFirst('Exception: ', ''),
        streamingContent: '',
      ));
      return 'Error: $e';
    }
  }

  void cancelAgent(String instanceId) {
    final agent = _agents[instanceId];
    agent?.cancel();
    _updateInstance(instanceId, (i) => i.copyWith(
      status: AgentRunStatus.cancelled,
    ));
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
    _agents[instanceId]?.cancel();
    _agents.remove(instanceId);
    final events = state.running[instanceId]?.events;
    events?.dispose();
    final running = Map<String, AgentInstance>.from(state.running);
    running.remove(instanceId);
    state = state.copyWith(running: running);
  }

  // --- Internal ---

  Future<void> _runAgent(
    String instanceId,
    AgentConfigModel config,
    String task,
    EventBus eventBus,
  ) async {
    final service = ref.read(agentServiceProvider);

    try {
      // Create a new CircuitAgent that shares the same provider
      // We access the provider through a fresh connection-like setup
      final agent = CircuitAgent(
        provider: service.provider!,
        workingDir: service.state.workingDir,
        events: eventBus,
        model: config.model,
        autoApprove: config.autoApprove,
      );

      // Override system prompt if configured
      if (config.systemPrompt.isNotEmpty) {
        agent.systemPromptOverride = config.systemPrompt;
      }
      await agent.init();

      _agents[instanceId] = agent;

      // Wire event handlers for UI updates
      _wireEvents(instanceId, eventBus);

      // Run the agent
      final response = await agent.chat(task);

      // Completed successfully
      final instance = state.running[instanceId];
      if (instance != null && instance.status == AgentRunStatus.running) {
        final assistantMsg = ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: response,
          timestamp: DateTime.now(),
        );
        _updateInstance(instanceId, (i) => i.copyWith(
          status: AgentRunStatus.completed,
          messages: [...i.messages, assistantMsg],
          streamingContent: '',
        ));
      }
    } catch (e) {
      Logger.error('Agent $instanceId failed', e);
      _updateInstance(instanceId, (i) => i.copyWith(
        status: AgentRunStatus.error,
        error: e.toString().replaceFirst('Exception: ', ''),
        streamingContent: '',
      ));
    }
  }

  void _wireEvents(String instanceId, EventBus eventBus) {
    eventBus.on(EventType.messageChunk, (event) {
      final content = event.data['content'] as String? ?? '';
      _updateInstance(instanceId, (i) => i.copyWith(
        streamingContent: i.streamingContent + content,
      ));
    });

    eventBus.on(EventType.toolCallStarted, (event) {
      final toolCall = event.data['toolCall'] as ToolCallInfo;
      final msg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: 'Using tool: ${toolCall.name}',
        timestamp: DateTime.now(),
        toolCalls: [toolCall],
      );
      _updateInstance(instanceId, (i) => i.copyWith(
        messages: [...i.messages, msg],
      ));
    });

    eventBus.on(EventType.messageError, (event) {
      final error = event.data['error'] as String? ?? 'Unknown error';
      _updateInstance(instanceId, (i) => i.copyWith(
        status: AgentRunStatus.error,
        error: error,
        streamingContent: '',
      ));
    });
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
    for (final agent in _agents.values) {
      agent.cancel();
    }
    _agents.clear();
    for (final instance in state.running.values) {
      instance.events.dispose();
    }
  }
}

final agentManagerProvider =
    NotifierProvider<AgentManagerNotifier, AgentManagerState>(
  AgentManagerNotifier.new,
);
