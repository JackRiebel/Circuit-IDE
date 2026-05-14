import 'mcp_config.dart';

/// Predefined Jira MCP server configuration
class JiraMcp {
  static const requiredEnvVars = ['JIRA_URL', 'JIRA_EMAIL', 'JIRA_TOKEN'];

  static McpServerConfig createConfig({
    String? scriptPath,
    int port = 5002,
    String name = 'jira',
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

  /// Well-known Jira MCP tool names
  static const knownTools = [
    'search_issues',
    'get_issue',
    'create_issue',
    'update_issue',
    'add_comment',
    'transition_issue',
    'list_projects',
    'assign_issue',
    'list_sprints',
    'get_sprint_issues',
  ];
}
