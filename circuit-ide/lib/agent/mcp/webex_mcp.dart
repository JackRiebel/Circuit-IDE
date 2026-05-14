import 'mcp_config.dart';

/// Predefined Webex Teams MCP server configuration
class WebexMcp {
  static const requiredEnvVars = ['WEBEX_TOKEN'];

  static McpServerConfig createConfig({
    String? scriptPath,
    int port = 5001,
    String name = 'webex',
  }) {
    return McpServerConfig(
      name: name,
      url: 'http://localhost:$port/mcp',
      transport: McpTransportType.http,
      headers: const {'Accept': 'application/json'},
      enabled: true,
      scriptPath: scriptPath,
      requiredEnvVars: requiredEnvVars,
      port: port,
    );
  }

  /// Well-known Webex MCP tool names
  static const knownTools = [
    'list_rooms',
    'get_room',
    'create_room',
    'list_messages',
    'send_message',
    'list_people',
    'get_me',
    'list_memberships',
    'create_webhook',
    'delete_webhook',
    'list_webhooks',
  ];
}
