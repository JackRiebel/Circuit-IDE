import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/mcp/bot_agent_config.dart';
import '../agent/mcp/mcp_client.dart';
import '../agent/mcp/mcp_config.dart';
import '../agent/mcp/mcp_config_storage.dart';
import '../agent/mcp/mcp_token_storage.dart';
import '../agent/providers/provider_interface.dart';
import '../core/utils/logger.dart';
import '../services/mcp_process_manager.dart';

enum McpConnectionState { disconnected, connecting, connected, error }

class McpServerStatus {
  final McpServerConfig config;
  final McpConnectionState connectionState;
  final int toolCount;
  final String? error;
  final McpProcessState processState;

  const McpServerStatus({
    required this.config,
    this.connectionState = McpConnectionState.disconnected,
    this.toolCount = 0,
    this.error,
    this.processState = McpProcessState.stopped,
  });

  McpServerStatus copyWith({
    McpServerConfig? config,
    McpConnectionState? connectionState,
    int? toolCount,
    String? error,
    McpProcessState? processState,
  }) {
    return McpServerStatus(
      config: config ?? this.config,
      connectionState: connectionState ?? this.connectionState,
      toolCount: toolCount ?? this.toolCount,
      error: error,
      processState: processState ?? this.processState,
    );
  }
}

class McpHubState {
  final List<McpServerStatus> servers;
  final bool isLoading;
  final BotAgentStatus? botAgent;

  const McpHubState({
    this.servers = const [],
    this.isLoading = false,
    this.botAgent,
  });

  McpHubState copyWith({
    List<McpServerStatus>? servers,
    bool? isLoading,
    BotAgentStatus? botAgent,
  }) {
    return McpHubState(
      servers: servers ?? this.servers,
      isLoading: isLoading ?? this.isLoading,
      botAgent: botAgent ?? this.botAgent,
    );
  }

  int get connectedCount => servers
      .where((s) => s.connectionState == McpConnectionState.connected)
      .length;

  int get totalToolCount => servers.fold(0, (sum, s) => sum + s.toolCount);

  int get runningCount =>
      servers.where((s) => s.processState == McpProcessState.running).length;
}

class McpHubNotifier extends Notifier<McpHubState> {
  final McpClient _client = McpClient();
  final _storage = McpConfigStorage();
  final _processManager = McpProcessManager();
  final _tokenStorage = McpTokenStorage();
  StreamSubscription<(String, McpProcessState)>? _processStateSub;
  Process? _botProcess;

  @override
  McpHubState build() {
    ref.onDispose(() {
      _client.disconnectAll();
      unawaited(_processManager.dispose());
      _processStateSub?.cancel();
      _botProcess?.kill();
    });

    // Listen to process state changes
    _processStateSub = _processManager.stateChanges.listen((event) {
      final (name, procState) = event;
      _updateProcessState(name, procState);
    });

    Future.microtask(() => loadAndConnect());
    return const McpHubState(isLoading: true);
  }

  McpClient get client => _client;

  List<ToolDefinition> get toolDefinitions => _client.toolDefinitions;

