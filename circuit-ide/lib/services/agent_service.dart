import 'dart:async';

import 'package:uuid/uuid.dart';

import '../agent/agent.dart';
import '../agent/checkpoint/checkpoint_manager.dart';
import '../agent/config/config.dart';
import '../agent/config/model_router.dart';
import '../agent/config/models_config.dart';
import '../agent/memory/session_manager.dart';
import '../agent/providers/provider_interface.dart';
import '../agent/providers/cisco_provider.dart';
import '../agent/providers/anthropic_provider.dart';
import '../core/utils/logger.dart';
import '../agent/mcp/mcp_client.dart';
import '../enums/ai_provider.dart';
import '../enums/connection_status.dart';
import '../enums/event_type.dart';
import '../enums/message_role.dart';
import '../models/agent_state.dart';
import '../models/chat_message.dart';
import '../models/confirmation_request.dart';
import '../models/routing_models.dart';
import 'event_bus.dart';

class AgentService {
  final EventBus events = EventBus();
  final SessionManager _sessionManager = SessionManager();

  // Model routing state
  RoutingConfig? _routingConfig;
  String? _lastRoutedModel;
  void Function(double savings)? onRoutingSavings;

  CircuitAgent? _agent;
  AIProvider? _provider;
  AgentState _state = const AgentState();

  AgentState get state => _state;
  AIProvider? get provider => _provider;
  CheckpointManager? get checkpointManager => _agent?.checkpointManager;
  bool get isConnected => _state.connectionStatus == ConnectionStatus.connected;

  /// Active confirmation requests pending user response
  final _pendingConfirmations = <String, ConfirmationRequest>{};

  /// Stream of state changes
  Stream<AgentState> get stateStream => events.stream.map((_) => _state);

  void _updateState(AgentState Function(AgentState) updater) {
    _state = updater(_state);
    events.emit(EventType.statusChanged, {'state': _state});
  }

  /// Connect to the specified AI provider
  Future<bool> connect({
    required AIProviderType providerType,
    required Map<String, String> credentials,
    required String workingDir,
    String? model,
  }) async {
    _updateState(
      (s) => s.copyWith(
        connectionStatus: ConnectionStatus.connecting,
        workingDir: workingDir,
      ),
    );
    events.emit(EventType.connecting);

    try {
      // Create provider
      _provider = switch (providerType) {
        AIProviderType.cisco => CiscoProvider(),
        AIProviderType.anthropic => AnthropicProvider(),
      };

      await _provider!.connect(credentials);

      // Create agent
      final selectedModel = ModelsConfig.coerceModelForProvider(
        providerType,
        model,
      );

      _agent = CircuitAgent(
        provider: _provider!,
        workingDir: workingDir,
        events: events,
        model: selectedModel,
        autoApprove: _state.autoApprove,
        streamResponses: _state.streamResponses,
      );
      await _agent!.init();

      // Listen for confirmation events
      events.on(EventType.confirmationNeeded, (event) {
        final request = event.data['request'] as ConfirmationRequest;
        _pendingConfirmations[request.id] = request;
      });

      _updateState(
        (s) => s.copyWith(
          connectionStatus: ConnectionStatus.connected,
          model: selectedModel,
        ),
      );
      events.emit(EventType.connected);

      Logger.info(
        'Connected to ${providerType.displayName} with model $selectedModel',
        'AgentService',
      );
      return true;
    } catch (e) {
      Logger.error('Connection failed', e);
      _updateState(
        (s) => s.copyWith(
          connectionStatus: ConnectionStatus.error,
          error: e.toString(),
        ),
      );
      events.emit(EventType.connectionError, {'error': e.toString()});
      return false;
    }
  }

