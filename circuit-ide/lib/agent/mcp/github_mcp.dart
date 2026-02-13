import 'mcp_config.dart';

/// Predefined GitHub MCP server configuration
class GitHubMcp {
  static McpServerConfig createConfig({
    required String token,
    String name = 'github',
  }) {
    return McpServerConfig(
      name: name,
      url: 'https://api.githubcopilot.com/mcp',
      transport: McpTransportType.http,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
      enabled: true,
    );
  }

  /// Well-known GitHub MCP tool names
  static const knownTools = [
    'create_or_update_file',
    'search_repositories',
    'create_repository',
    'get_file_contents',
    'push_files',
    'create_issue',
    'create_pull_request',
    'fork_repository',
    'create_branch',
    'list_commits',
    'list_issues',
    'update_issue',
    'add_issue_comment',
    'search_code',
    'search_issues',
    'search_users',
    'get_issue',
    'get_pull_request',
    'list_pull_requests',
    'create_or_update_file',
  ];
}