  Future<void> loadAndConnect() async {
    state = state.copyWith(isLoading: true);
    try {
      final configs = await _storage.load();
      final servers = configs.map((c) => McpServerStatus(config: c)).toList();
      state = state.copyWith(servers: servers, isLoading: false);

      // Load bot config
      final botJson = await _storage.loadBotConfig();
      if (botJson != null) {
        final botConfig = BotAgentConfig.fromJson(botJson);
        state = state.copyWith(botAgent: BotAgentStatus(config: botConfig));
      }

      // Auto-connect enabled servers
      for (final config in configs) {
        if (config.enabled) {
          await _connectServer(config.name);
        }
      }
    } catch (e) {
      Logger.error('Failed to load MCP configs', e);
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> addServer(McpServerConfig config) async {
    final servers = List<McpServerStatus>.from(state.servers);
    servers.add(McpServerStatus(config: config));
    state = state.copyWith(servers: servers);
    await _saveConfigs();

    if (config.enabled) {
      await _connectServer(config.name);
    }
  }

  Future<void> removeServer(String name) async {
    await shutdownServer(name);
    await _tokenStorage.deleteTokens(
      name,
      state.servers
          .firstWhere((s) => s.config.name == name)
          .config
          .requiredEnvVars,
    );
    final servers = state.servers.where((s) => s.config.name != name).toList();
    state = state.copyWith(servers: servers);
    await _saveConfigs();
  }

  Future<void> toggleServer(String name, bool enabled) async {
    final servers = state.servers.map((s) {
      if (s.config.name == name) {
        return s.copyWith(config: s.config.copyWith(enabled: enabled));
      }
      return s;
    }).toList();
    state = state.copyWith(servers: servers);
    await _saveConfigs();

    if (enabled) {
      await _connectServer(name);
    } else {
      await _client.disconnectServer(name);
      _updateServerStatus(name, McpConnectionState.disconnected, toolCount: 0);
    }
  }

  // --- Process management ---

  /// Launch a server process, wait for startup, then connect.
  Future<void> launchServer(String name) async {
    final serverStatus = state.servers.firstWhere(
      (s) => s.config.name == name,
      orElse: () => throw StateError('Server not found: $name'),
    );

    await _processManager.startServer(serverStatus.config);

    // Give the Python process time to start listening
    await Future.delayed(const Duration(seconds: 2));

    // Auto-connect after launch
    if (_processManager.isRunning(name)) {
      await _connectServer(name);
    }
  }

  /// Disconnect the MCP client and stop the server process.
  Future<void> shutdownServer(String name) async {
    await _client.disconnectServer(name);
    _updateServerStatus(name, McpConnectionState.disconnected, toolCount: 0);
    await _processManager.stopServer(name);
  }

  // --- Token management ---

  Future<void> saveServerTokens(String name, Map<String, String> tokens) async {
    await _tokenStorage.saveTokens(name, tokens);
  }

  Future<void> replaceServerTokens(
    String name,
    List<String> envVars,
    Map<String, String> tokens,
  ) async {
    await _tokenStorage.replaceTokens(name, envVars, tokens);
  }

  Future<Map<String, String>> loadServerTokens(
    String name,
    List<String> envVars,
  ) async {
    return _tokenStorage.loadTokens(name, envVars);
  }

  // --- Bot agent ---

  Future<void> saveBotConfig(BotAgentConfig config) async {
    await _storage.saveBotConfig(config.toJson());
    state = state.copyWith(botAgent: BotAgentStatus(config: config));
  }

  Future<void> saveBotTokens(Map<String, String> tokens) async {
    await _tokenStorage.saveTokens('bot_agent', tokens);
  }

  Future<void> replaceBotTokens(Map<String, String> tokens) async {
    await _tokenStorage.replaceTokens(
      'bot_agent',
      BotAgentConfig.requiredEnvVars,
      tokens,
    );
  }

  Future<void> launchBotAgent() async {
    final botStatus = state.botAgent;
    if (botStatus == null || botStatus.config.scriptPath == null) return;

    state = state.copyWith(
      botAgent: botStatus.copyWith(state: BotAgentState.starting),
    );

    try {
      // Load tokens
      final tokens = await _tokenStorage.loadTokens(
        'bot_agent',
        BotAgentConfig.requiredEnvVars,
      );

      final env = <String, String>{
        ...Platform.environment,
        ...tokens,
        'PORT': botStatus.config.port.toString(),
        'MODEL': botStatus.config.model,
      };

      if (botStatus.config.systemPrompt != null) {
        env['SYSTEM_PROMPT'] = botStatus.config.systemPrompt!;
      }
      if (botStatus.config.roomIds.isNotEmpty) {
        env['ROOM_IDS'] = botStatus.config.roomIds.join(',');
      }
      if (botStatus.config.mcpServerUrls.isNotEmpty) {
        env['MCP_SERVER_URLS'] = botStatus.config.mcpServerUrls.join(',');
      }

      _botProcess = await Process.start('python3', [
        botStatus.config.scriptPath!,
      ], environment: env);

      String? ngrokUrl;

      // Parse stdout for ngrok URL
      _botProcess!.stdout.transform(const SystemEncoding().decoder).listen((
        data,
      ) {
        Logger.info('[bot stdout] $data', 'McpHubNotifier');
        // Look for ngrok URL pattern
        final match = RegExp(r'https://[a-z0-9]+\.ngrok\.io').firstMatch(data);
        if (match != null && ngrokUrl == null) {
          ngrokUrl = match.group(0);
          state = state.copyWith(
            botAgent: state.botAgent?.copyWith(publicUrl: ngrokUrl),
          );
        }
      });

      _botProcess!.stderr.transform(const SystemEncoding().decoder).listen((
        data,
      ) {
        Logger.warning('[bot stderr] $data', 'McpHubNotifier');
      });

      state = state.copyWith(
        botAgent: botStatus.copyWith(
          state: BotAgentState.running,
          pid: _botProcess!.pid,
        ),
      );

      _botProcess!.exitCode.then((code) {
        _botProcess = null;
        state = state.copyWith(
          botAgent: state.botAgent?.copyWith(
            state: code == 0 ? BotAgentState.stopped : BotAgentState.error,
            error: code != 0 ? 'Bot exited with code $code' : null,
          ),
        );
      });
    } catch (e) {
      state = state.copyWith(
        botAgent: botStatus.copyWith(
          state: BotAgentState.error,
          error: e.toString(),
        ),
      );
      Logger.error('Failed to launch bot agent', e);
    }
  }

  Future<void> stopBotAgent() async {
    if (_botProcess != null) {
      _botProcess!.kill(ProcessSignal.sigterm);
      final exited = await _botProcess!.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => -1,
      );
      if (exited == -1) {
        _botProcess!.kill(ProcessSignal.sigkill);
      }
      _botProcess = null;
    }
    state = state.copyWith(
      botAgent: state.botAgent?.copyWith(state: BotAgentState.stopped),
    );
  }

  // --- Internal ---

  Future<void> _connectServer(String name) async {
    final serverStatus = state.servers.firstWhere(
      (s) => s.config.name == name,
      orElse: () => throw StateError('Server not found: $name'),
    );

    _updateServerStatus(name, McpConnectionState.connecting);

    try {
      final toolCount = await _client.connectServer(serverStatus.config);

      _updateServerStatus(
        name,
        McpConnectionState.connected,
        toolCount: toolCount,
      );
    } catch (e) {
      _updateServerStatus(name, McpConnectionState.error, error: e.toString());
    }
  }

  void _updateServerStatus(
    String name,
    McpConnectionState connectionState, {
    int? toolCount,
    String? error,
  }) {
    final servers = state.servers.map((s) {
      if (s.config.name == name) {
        return s.copyWith(
          connectionState: connectionState,
          toolCount: toolCount ?? s.toolCount,
          error: error,
        );
      }
      return s;
    }).toList();
    state = state.copyWith(servers: servers);
  }

  void _updateProcessState(String name, McpProcessState procState) {
    final servers = state.servers.map((s) {
      if (s.config.name == name) {
        return s.copyWith(
          processState: procState,
          error: _processManager.errorOf(name),
        );
      }
      return s;
    }).toList();
    state = state.copyWith(servers: servers);
  }

  Future<void> _saveConfigs() async {
    final configs = state.servers.map((s) => s.config).toList();
    await _storage.save(configs);
  }
}

final mcpHubProvider = NotifierProvider<McpHubNotifier, McpHubState>(
  McpHubNotifier.new,
);