  /// Connect using saved credentials
  Future<bool> connectWithSavedCredentials({
    required String workingDir,
    AIProviderType? preferredProvider,
  }) async {
    final config = await AgentConfig.load();

    // Try preferred provider first, then fall back
    if (preferredProvider == AIProviderType.anthropic ||
        (preferredProvider == null && config.hasAnthropicCredentials)) {
      if (config.hasAnthropicCredentials) {
        return connect(
          providerType: AIProviderType.anthropic,
          credentials: {'api_key': config.anthropicApiKey!},
          workingDir: workingDir,
          model: config.model,
        );
      }
    }

    if (config.hasCiscoCredentials) {
      return connect(
        providerType: AIProviderType.cisco,
        credentials: {
          'client_id': config.ciscoClientId!,
          'client_secret': config.ciscoClientSecret!,
          'app_key': config.ciscoAppKey!,
        },
        workingDir: workingDir,
        model: config.model,
      );
    }

    Logger.warning('No saved credentials found', 'AgentService');
    return false;
  }

  void disconnect() {
    _provider?.disconnect();
    _agent = null;
    _provider = null;
    _pendingConfirmations.clear();
    _updateState((s) => const AgentState());
    events.emit(EventType.disconnected);
  }

  /// Update the agent's working directory (rebuilds agent with new dir)
  Future<void> updateWorkingDir(String newDir) async {
    if (_provider == null || !isConnected) return;

    final oldModel = _agent?.model ?? _state.model;
    final oldAutoApprove = _agent?.autoApprove ?? _state.autoApprove;

    _agent = CircuitAgent(
      provider: _provider!,
      workingDir: newDir,
      events: events,
      model: oldModel,
      autoApprove: oldAutoApprove,
    );
    await _agent!.init();

    _updateState((s) => s.copyWith(workingDir: newDir));
    Logger.info('Agent working directory updated to $newDir', 'AgentService');
  }

  /// Cancel the current operation
  void cancelCurrentOperation() {
    _agent?.cancel();
    _updateState((s) => s.copyWith(isProcessing: false));
  }

  /// Update routing config from provider
  void setRoutingConfig(RoutingConfig? config) {
    _routingConfig = config;
  }

  /// Get the last auto-routed model (null if routing was not used)
  String? get lastRoutedModel => _lastRoutedModel;

  /// Set MCP client on the active agent
  void setMcpClient(McpClient? client) {
    _agent?.setMcpClient(client);
  }

  /// Expose the agent for orchestration
  CircuitAgent? get agent => _agent;

  /// Get the active provider type
  AIProviderType? get activeProviderType {
    if (_provider is CiscoProvider) return AIProviderType.cisco;
    if (_provider is AnthropicProvider) return AIProviderType.anthropic;
    return null;
  }

  /// Send a message to the AI
  Future<String?> sendMessage(String content) async {
    if (_agent == null) {
      _updateState(
        (s) => s.copyWith(error: 'Agent not initialized — connect first'),
      );
      return null;
    }

    _updateState((s) => s.copyWith(isProcessing: true));

    // Apply model routing if enabled
    String? originalModel;
    _lastRoutedModel = null;
    if (_routingConfig != null &&
        _routingConfig!.enabled &&
        activeProviderType != null) {
      final complexity = ModelRouter.classify(content);
      final routed = ModelRouter.selectModel(
        complexity,
        activeProviderType!,
        _routingConfig!,
      );
      if (routed != _agent!.model) {
        originalModel = _agent!.model;
        _agent!.model = routed;
        _lastRoutedModel = routed;
        Logger.info(
          'Routed to $routed (complexity: ${complexity.name})',
          'ModelRouter',
        );

        // Track savings
        final savings = ModelRouter.estimateSavings(
          activeProviderType!,
          routed,
          500, // estimated tokens per request
        );
        if (savings > 0) {
          onRoutingSavings?.call(savings);
        }
      }
    }

    try {
      final response = await _agent!
          .chat(
            content,
            onContent: (chunk) {
              // State updates happen via events already
            },
          )
          .timeout(const Duration(minutes: 4));

      // Update service state (token/cost tracking only — UI messages
      // are owned by ChatNotifier, not synced from agent history)
      _updateState(
        (s) => s.copyWith(
          isProcessing: false,
          tokenUsage: _agent!.costTracker.totalUsage,
          lastTokenUsage: _agent!.costTracker.lastUsage,
          costInfo: _agent!.costTracker.costInfo,
        ),
      );

      return response;
    } on TimeoutException {
      _agent?.cancel();
      _updateState(
        (s) => s.copyWith(
          isProcessing: false,
          error: 'Request timed out after 4 minutes',
        ),
      );
      return null;
    } catch (e) {
      _updateState((s) => s.copyWith(isProcessing: false, error: e.toString()));
      return null;
    } finally {
      // Restore original model after routing
      if (originalModel != null && _agent != null) {
        _agent!.model = originalModel;
      }
    }
  }

