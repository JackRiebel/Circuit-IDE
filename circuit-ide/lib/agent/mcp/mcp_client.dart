import '../../core/utils/logger.dart';
import '../providers/provider_interface.dart';
import 'mcp_config.dart';
import 'mcp_transport.dart';

/// Manages connections to MCP servers and exposes their tools
class McpClient {
  final bool allowUnsafeMcpCalls;
  final Map<String, _McpConnection> _connections = {};
  final List<McpToolInfo> _availableTools = [];

  McpClient({this.allowUnsafeMcpCalls = false});

  List<McpToolInfo> get availableTools => List.unmodifiable(_availableTools);

  bool get hasConnections => _connections.isNotEmpty;

  Future<int> connectServer(McpServerConfig config) async {
    if (_connections.containsKey(config.name)) {
      await disconnectServer(config.name);
    }

    McpHttpTransport? transport;
    try {
      transport = await McpHttpTransport.create(config);

      // Initialize the connection
      final initResponse = await transport.initialize();
      if (initResponse.isError) {
        throw McpConnectionException(
          'MCP init failed: ${_errorMessage(initResponse)}',
        );
      }

      // List available tools
      final toolsResponse = await transport.listTools();
      final tools = <McpToolInfo>[];

      if (toolsResponse.isError) {
        throw McpConnectionException(
          'MCP tools/list failed: ${_errorMessage(toolsResponse)}',
        );
      }

      if (toolsResponse.result != null) {
        final toolsList =
            (toolsResponse.result as Map<String, dynamic>)['tools'] as List?;
        if (toolsList != null) {
          for (final tool in toolsList) {
            final t = tool as Map<String, dynamic>;
            tools.add(
              McpToolInfo(
                serverName: config.name,
                name: t['name'] as String,
                description: t['description'] as String? ?? '',
                inputSchema: t['inputSchema'] as Map<String, dynamic>? ?? {},
              ),
            );
          }
        }
      }

      _connections[config.name] = _McpConnection(
        config: config,
        transport: transport,
        tools: tools,
      );

      // Rebuild available tools list
      _rebuildToolsList();

      Logger.info(
        'Connected to MCP server ${config.name} with ${tools.length} tools',
        'McpClient',
      );
      return tools.length;
    } catch (e) {
      transport?.dispose();
      Logger.error('Failed to connect MCP server ${config.name}', e);
      throw McpConnectionException(e.toString());
    }
  }

  Future<void> disconnectServer(String name) async {
    final connection = _connections.remove(name);
    connection?.transport.dispose();
    _rebuildToolsList();
  }

  Future<void> disconnectAll() async {
    for (final connection in _connections.values) {
      connection.transport.dispose();
    }
    _connections.clear();
    _availableTools.clear();
  }

  /// Call a tool on the appropriate MCP server
  Future<String> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final guard = _guardToolDispatch(toolName, arguments);
    if (guard != null) return guard;

    // Find which server has this tool
    for (final connection in _connections.values) {
      final hasTool = connection.tools.any((t) => t.name == toolName);
      if (hasTool) {
        try {
          final response = await connection.transport.callTool(
            toolName,
            arguments,
          );

          if (response.isError) {
            return 'MCP error: ${response.error?['message'] ?? 'Unknown error'}';
          }

          final result = response.result;
          if (result is Map<String, dynamic>) {
            final content = result['content'] as List?;
            final isToolError = result['isError'] == true;
            if (content != null && content.isNotEmpty) {
              final text = content
                  .map((c) {
                    final item = c as Map<String, dynamic>;
                    return item['text'] as String? ?? item.toString();
                  })
                  .join('\n');
              return isToolError ? 'MCP error: $text' : text;
            }
            if (isToolError) return 'MCP error: ${result.toString()}';
          }

          return result?.toString() ?? 'No result';
        } catch (e) {
          return 'MCP tool error: $e';
        }
      }
    }

