import '../providers/provider_interface.dart';

class ToolRegistry {
  static const readOnlyTools = {
    'read_file',
    'lsdf_read_index',
    'list_files',
    'search_files',
    'git_status',
    'git_diff',
    'git_log',
    'git_branch',
    'web_fetch',
    'web_search',
    'github_whoami',
    'github_list_repos',
    'github_get_repo',
    'github_list_issues',
    'github_get_issue',
    'github_list_prs',
    'github_get_pr',
    'github_search_repos',
    'github_search_issues',
  };

  /// Check if a tool name is an MCP-proxied tool
  static bool isMcpTool(String name) => name.startsWith('mcp_');

  /// MCP tools are treated as read-only (they don't modify local files)
  static bool isReadOnlyIncludingMcp(String name) =>
      readOnlyTools.contains(name) || isMcpTool(name);

  static const confirmationRequired = {
    'write_file',
    'edit_file',
    'run_command',
    'git_commit',
    'github_create_repo',
    'github_create_issue',
    'github_close_issue',
  };

  static bool isReadOnly(String toolName) => readOnlyTools.contains(toolName);
  static bool needsConfirmation(String toolName) =>
      confirmationRequired.contains(toolName);

  static List<ToolDefinition> get allTools => [
    ..._fileTools,
    ..._lsdfTools,
    ..._gitTools,
    ..._webTools,
    ..._githubTools,
    ..._orchestrationTools,
  ];