  /// Approve a pending confirmation
  void approveConfirmation(String confirmationId) {
    _pendingConfirmations[confirmationId]?.approve();
    _pendingConfirmations.remove(confirmationId);
  }

  /// Reject a pending confirmation
  void rejectConfirmation(String confirmationId) {
    _pendingConfirmations[confirmationId]?.reject();
    _pendingConfirmations.remove(confirmationId);
  }

  /// Change the active model
  void setModel(String model) {
    _agent?.model = model;
    _updateState((s) => s.copyWith(model: model));
    events.emit(EventType.modelChanged, {'model': model});
  }

  /// Toggle auto-approve
  void setAutoApprove(bool value) {
    _agent?.autoApprove = value;
    _updateState((s) => s.copyWith(autoApprove: value));
  }

  /// Clear chat history
  void clearHistory() {
    _agent?.clearHistory();
    _updateState((s) => s.copyWith(messages: []));
  }

  /// Save current session
  Future<String?> saveSession({String? name}) async {
    if (_agent == null) return null;
    final sessionName = await _sessionManager.autoSave(
      history: _agent!.history,
      model: _agent!.model,
      workingDir: _agent!.workingDir,
      autoApprove: _agent!.autoApprove,
    );
    events.emit(EventType.sessionSaved, {'name': sessionName});
    return sessionName;
  }

  /// Load a saved session
  Future<bool> loadSession(String name) async {
    final session = await _sessionManager.load(name);
    if (session == null) return false;

    _agent?.history.clear();
    _agent?.history.addAll(session.history);
    _updateState((s) => s.copyWith(messages: List.of(session.history)));
    events.emit(EventType.sessionLoaded, {'name': name});
    return true;
  }

  /// Load a saved session and return its messages for UI display
  Future<List<ChatMessage>?> loadSessionMessages(String name) async {
    final session = await _sessionManager.load(name);
    if (session == null) return null;

    _agent?.history.clear();
    _agent?.history.addAll(session.history);
    _updateState((s) => s.copyWith(messages: List.of(session.history)));
    events.emit(EventType.sessionLoaded, {'name': name});
    return session.history;
  }

  /// List all saved sessions
  Future<List<String>> listSessions() async {
    return _sessionManager.listSessions();
  }

  /// Delete a saved session
  Future<bool> deleteSession(String name) async {
    return _sessionManager.delete(name);
  }

  /// Send a one-shot prompt to the AI without contaminating chat history.
  /// Used by Code Review, Semantic Search, and other features that need
  /// AI responses without affecting the main conversation.
  Future<String?> sendOneShot(String prompt, {String? systemPrompt}) async {
    if (_provider == null || !isConnected) return null;
    try {
      final messages = [
        ChatMessage(
          id: const Uuid().v4(),
          role: MessageRole.user,
          content: prompt,
          timestamp: DateTime.now(),
        ),
      ];
      String result = '';
      await for (final chunk in _provider!.chat(
        messages,
        model: _agent?.model ?? _state.model,
        tools: [],
        systemPrompt: systemPrompt,
      )) {
        if (chunk.content != null) result += chunk.content!;
      }
      return result.isEmpty ? null : result;
    } catch (e) {
      Logger.error('sendOneShot failed', e);
      return null;
    }
  }

  void dispose() {
    disconnect();
    events.dispose();
  }
}
