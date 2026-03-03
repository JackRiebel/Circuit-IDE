import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/mcp/mcp_client.dart';
import '../agent/mcp/mcp_config.dart';
import '../agent/mcp/mcp_config_storage.dart';
import '../agent/providers/provider_interface.dart';
import '../core/utils/logger.dart';

enum McpConnectionState { disconnected, connecting, connected, error }

class McpServerStatus {
  final McpServerConfig config;
  final McpConnectionState connectionState;
  final int toolCount;
  final String? error;

  const McpServerStatus({
    required this.config,
    this.connectionState = McpConnectionState.disconnected,
    this.toolCount = 0,
    this.error,
  });

  McpServerStatus copyWith({
    McpServerConfig? config,
    McpConnectionState? connectionState,
    int? toolCount,
    String? error,
  }) {
    return McpServerStatus(
      config: config ?? this.config,
      connectionState: connectionState ?? this.connectionState,
      toolCount: toolCount ?? this.toolCount,
      error: error,
    );
  }
}

class McpHubState {
  final List<McpServerStatus> servers;
  final bool isLoading;

  const McpHubState({
    this.servers = const [],
    this.isLoading = false,
  });

  McpHubState copyWith({
    List<McpServerStatus>? servers,
    bool? isLoading,
  }) {
    return McpHubState(
      servers: servers ?? this.servers,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  int get connectedCount =>
      servers.where((s) => s.connectionState == McpConnectionState.connected).length;

  int get totalToolCount =>
      servers.fold(0, (sum, s) => sum + s.toolCount);
}

class McpHubNotifier extends Notifier<McpHubState> {
  final McpClient _client = McpClient();
  final _storage = McpConfigStorage();

  @override
  McpHubState build() {
    ref.onDispose(() => _client.disconnectAll());
    Future.microtask(() => loadAndConnect());
    return const McpHubState(isLoading: true);
  }

  McpClient get client => _client;

  List<ToolDefinition> get toolDefinitions => _client.toolDefinitions;

  Future<void> loadAndConnect() async {
    state = state.copyWith(isLoading: true);
    try {
      final configs = await _storage.load();
      final servers = configs
          .map((c) => McpServerStatus(config: c))
          .toList();
      state = state.copyWith(servers: servers, isLoading: false);

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
    await _client.disconnectServer(name);
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

  Future<void> _connectServer(String name) async {
    final serverStatus = state.servers.firstWhere(
      (s) => s.config.name == name,
      orElse: () => throw StateError('Server not found: $name'),
    );

    _updateServerStatus(name, McpConnectionState.connecting);

    try {
      await _client.connectServer(serverStatus.config);

      final toolCount = _client.availableTools
          .where((t) => t.serverName == name)
          .length;

      _updateServerStatus(
        name,
        McpConnectionState.connected,
        toolCount: toolCount,
      );
    } catch (e) {
      _updateServerStatus(
        name,
        McpConnectionState.error,
        error: e.toString(),
      );
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

  Future<void> _saveConfigs() async {
    final configs = state.servers.map((s) => s.config).toList();
    await _storage.save(configs);
  }
}

final mcpHubProvider = NotifierProvider<McpHubNotifier, McpHubState>(
  McpHubNotifier.new,
);