  static final _fileTools = [
    const ToolDefinition(
      name: 'read_file',
      description:
          'Read the contents of a file. Returns line-numbered content.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Relative path to the file to read',
          },
          'start_line': {
            'type': 'integer',
            'description': 'Starting line number (1-indexed)',
          },
          'end_line': {
            'type': 'integer',
            'description': 'Ending line number (inclusive)',
          },
        },
        'required': ['path'],
      },
    ),
    const ToolDefinition(
      name: 'write_file',
      description: 'Create or overwrite a file with the given content.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Relative path for the file',
          },
          'content': {'type': 'string', 'description': 'Content to write'},
        },
        'required': ['path', 'content'],
      },
    ),
    const ToolDefinition(
      name: 'edit_file',
      description:
          'Edit a file by replacing exact text. The old_text must match exactly including whitespace.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Relative path to the file',
          },
          'old_text': {
            'type': 'string',
            'description': 'Exact text to find and replace',
          },
          'new_text': {'type': 'string', 'description': 'Replacement text'},
        },
        'required': ['path', 'old_text', 'new_text'],
      },
    ),
    const ToolDefinition(
      name: 'list_files',
      description:
          'List files matching a glob pattern in the working directory.',
      parameters: {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': 'Glob pattern (e.g., "**/*.py", "src/")',
          },
        },
        'required': ['pattern'],
      },
    ),
    const ToolDefinition(
      name: 'search_files',
      description: 'Search for a regex pattern across files.',
      parameters: {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': 'Regex pattern to search for',
          },
          'path': {
            'type': 'string',
            'description': 'Directory or file to search in',
          },
          'case_sensitive': {
            'type': 'boolean',
            'description': 'Case sensitive search (default: true)',
          },
        },
        'required': ['pattern'],
      },
    ),
    const ToolDefinition(
      name: 'run_command',
      description: 'Execute a shell command in the working directory.',
      parameters: {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Shell command to execute',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Timeout in seconds (default: 60, max: 300)',
          },
        },
        'required': ['command'],
      },
    ),
  ];

  static final _lsdfTools = [
    const ToolDefinition(
      name: 'lsdf_read_index',
      description:
          'Read compact L-SDF project or directory indexes for low-token codebase navigation before reading source files.',
      parameters: {
        'type': 'object',
        'properties': {
          'directory': {
            'type': 'string',
            'description':
                'Directory or file path whose nearest L-SDF index should be read. Defaults to project root.',
          },
          'detail': {
            'type': 'boolean',
            'description':
                'Read INDEX.detail.lsdf instead of INDEX.lsdf for signatures and source paths.',
          },
          'include_project': {
            'type': 'boolean',
            'description':
                'Also include project.lsdf from the repository root.',
          },
        },
      },
    ),
  ];

  static final _gitTools = [
    const ToolDefinition(
      name: 'git_status',
      description: 'Show the working tree status.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    const ToolDefinition(
      name: 'git_diff',
      description: 'Show changes in the working directory or between commits.',
      parameters: {
        'type': 'object',
        'properties': {
          'cached': {
            'type': 'boolean',
            'description': 'Show staged changes only',
          },
          'commit': {
            'type': 'string',
            'description': 'Compare with specific commit',
          },
        },
      },
    ),
    const ToolDefinition(
      name: 'git_log',
      description: 'Show commit history.',
      parameters: {
        'type': 'object',
        'properties': {
          'count': {
            'type': 'integer',
            'description': 'Number of commits to show (default: 10)',
          },
        },
      },
    ),
    const ToolDefinition(
      name: 'git_commit',
      description: 'Stage files and create a commit.',
      parameters: {
        'type': 'object',
        'properties': {
          'message': {'type': 'string', 'description': 'Commit message'},
          'files': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Files to stage (empty for all)',
          },
        },
        'required': ['message'],
      },
    ),
    const ToolDefinition(
      name: 'git_branch',
      description: 'List, create, switch, or delete branches.',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['list', 'create', 'switch', 'delete'],
            'description': 'Branch operation',
          },
          'name': {
            'type': 'string',
            'description': 'Branch name (for create/switch/delete)',
          },
        },
        'required': ['action'],
      },
    ),
  ];

  static final _webTools = [
    const ToolDefinition(
      name: 'web_fetch',
      description: 'Fetch content from a URL and return as markdown.',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'URL to fetch'},
          'selector': {
            'type': 'string',
            'description': 'Optional CSS selector to extract specific content',
          },
        },
        'required': ['url'],
      },
    ),
    const ToolDefinition(
      name: 'web_search',
      description: 'Search the web and return results.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search query'},
        },
        'required': ['query'],
      },
    ),
  ];

  static final _githubTools = [
    const ToolDefinition(
      name: 'github_whoami',
      description: 'Get the authenticated GitHub user.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    const ToolDefinition(
      name: 'github_list_repos',
      description: 'List repositories for the authenticated user.',
      parameters: {
        'type': 'object',
        'properties': {
          'sort': {
            'type': 'string',
            'enum': ['updated', 'created', 'pushed', 'full_name'],
          },
          'per_page': {'type': 'integer'},
        },
      },
    ),
    const ToolDefinition(
      name: 'github_get_repo',
      description: 'Get details of a specific repository.',
      parameters: {
        'type': 'object',
        'properties': {
          'owner': {'type': 'string'},
          'repo': {'type': 'string'},
        },
        'required': ['owner', 'repo'],
      },
    ),
    const ToolDefinition(
      name: 'github_list_issues',
      description: 'List issues for a repository.',
      parameters: {
        'type': 'object',
        'properties': {
          'owner': {'type': 'string'},
          'repo': {'type': 'string'},
          'state': {
            'type': 'string',
            'enum': ['open', 'closed', 'all'],
          },
        },
        'required': ['owner', 'repo'],
      },
    ),
    const ToolDefinition(
      name: 'github_get_issue',
      description: 'Get details of a specific issue.',
      parameters: {
        'type': 'object',
        'properties': {
          'owner': {'type': 'string'},
          'repo': {'type': 'string'},
          'number': {'type': 'integer'},
        },
        'required': ['owner', 'repo', 'number'],
      },
    ),
    const ToolDefinition(
      name: 'github_create_issue',
      description: 'Create a new issue.',
      parameters: {
        'type': 'object',
        'properties': {
          'owner': {'type': 'string'},
          'repo': {'type': 'string'},
          'title': {'type': 'string'},
          'body': {'type': 'string'},
        },
        'required': ['owner', 'repo', 'title'],
      },
    ),
    const ToolDefinition(
      name: 'github_list_prs',
      description: 'List pull requests for a repository.',
      parameters: {
        'type': 'object',
        'properties': {
          'owner': {'type': 'string'},
          'repo': {'type': 'string'},
          'state': {
            'type': 'string',
            'enum': ['open', 'closed', 'all'],
          },
        },
        'required': ['owner', 'repo'],
      },
    ),
    const ToolDefinition(
      name: 'github_get_pr',
      description: 'Get details of a specific pull request.',
      parameters: {
        'type': 'object',
        'properties': {
          'owner': {'type': 'string'},
          'repo': {'type': 'string'},
          'number': {'type': 'integer'},
        },
        'required': ['owner', 'repo', 'number'],
      },
    ),
    const ToolDefinition(
      name: 'github_search_repos',
      description: 'Search for repositories on GitHub.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      },
    ),
    const ToolDefinition(
      name: 'github_search_issues',
      description: 'Search for issues on GitHub.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      },
    ),
  ];

  static final _orchestrationTools = [
    const ToolDefinition(
      name: 'orchestrate',
      description:
          'Spawn a subagent to handle a specific task autonomously. '
          'The subagent has full tool access and will return its result. '
          'Use this for tasks that can run independently.',
      parameters: {
        'type': 'object',
        'properties': {
          'task': {
            'type': 'string',
            'description': 'Detailed task description for the subagent',
          },
          'name': {
            'type': 'string',
            'description':
                'Short name for this subagent (e.g., "test-writer", "refactorer")',
          },
        },
        'required': ['task', 'name'],
      },
    ),
  ];
}