    return 'Error: Tool $toolName not found on any MCP server';
  }

  /// Call a tool on a specific MCP server.
  ///
  /// Provider-facing tool names include the server name (`mcp_server_tool`).
  /// Execution must preserve that binding so a same-named tool from another
  /// connected server cannot be called by accident.
  Future<String> callToolOnServer(
    String serverName,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final guard = _guardToolDispatch(
      toolName,
      arguments,
      serverName: serverName,
    );
    if (guard != null) return guard;

    final connection = _connections[serverName];
    if (connection == null) {
      return 'Error: MCP server $serverName is not connected';
    }
    final hasTool = connection.tools.any((t) => t.name == toolName);
    if (!hasTool) {
      return 'Error: Tool $toolName not found on MCP server $serverName';
    }
    try {
      final response = await connection.transport.callTool(toolName, arguments);

      if (response.isError) {
        return 'MCP error: ${response.error?['message'] ?? 'Unknown error'}';
      }

      final result = response.result;
      if (result is Map<String, dynamic>) {
        final content = result['content'] as List?;
        final isToolError = result['isError'] == true;
        if (content != null && content.isNotEmpty) {
          final text = content
              .map((c) {
                final item = c as Map<String, dynamic>;
                return item['text'] as String? ?? item.toString();
              })
              .join('\n');
          return isToolError ? 'MCP error: $text' : text;
        }
        if (isToolError) return 'MCP error: ${result.toString()}';
      }

      return result?.toString() ?? 'No result';
    } catch (e) {
      return 'MCP tool error: $e';
    }
  }

  /// Convert MCP tools to ToolDefinition for the AI provider
  List<ToolDefinition> get toolDefinitions {
    return _availableTools.map((t) {
      return ToolDefinition(
        name: 'mcp_${t.serverName}_${t.name}',
        description: '[MCP:${t.serverName}] ${t.description}',
        parameters: t.inputSchema,
      );
    }).toList();
  }

  bool isMcpTool(String name) => name.startsWith('mcp_');

  /// Parse MCP tool name back to server + tool name
  (String serverName, String toolName)? parseMcpToolName(String fullName) {
    if (!fullName.startsWith('mcp_')) return null;
    final rest = fullName.substring(4);
    final idx = rest.indexOf('_');
    if (idx == -1) return null;
    return (rest.substring(0, idx), rest.substring(idx + 1));
  }

  void _rebuildToolsList() {
    _availableTools.clear();
    for (final connection in _connections.values) {
      _availableTools.addAll(connection.tools);
    }
  }

  List<String> get connectedServers => _connections.keys.toList();

  String? _guardToolDispatch(
    String toolName,
    Map<String, dynamic> arguments, {
    String? serverName,
  }) {
    if (allowUnsafeMcpCalls) return null;
    if (_looksNetworkBacked(toolName, arguments, serverName: serverName)) {
      return 'Error: MCP tool blocked: MCP browser, web, URL, or network tools require explicit scoped review before dispatch.';
    }
    final risk = _riskFromToolName(toolName);
    return switch (risk) {
      _McpDispatchRisk.readOnly => null,
      _McpDispatchRisk.mutation =>
        'Error: MCP tool blocked: MCP mutation tools require explicit scoped review before dispatch.',
      _McpDispatchRisk.unknown =>
        'Error: MCP tool blocked: Unknown MCP tools require explicit scoped review before dispatch.',
    };
  }

  _McpDispatchRisk _riskFromToolName(String toolName) {
    final normalized = toolName.toLowerCase();
    if (RegExp(
      r'(^|_)(get|list|read|search|find|fetch|query|lookup|status|describe|view|show)(_|$)',
    ).hasMatch(normalized)) {
      return _McpDispatchRisk.readOnly;
    }
    if (RegExp(
      r'(^|_)(create|update|delete|remove|close|open|write|edit|set|send|post|put|patch|merge|assign|comment|reply|resolve|deploy)(_|$)',
    ).hasMatch(normalized)) {
      return _McpDispatchRisk.mutation;
    }
    return _McpDispatchRisk.unknown;
  }

  bool _looksNetworkBacked(
    String toolName,
    Map<String, dynamic> arguments, {
    String? serverName,
  }) {
    final normalized = [
      if (serverName?.trim().isNotEmpty == true) serverName!.trim(),
      toolName,
    ].join('_').toLowerCase();
    if (RegExp(
      r'(^|_)(browser|web|url|uri|http|https|fetch_url|fetch_page|open_url|navigate|crawl|scrape|download)(_|$)',
    ).hasMatch(normalized)) {
      return true;
    }
    return arguments.entries.any(
      (entry) => _containsNetworkTarget(entry.value, key: entry.key),
    );
  }

  bool _containsNetworkTarget(Object? value, {String? key}) {
    if (value is String) {
      final trimmed = value.trim();
      if (_containsUrl(trimmed)) return true;
      if (_isNetworkKey(key) && _containsBareNetworkHost(trimmed)) return true;
      return false;
    }
    if (value is Iterable) {
      return value.any((item) => _containsNetworkTarget(item, key: key));
    }
    if (value is Map) {
      return value.entries.any(
        (entry) => _containsNetworkTarget(
          entry.value,
          key: entry.key is String ? entry.key as String : key,
        ),
      );
    }
    return false;
  }

  bool _containsUrl(String text) {
    final match = RegExp(
      r"""\b(?:https?|wss?)://[^\s'"<>]+""",
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return false;
    final uri = Uri.tryParse(match.group(0) ?? '');
    return uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'ws' ||
            uri.scheme == 'wss') &&
        uri.host.trim().isNotEmpty;
  }

  bool _isNetworkKey(String? key) {
    final normalized = key?.trim().toLowerCase() ?? '';
    return const {
      'url',
      'uri',
      'endpoint',
      'domain',
      'host',
      'hostname',
      'target',
      'origin',
      'baseurl',
      'base_url',
    }.contains(normalized);
  }

  bool _containsBareNetworkHost(String text) {
    if (text.isEmpty) return false;
    final uri = Uri.tryParse(text);
    if (uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'ws' ||
            uri.scheme == 'wss') &&
        uri.host.trim().isNotEmpty) {
      return true;
    }
    return RegExp(
      r'\b((?:localhost)|(?:\d{1,3}(?:\.\d{1,3}){3})|(?:[a-z0-9-]+\.)+[a-z]{2,})\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  String _errorMessage(JsonRpcMessage response) {
    final error = response.error;
    if (error == null) return 'Unknown error';
    return error['message'] as String? ?? error.toString();
  }
}

enum _McpDispatchRisk { unknown, readOnly, mutation }

class McpConnectionException implements Exception {
  final String message;

  const McpConnectionException(this.message);

  @override
  String toString() => message;
}

class _McpConnection {
  final McpServerConfig config;
  final McpHttpTransport transport;
  final List<McpToolInfo> tools;

  _McpConnection({
    required this.config,
    required this.transport,
    required this.tools,
  });
}
