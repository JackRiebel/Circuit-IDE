import '../../core/utils/logger.dart';
import '../providers/provider_interface.dart';
import 'mcp_config.dart';
import 'mcp_transport.dart';

/// Manages connections to MCP servers and exposes their tools
class McpClient {
  final Map<String, _McpConnection> _connections = {};
  final List<McpToolInfo> _availableTools = [];

  List<McpToolInfo> get availableTools => List.unmodifiable(_availableTools);

  bool get hasConnections => _connections.isNotEmpty;

  Future<void> connectServer(McpServerConfig config) async {
    if (_connections.containsKey(config.name)) {
      await disconnectServer(config.name);
    }

    try {
      final transport = McpHttpTransport(config: config);

      // Initialize the connection
      final initResponse = await transport.initialize();
      if (initResponse.isError) {
        Logger.error(
          'MCP init failed for ${config.name}: ${initResponse.error}',
          null,
        );
        transport.dispose();
        return;
      }

      // List available tools
      final toolsResponse = await transport.listTools();
      final tools = <McpToolInfo>[];

      if (!toolsResponse.isError && toolsResponse.result != null) {
        final toolsList =
            (toolsResponse.result as Map<String, dynamic>)['tools'] as List?;
        if (toolsList != null) {
          for (final tool in toolsList) {
            final t = tool as Map<String, dynamic>;
            tools.add(McpToolInfo(
              serverName: config.name,
              name: t['name'] as String,
              description: t['description'] as String? ?? '',
              inputSchema: t['inputSchema'] as Map<String, dynamic>? ?? {},
            ));
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
    } catch (e) {
      Logger.error('Failed to connect MCP server ${config.name}', e);
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
      String toolName, Map<String, dynamic> arguments) async {
    // Find which server has this tool
    for (final connection in _connections.values) {
      final hasTool = connection.tools.any((t) => t.name == toolName);
      if (hasTool) {
        try {
          final response =
              await connection.transport.callTool(toolName, arguments);

          if (response.isError) {
            return 'MCP error: ${response.error?['message'] ?? 'Unknown error'}';
          }

          final result = response.result;
          if (result is Map<String, dynamic>) {
            final content = result['content'] as List?;
            if (content != null && content.isNotEmpty) {
              return content
                  .map((c) {
                    final item = c as Map<String, dynamic>;
                    return item['text'] as String? ?? item.toString();
                  })
                  .join('\n');
            }
          }

          return result?.toString() ?? 'No result';
        } catch (e) {
          return 'MCP tool error: $e';
        }
      }
    }

    return 'Error: Tool $toolName not found on any MCP server';
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
