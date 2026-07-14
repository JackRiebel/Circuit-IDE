import '../providers/provider_interface.dart';

class ToolRegistry {
  static const readOnlyTools = {
    'read_file',
    'list_files',
    'search_files',
    'git_status',
    'git_diff',
    'git_log',
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

  /// MCP tools are not assumed safe; callers should use the permission policy.
  static bool isReadOnlyIncludingMcp(String name) =>
      readOnlyTools.contains(name);

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

  static List<ToolDefinition> toolsForMode(AgentToolMode mode) {
    final allowedNames = switch (mode) {
      AgentToolMode.chat => const <String>{},
      AgentToolMode.ask => _askToolNames,
      AgentToolMode.research => _researchToolNames,
      AgentToolMode.plan => _planToolNames,
      AgentToolMode.code => _codeToolNames,
      AgentToolMode.fix => _codeToolNames,
      AgentToolMode.review => _reviewToolNames,
      AgentToolMode.verify => _verifyToolNames,
      AgentToolMode.handoff => _handoffToolNames,
    };
    return allTools.where((tool) => allowedNames.contains(tool.name)).toList();
  }

  static List<ToolDefinition> toolsForModeAndPhase(
    AgentToolMode mode,
    AgentToolPhase phase,
  ) {
    final allowedNames = switch ((mode, phase)) {
      (AgentToolMode.chat, _) => const <String>{},
      (AgentToolMode.ask, _) => _askToolNames,
      (AgentToolMode.research, _) => _researchToolNames,
      (AgentToolMode.review, _) => _reviewToolNames,
      (AgentToolMode.handoff, _) => _handoffToolNames,
      (AgentToolMode.plan, _) => _planToolNames,
      (AgentToolMode.verify, _) => _verifyToolNames,
      (AgentToolMode.code || AgentToolMode.fix, AgentToolPhase.inspect) =>
        _askToolNames,
      (AgentToolMode.code || AgentToolMode.fix, AgentToolPhase.propose) =>
        _codeProposalToolNames,
      (AgentToolMode.code || AgentToolMode.fix, AgentToolPhase.apply) =>
        _codeApplyToolNames,
      (AgentToolMode.code || AgentToolMode.fix, AgentToolPhase.verify) =>
        _verifyToolNames,
    };
    return allTools.where((tool) => allowedNames.contains(tool.name)).toList();
  }

  static List<ToolDefinition> get allTools => [
    ..._fileTools,
    ..._patchTools,
    ..._delegationTools,
    ..._gitTools,
    ..._webTools,
    ..._githubTools,
  ];

  static final _patchTools = [
    const ToolDefinition(
      name: 'propose_patch',
      description:
          'Create a reviewable implementation plan or patch proposal. Use this for coding changes instead of asking the user to type approve. CircuitCode renders approval, revision, and rejection controls.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'summary': {'type': 'string'},
          'plan_markdown': {
            'type': 'string',
            'description':
                'Markdown plan shown in the Studio review panel. Include implementation steps, files, and verification.',
          },
          'assumptions': {
            'type': 'array',
            'description':
                'Explicit assumptions the user should review before implementation.',
            'items': {'type': 'string'},
          },
          'verification_steps': {
            'type': 'array',
            'description':
                'Specific checks CircuitCode should suggest after the patch is applied.',
            'items': {'type': 'string'},
          },
          'files': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
                'intent': {'type': 'string'},
                'operation': {
                  'type': 'string',
                  'enum': ['create', 'modify', 'delete'],
                  'description':
                      'Required for plan-only and applyable proposals. Use create for new files, modify for existing-file changes, and delete only when the user/accepted plan explicitly asks to remove a file.',
                },
                'content': {
                  'type': 'string',
                  'description':
                      'Full target file content when the proposal is ready for app-side apply. Required for applyable create/modify proposals. Omit only for plan-only proposals.',
                },
                'before': {
                  'type': 'string',
                  'description':
                      'Expected current file content. Required for applyable modify/delete proposals so CircuitCode can detect stale-file conflicts.',
                },
                'unified_diff': {
                  'type': 'string',
                  'description':
                      'Optional preview/explanation diff. CircuitCode cannot apply diff-only create/modify proposals; include content for app-side apply.',
                },
              },
              'required': ['path', 'intent', 'operation'],
            },
          },
        },
        'required': ['title', 'summary', 'files'],
      },
    ),
  ];

  static final _delegationTools = [
    const ToolDefinition(
      name: 'delegate_subagent',
      description:
          'Ask an isolated subagent to complete one bounded task. Supply only the context it needs and an explicit read-only tool grant. This always requires user review. A child never receives the parent conversation and cannot modify files; allow_reviewed_patch_proposal only permits a reviewable proposal.',
      parameters: {
        'type': 'object',
        'properties': {
          'task': {
            'type': 'string',
            'description': 'One bounded task for the child agent.',
          },
          'context': {
            'type': 'string',
            'description':
                'The exact, minimal context excerpt to share. Do not include a whole conversation.',
          },
          'tool_grant': {
            'type': 'array',
            'description':
                'Explicit child tools. Only read_file, list_files, search_files, git_status, git_diff, git_log, and conditionally propose_patch are allowed.',
            'items': {
              'type': 'string',
              'enum': [
                'read_file',
                'list_files',
                'search_files',
                'git_status',
                'git_diff',
                'git_log',
                'propose_patch',
              ],
            },
          },
          'allow_reviewed_patch_proposal': {
            'type': 'boolean',
            'description':
                'Permit only a reviewable patch proposal. It never applies changes.',
          },
        },
        'required': ['task'],
      },
    ),
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
          'Fallback exact-text edit. Prefer proposing a patch summary first when possible. The old_text must match exactly including whitespace.',
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
}

enum AgentToolMode {
  chat,
  ask,
  research,
  plan,
  code,
  fix,
  review,
  verify,
  handoff,
}

enum AgentToolPhase { inspect, propose, apply, verify }

const _askToolNames = {
  'read_file',
  'list_files',
  'search_files',
  'git_status',
  'git_diff',
  'git_log',
  'delegate_subagent',
};

/// Research is intentionally separate from Ask. It exposes only the network
/// tools, which remain subject to the project network policy and a per-call
/// approval. Workspace, patch, command, MCP, and Git tools are absent.
const _researchToolNames = {'web_search', 'web_fetch'};

const _codeToolNames = _codeProposalToolNames;

const _codeProposalToolNames = {..._askToolNames, 'propose_patch'};

// Patch application is app-owned. The model can propose patch data, but
// Studio review UI invokes apply_patch_set internally after user approval.
const _codeApplyToolNames = _codeProposalToolNames;

const _verifyToolNames = {..._askToolNames, 'run_command'};

const _planToolNames = {..._askToolNames, 'propose_patch'};

const _reviewToolNames = {
  'read_file',
  'list_files',
  'search_files',
  'git_status',
  'git_diff',
  'git_log',
};

const _handoffToolNames = {
  'read_file',
  'list_files',
  'search_files',
  'git_status',
  'git_diff',
  'git_log',
};
