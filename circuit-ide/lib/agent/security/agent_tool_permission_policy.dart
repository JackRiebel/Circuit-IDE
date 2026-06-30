import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/agent_tool_permission.dart';
import '../../models/tool_call_info.dart';
import '../../models/turn_intent.dart';
import 'command_sanitizer.dart';

class AgentToolPermissionPolicy {
  final String workingDir;
  final ToolPermissionRequest request;

  const AgentToolPermissionPolicy({
    required this.workingDir,
    this.request = const ToolPermissionRequest(
      intent: TurnIntent.ask,
      phase: ToolPermissionPhase.inspect,
    ),
  });

  ToolPermissionDecision evaluate(ToolCallInfo toolCall) {
    final name = toolCall.name;
    final intentContract = IntentContract.forIntent(request.intent);
    if (!intentContract.mayExposeTools) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.unknownTool,
        message: 'Tools are not available for this conversational turn.',
      );
    }
    if (_githubMutationTools.contains(name)) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.gitMutationRequiresReview,
        message:
            'GitHub mutation is not available in Studio turns until that connector is explicitly feature-enabled and scoped.',
      );
    }
    if (name.startsWith('mcp_')) {
      final mcpToolName = request.mcpToolName ?? name;
      if (_mcpLooksNetworkBacked(mcpToolName, toolCall)) {
        return const ToolPermissionDecision(
          verdict: ToolPermissionVerdict.deny,
          reason: ToolPermissionReason.mcpRequiresReview,
          message:
              'MCP browser, web, URL, or network tools are unavailable in Studio until that connector is explicitly feature-enabled and scoped.',
        );
      }
      final mcpRisk = request.mcpToolRisk == McpToolRisk.unknown
          ? _mcpRiskFromToolName(mcpToolName)
          : request.mcpToolRisk;
      if (mcpRisk == McpToolRisk.readOnly &&
          intentContract.mayInspectWorkspace) {
        return const ToolPermissionDecision(
          verdict: ToolPermissionVerdict.allow,
          reason: ToolPermissionReason.readOnlyInsideWorkspace,
          message: 'Read-only MCP inspection.',
          isReadOnly: true,
        );
      }
      if (mcpRisk == McpToolRisk.mutation) {
        return const ToolPermissionDecision(
          verdict: ToolPermissionVerdict.deny,
          reason: ToolPermissionReason.mcpRequiresReview,
          message:
              'MCP mutation is not available in Studio turns until that connector is explicitly feature-enabled and scoped.',
        );
      }
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.mcpRequiresReview,
        message:
            'Unknown MCP tools are unavailable in Studio until the connector declares read-only or mutation risk metadata.',
      );
    }

    if (_networkTools.contains(name)) {
      final accessKind = request.networkAccessKind == NetworkAccessKind.none
          ? _networkAccessKind(toolCall)
          : request.networkAccessKind;
      final domain = request.networkDomain ?? _networkDomain(toolCall);
      final blockedTarget = _blockedNetworkDecision(accessKind, domain);
      if (blockedTarget != null) return blockedTarget;
      final granted = _grantDecision(
        toolCall,
        'Network tool approved for this turn (${_networkDescription(accessKind, domain)}).',
        _networkGrantKey(name, accessKind, domain, toolCall: toolCall),
      );
      if (granted != null) return granted;
      return ToolPermissionDecision(
        verdict: ToolPermissionVerdict.ask,
        reason: ToolPermissionReason.networkRequiresReview,
        message:
            'Network access requires review (${_networkDescription(accessKind, domain)}).',
      );
    }

    if (_readOnlyTools.contains(name)) {
      if (!intentContract.mayInspectWorkspace) {
        return const ToolPermissionDecision(
          verdict: ToolPermissionVerdict.deny,
          reason: ToolPermissionReason.unknownTool,
          message:
              'Workspace inspection is not available for this turn intent.',
        );
      }
      final pathDecision = _pathDecision(toolCall);
      if (pathDecision != null) return pathDecision;
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.allow,
        reason: ToolPermissionReason.readOnlyInsideWorkspace,
        message: 'Read-only workspace inspection.',
        isReadOnly: true,
      );
    }

    if (name == 'git_branch') return _gitBranchDecision(toolCall);
    if (name == 'propose_patch') {
      if (!intentContract.mayProposePatch) {
        return const ToolPermissionDecision(
          verdict: ToolPermissionVerdict.deny,
          reason: ToolPermissionReason.unknownTool,
          message: 'Patch proposals are not available for this turn intent.',
        );
      }
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.allow,
        reason: ToolPermissionReason.readOnlyInsideWorkspace,
        message: 'Patch proposal does not modify files.',
      );
    }
    if (name == 'write_file' || name == 'edit_file') {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.writeRequiresReview,
        message:
            'Direct file writes are not available in Studio turns. Use a patch proposal and app-side apply transaction.',
      );
    }
    if (name == 'apply_patch_set') return _writeDecision(toolCall);
    if (name == 'run_command') return _commandDecision(toolCall);
    if (_gitMutationTools.contains(name)) {
      final gitPathDecision = _gitMutationArgumentDecision(toolCall);
      if (gitPathDecision != null) return gitPathDecision;
      final gitAvailability = _gitMutationAvailabilityDecision();
      if (gitAvailability != null) return gitAvailability;
      final granted = _grantDecision(
        toolCall,
        'Git mutation approved for this turn.',
        _toolGrantKey(name),
      );
      if (granted != null) return granted;
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.ask,
        reason: ToolPermissionReason.gitMutationRequiresReview,
        message: 'Git mutation requires review.',
      );
    }
    return const ToolPermissionDecision(
      verdict: ToolPermissionVerdict.ask,
      reason: ToolPermissionReason.unknownTool,
      message: 'Unknown tool requires review.',
    );
  }

  String approvalGrantKeyFor(ToolCallInfo toolCall) {
    return _approvalGrantKey(toolCall);
  }

  ToolPermissionDecision _writeDecision(ToolCallInfo toolCall) {
    if (toolCall.name == 'apply_patch_set') {
      final patchPathDecision = _patchSetPathDecision(toolCall);
      if (patchPathDecision != null) return patchPathDecision;
    }
    if (toolCall.name == 'apply_patch_set' && !request.allowPatchTransaction) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.writeRequiresReview,
        message:
            'Patch application is only available through an approved app-side patch transaction.',
      );
    }
    if (toolCall.name == 'apply_patch_set' &&
        request.phase != ToolPermissionPhase.apply) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.writeRequiresReview,
        message: 'Patch application is only available in the apply phase.',
      );
    }
    final pathDecision = _pathDecision(toolCall);
    if (pathDecision != null) return pathDecision;
    if (toolCall.name == 'apply_patch_set') {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.allow,
        reason: ToolPermissionReason.patchTransactionApproved,
        message: 'Approved app-side patch transaction.',
      );
    }
    final granted = _grantDecision(
      toolCall,
      'File write approved for this turn.',
      _toolGrantKey(toolCall.name),
    );
    if (granted != null) return granted;
    return const ToolPermissionDecision(
      verdict: ToolPermissionVerdict.ask,
      reason: ToolPermissionReason.writeRequiresReview,
      message: 'File write requires review.',
    );
  }

  ToolPermissionDecision _commandDecision(ToolCallInfo toolCall) {
    final category = request.commandCategory == CommandCategory.unknown
        ? _commandCategory(toolCall.arguments['command'] as String? ?? '')
        : request.commandCategory;
    if (category == CommandCategory.destructive) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.dangerousCommand,
        message: 'Destructive shell commands are blocked.',
      );
    }
    if (category == CommandCategory.secretAccess) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.secretPath,
        message: 'Commands that read secret or environment files are blocked.',
      );
    }
    if (category == CommandCategory.privileged) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.dangerousCommand,
        message: 'Privileged shell commands are blocked.',
      );
    }
    if (category == CommandCategory.compound) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.commandRequiresReview,
        message:
            'Compound shell commands are blocked. Run one command per approval so each action can be reviewed independently.',
      );
    }
    if (!IntentContract.forIntent(request.intent).mayRunCommands ||
        request.phase != ToolPermissionPhase.verify) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.commandRequiresReview,
        message: 'Shell commands are only available in Verify mode.',
      );
    }
    final command = toolCall.arguments['command'] as String? ?? '';
    final danger = CommandSanitizer.checkDangerous(command);
    if (danger != null) {
      return ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.dangerousCommand,
        message: 'Command blocked: $danger',
      );
    }
    final boundaryDecision = _commandWorkspaceBoundaryDecision(command);
    if (boundaryDecision != null) return boundaryDecision;
    if (category == CommandCategory.network) {
      final blockedNetworkTarget = CommandSanitizer.checkBlockedNetworkTarget(
        command,
      );
      if (blockedNetworkTarget != null) {
        return ToolPermissionDecision(
          verdict: ToolPermissionVerdict.deny,
          reason: ToolPermissionReason.networkRequiresReview,
          message: 'Network target is blocked: $blockedNetworkTarget',
        );
      }
      final accessKind = request.networkAccessKind == NetworkAccessKind.none
          ? _networkAccessKindFromText(command)
          : request.networkAccessKind;
      final domain = request.networkDomain ?? _networkDomainFromText(command);
      final blockedTarget = _blockedNetworkDecision(accessKind, domain);
      if (blockedTarget != null) return blockedTarget;
      final granted = _grantDecision(
        toolCall,
        'Network shell command approved for this turn (${_networkDescription(accessKind, domain)}).',
        _commandGrantKey(
          category,
          accessKind: accessKind,
          domain: domain,
          command: command,
        ),
      );
      if (granted != null) return granted;
      return ToolPermissionDecision(
        verdict: ToolPermissionVerdict.ask,
        reason: ToolPermissionReason.networkRequiresReview,
        message:
            'Network shell command requires review (${_networkDescription(accessKind, domain)}).',
      );
    }
    if (category == CommandCategory.install) {
      final granted = _grantDecision(
        toolCall,
        'Dependency installation approved for this turn.',
        _commandGrantKey(category, command: command),
      );
      if (granted != null) return granted;
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.ask,
        reason: ToolPermissionReason.commandRequiresReview,
        message:
            'Dependency installation can modify the workspace and requires review.',
      );
    }
    final granted = _grantDecision(
      toolCall,
      'Shell command approved for this turn.',
      _commandGrantKey(category, command: command),
    );
    if (granted != null) return granted;
    return const ToolPermissionDecision(
      verdict: ToolPermissionVerdict.ask,
      reason: ToolPermissionReason.commandRequiresReview,
      message: 'Shell command requires review.',
    );
  }

  CommandCategory _commandCategory(String command) {
    final normalized = command.trim().toLowerCase();
    if (RegExp(
      r'\b(rm\s+-[^\s]*r[^\s]*f|rm\s+-[^\s]*f[^\s]*r|rm\s+(?=(?:-[a-z]*r\b|--recursive\b|[^\n]*\s(?:-[a-z]*r\b|--recursive\b)))(?=(?:-[a-z]*f\b|--force\b|[^\n]*\s(?:-[a-z]*f\b|--force\b)))[^\n]*|git\s+reset\s+--hard|git\s+clean\s+-[^\n]*[fd]|git\s+push\s+([^\n]*\s)?(-f|--force(?:-with-lease)?)\b|mkfs|dd\s+if=)',
    ).hasMatch(normalized)) {
      return CommandCategory.destructive;
    }
    if (RegExp(
      r'\bgit\s+branch\s+([^\n]*\s)?(-d|-D|--delete)\b|\bgit\s+checkout\s+--\s+|\bgit\s+restore\s+([^\n]*\s)?[^\s]',
    ).hasMatch(normalized)) {
      return CommandCategory.destructive;
    }
    if (RegExp(
      r'(^|\s)(sudo|su)\b|\bchmod\s+777\b|\bchown\s+(-r\s+)?root\b',
    ).hasMatch(normalized)) {
      return CommandCategory.privileged;
    }
    if (RegExp(
      r'''(^|[\s'"`(])(cat|less|more|head|tail|grep|rg|sed|awk|perl|ls|find|stat|du)\s+[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.ssh\b|\.ssh/|\.aws\b|\.aws/|aws/credentials|\.azure\b|\.azure/|\.kube/config|\.docker/config\.json|\.config/gh/hosts\.yml|\.config/gcloud)''',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(r'(^|\s)(env|printenv|set)\s*($|[|;&>])').hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(
      r'(<|>|>>|\bsource\b|\.)\s*[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.ssh/|\.aws/|aws/credentials|\.azure/|\.kube/config|\.docker/config\.json|\.config/gh/hosts\.yml|\.config/gcloud)',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(
      r'''(^|[\s'"`(])(python|python3|node|ruby|php|perl)\b[^\n]*(open|readfilesync|file_get_contents|read_text|readbytes|read\s*\()[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.ssh/|\.aws/|aws/credentials|\.azure/|\.kube/config|\.docker/config\.json|\.config/gh/hosts\.yml|\.config/gcloud)''',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(
      r'''(^|[\s'"`(])(python|python3|node|ruby|php|perl)\b[^\n]*(os\.environ|process\.env|\benv\b|getenv|dotenv|load_dotenv)''',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(
      r'''(^|[\s'"`(])(cp|rsync|tar|zip|7z|gzip|gpg|base64)\b[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.ssh/|\.aws/|aws/credentials|\.azure/|\.kube/config|\.docker/config\.json|\.config/gh/hosts\.yml|\.config/gcloud)''',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(
      r'(^|\s)(security\s+(find-generic-password|find-internet-password|dump-keychain)|gh\s+auth\s+token|gcloud\s+auth\s+(print-access-token|print-identity-token)|aws\s+configure\s+get|firebase\s+functions:secrets:access|npm\s+token\b|vercel\s+env\s+(pull|ls|add|rm)|op\s+(read|item\s+get)|pass\s+(show|find)|doppler\s+secrets|vault\s+(read|kv\s+get))\b',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(
      r'(^|\s)(firebase|gh|gcloud|aws|az|vercel|netlify|flyctl|railway|render|doppler|vault)\s+([^\n]*\s)?(login|auth\s+login|sso\s+login)\b',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (_hasUnquotedShellControlOperator(command)) {
      return CommandCategory.compound;
    }
    if (RegExp(
      r'(^|\s)(npm|pnpm|yarn|bun|pip|pip3|pipx|poetry|uv|gem|bundle|cargo|go)\s+(install|add|get|update|upgrade)\b|(^|\s)(python|python3)\s+-m\s+(pip|pip3)\s+(install|add|get|update|upgrade)\b|(^|\s)(npx|bunx|uvx)\b|(^|\s)(pnpm|yarn)\s+dlx\b|(^|\s)(brew|apt|apt-get|dnf|yum|apk)\s+install\b',
    ).hasMatch(normalized)) {
      return CommandCategory.install;
    }
    if (CommandSanitizer.checkNetworkAccess(command) != null) {
      return CommandCategory.network;
    }
    if (RegExp(
      r'(^|\s)(firebase|vercel|netlify|flyctl|railway|render|gcloud|aws|az|kubectl|helm|gh)\s+([^\n]*\s)?(deploy|apply|sync|publish|release|workflow\s+run|run\s+deploy|functions:deploy|hosting:deploy|push|upload)\b',
    ).hasMatch(normalized)) {
      return CommandCategory.network;
    }
    if (RegExp(
      r'\b(test|pytest|flutter test|dart test|npm test|pnpm test|yarn test|cargo test|go test)\b',
    ).hasMatch(normalized)) {
      return CommandCategory.test;
    }
    if (RegExp(
      r'\b(build|flutter build|npm run build|pnpm build|yarn build)\b',
    ).hasMatch(normalized)) {
      return CommandCategory.build;
    }
    if (RegExp(
      r'\b(npm run dev|flutter run|python3? -m http.server)\b',
    ).hasMatch(normalized)) {
      return CommandCategory.devServer;
    }
    if (normalized.startsWith('git ')) return CommandCategory.git;
    if (RegExp(
      r'^(pwd|ls|find|git\s+(status|diff|log|show|branch)\b)',
    ).hasMatch(normalized)) {
      return CommandCategory.readOnly;
    }
    return CommandCategory.unknown;
  }

  ToolPermissionDecision? _commandWorkspaceBoundaryDecision(String command) {
    final boundary = CommandSanitizer.checkWorkspaceBoundary(
      command,
      workingDir,
    );
    if (boundary == null) return null;
    return const ToolPermissionDecision(
      verdict: ToolPermissionVerdict.deny,
      reason: ToolPermissionReason.pathOutsideWorkspace,
      message:
          'Shell commands may not read or modify paths outside the active workspace.',
    );
  }

  ToolPermissionDecision _gitBranchDecision(ToolCallInfo toolCall) {
    final action = (toolCall.arguments['action'] as String? ?? 'list')
        .toLowerCase();
    if (action == 'list' || action == 'current') {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.allow,
        reason: ToolPermissionReason.readOnlyInsideWorkspace,
        message: 'Read-only branch inspection.',
        isReadOnly: true,
      );
    }
    if (action != 'create' && action != 'switch' && action != 'delete') {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.gitMutationRequiresReview,
        message: 'Unknown branch action is not available.',
      );
    }
    final branchNameDecision = _gitBranchNameDecision(
      toolCall.arguments['name'] as String?,
    );
    if (branchNameDecision != null) return branchNameDecision;
    final gitAvailability = _gitMutationAvailabilityDecision();
    if (gitAvailability != null) return gitAvailability;
    final granted = _grantDecision(
      toolCall,
      'Branch mutation approved for this turn.',
      _gitBranchGrantKey(action),
    );
    if (granted != null) return granted;
    return const ToolPermissionDecision(
      verdict: ToolPermissionVerdict.ask,
      reason: ToolPermissionReason.gitMutationRequiresReview,
      message: 'Branch mutation requires review.',
    );
  }

  ToolPermissionDecision? _gitBranchNameDecision(String? rawName) {
    final name = rawName?.trim() ?? '';
    if (name.isEmpty) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.gitMutationRequiresReview,
        message: 'Branch mutation requires a branch name.',
      );
    }
    if (!_isSafeGitBranchName(name)) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.gitMutationRequiresReview,
        message:
            'Branch names must be plain safe Git refs, not options, revisions, path traversal, or pathspec-like values.',
      );
    }
    return null;
  }

  bool _isSafeGitBranchName(String name) {
    if (name.startsWith('-')) return false;
    if (name.startsWith('/') || name.endsWith('/')) return false;
    if (name.contains('..') || name.contains('@{')) return false;
    if (name == '@') return false;
    if (name.endsWith('.lock') || name.endsWith('.')) return false;
    if (name.contains('//')) return false;
    if (RegExp(r'''[\s\\~^:?*\[\]\x00-\x1f\x7f]''').hasMatch(name)) {
      return false;
    }
    final parts = name.split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      return false;
    }
    return true;
  }

  ToolPermissionDecision? _gitMutationAvailabilityDecision() {
    if (request.intent != TurnIntent.verify ||
        request.phase != ToolPermissionPhase.verify) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.gitMutationRequiresReview,
        message: 'Git mutation is only available from a reviewed Verify turn.',
      );
    }
    return null;
  }

  ToolPermissionDecision? _gitMutationArgumentDecision(ToolCallInfo toolCall) {
    if (toolCall.name != 'git_commit') return null;
    final files = toolCall.arguments['files'];
    if (files == null) return null;
    if (files is! List) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.pathOutsideWorkspace,
        message: 'Git commit file list must contain plain relative paths.',
      );
    }
    for (final entry in files) {
      if (entry is! String || entry.trim().isEmpty) {
        return const ToolPermissionDecision(
          verdict: ToolPermissionVerdict.deny,
          reason: ToolPermissionReason.pathOutsideWorkspace,
          message: 'Git commit file list contains an invalid path.',
        );
      }
      final pathspecDecision = _gitPathspecDecision(entry);
      if (pathspecDecision != null) return pathspecDecision;
      final pathDecision = _pathDecisionForRawPath(entry);
      if (pathDecision != null) return pathDecision;
    }
    return null;
  }

  ToolPermissionDecision? _gitPathspecDecision(String rawPath) {
    final path = rawPath.trim();
    if (path.startsWith('-') || path.startsWith(':(')) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.pathOutsideWorkspace,
        message:
            'Git commit file entries must be plain workspace-relative paths, not options or pathspec magic.',
      );
    }
    return null;
  }

  ToolPermissionDecision? _pathDecision(ToolCallInfo toolCall) {
    final rawPath = toolCall.arguments['path'] as String?;
    if (rawPath == null || rawPath.trim().isEmpty) return null;
    return _pathDecisionForRawPath(rawPath);
  }

  ToolPermissionDecision? _patchSetPathDecision(ToolCallInfo toolCall) {
    final files = toolCall.arguments['files'] as List<dynamic>? ?? const [];
    for (final entry in files.whereType<Map<String, dynamic>>()) {
      final rawPath = entry['path'] as String? ?? '';
      if (rawPath.trim().isEmpty) {
        return const ToolPermissionDecision(
          verdict: ToolPermissionVerdict.deny,
          reason: ToolPermissionReason.pathOutsideWorkspace,
          message: 'Patch file path is missing.',
        );
      }
      final pathDecision = _pathDecisionForRawPath(rawPath);
      if (pathDecision != null) return pathDecision;
    }
    return null;
  }

  ToolPermissionDecision? _pathDecisionForRawPath(String rawPath) {
    final sanitizedPath = _sanitizePathInput(rawPath);
    if (_looksSecret(sanitizedPath)) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.secretPath,
        message: 'Secret or environment files are not available to the agent.',
      );
    }
    if (_looksLikeWindowsAbsolutePath(sanitizedPath)) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.pathOutsideWorkspace,
        message: 'Tool path is outside the active workspace.',
      );
    }
    final resolved = p.normalize(
      p.isAbsolute(sanitizedPath)
          ? sanitizedPath
          : p.join(workingDir, sanitizedPath),
    );
    if (resolved != workingDir && !p.isWithin(workingDir, resolved)) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.pathOutsideWorkspace,
        message: 'Tool path is outside the active workspace.',
      );
    }
    return null;
  }

  String _sanitizePathInput(String rawPath) =>
      rawPath.trim().replaceAll('\\', '/');

  bool _looksLikeWindowsAbsolutePath(String sanitizedPath) {
    return RegExp(r'^[A-Za-z]:/').hasMatch(sanitizedPath) ||
        sanitizedPath.startsWith('//');
  }

  bool _looksSecret(String rawPath) {
    return CommandSanitizer.looksSensitivePath(rawPath);
  }

  McpToolRisk _mcpRiskFromToolName(String toolName) {
    final normalized = toolName.toLowerCase();
    if (RegExp(
      r'(^|_)(get|list|read|search|find|fetch|query|lookup|status|describe|view|show)(_|$)',
    ).hasMatch(normalized)) {
      return McpToolRisk.readOnly;
    }
    if (RegExp(
      r'(^|_)(create|update|delete|remove|close|open|write|edit|set|send|post|put|patch|merge|assign|comment|reply|resolve|deploy)(_|$)',
    ).hasMatch(normalized)) {
      return McpToolRisk.mutation;
    }
    return McpToolRisk.unknown;
  }

  bool _mcpLooksNetworkBacked(String toolName, ToolCallInfo toolCall) {
    final normalized = toolName.toLowerCase();
    if (RegExp(
      r'(^|_)(browser|web|url|uri|http|https|fetch_url|fetch_page|open_url|navigate|crawl|scrape|download)(_|$)',
    ).hasMatch(normalized)) {
      return true;
    }
    return toolCall.arguments.entries.any(
      (entry) => _containsNetworkTarget(entry.value, key: entry.key),
    );
  }

  bool _containsNetworkTarget(Object? value, {String? key}) {
    if (value is String) {
      return _networkDomainFromText(
            value,
            allowBareAmbiguousIpv4: _isNetworkKey(key),
          ) !=
          null;
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

  NetworkAccessKind _networkAccessKind(ToolCallInfo toolCall) {
    final domain = _networkDomain(toolCall);
    return _networkAccessKindFromDomain(domain);
  }

  String? _networkDomain(ToolCallInfo toolCall) {
    for (final key in const ['url', 'uri', 'endpoint', 'domain', 'host']) {
      final value = toolCall.arguments[key];
      if (value is String) {
        final domain = _networkDomainFromText(
          value,
          allowBareAmbiguousIpv4: true,
        );
        if (domain != null) return domain;
      }
    }
    for (final value in toolCall.arguments.values) {
      if (value is String) {
        final domain = _networkDomainFromText(value);
        if (domain != null) return domain;
      }
    }
    return null;
  }

  NetworkAccessKind _networkAccessKindFromText(String text) {
    return _networkAccessKindFromDomain(_networkDomainFromText(text));
  }

  String? _networkDomainFromText(
    String text, {
    bool allowBareAmbiguousIpv4 = false,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final uriMatch = RegExp(
      r"""\b(?:https?|wss?|ftp)://[^\s'"<>]+""",
      caseSensitive: false,
    ).firstMatch(trimmed);
    final candidate = uriMatch?.group(0) ?? trimmed;
    final uri = Uri.tryParse(candidate);
    final host = uri?.host;
    if (host != null && host.isNotEmpty) return _normalizeNetworkHost(host);
    final bracketedIpv6 = RegExp(
      r'\[([0-9a-f:.%]+)\]',
      caseSensitive: false,
    ).firstMatch(trimmed)?.group(1);
    if (bracketedIpv6 != null && _isIpv6Literal(bracketedIpv6)) {
      return _normalizeNetworkHost(bracketedIpv6);
    }
    if (_isIpv6Literal(trimmed)) return _normalizeNetworkHost(trimmed);
    if (allowBareAmbiguousIpv4 && _looksLikeAmbiguousIpv4Alias(trimmed)) {
      return _normalizeNetworkHost(trimmed);
    }
    final bareHost = RegExp(
      r'\b((?:localhost)|(?:\d{1,3}(?:\.\d{1,3}){3})|(?:[a-z0-9-]+\.)+[a-z]{2,})\b',
      caseSensitive: false,
    ).firstMatch(trimmed)?.group(1);
    return bareHost == null ? null : _normalizeNetworkHost(bareHost);
  }

  NetworkAccessKind _networkAccessKindFromDomain(String? domain) {
    if (domain == null || domain.trim().isEmpty) {
      return NetworkAccessKind.publicInternet;
    }
    final normalized = _normalizeNetworkHost(domain);
    if (normalized == 'localhost' ||
        normalized == '::1' ||
        normalized.startsWith('127.')) {
      return NetworkAccessKind.localhost;
    }
    if (_looksLikeAmbiguousIpv4Alias(normalized) ||
        _isPrivateIpv4(normalized) ||
        _isBlockedIpv6(normalized) ||
        normalized.endsWith('.local') ||
        normalized.endsWith('.internal') ||
        normalized.endsWith('.lan')) {
      return NetworkAccessKind.privateNetwork;
    }
    return NetworkAccessKind.publicInternet;
  }

  String _normalizeNetworkHost(String host) {
    var normalized = host.trim().toLowerCase();
    if (normalized.startsWith('[') && normalized.endsWith(']')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
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

  bool _isIpv6Literal(String host) {
    final normalized = _normalizeNetworkHost(host);
    return normalized.contains(':') &&
        RegExp(r'^[0-9a-f:.%]+$', caseSensitive: false).hasMatch(normalized);
  }

  bool _isBlockedIpv6(String host) {
    if (!_isIpv6Literal(host)) return false;
    final normalized = _normalizeNetworkHost(host);
    if (normalized == '::' || normalized == '0:0:0:0:0:0:0:0') return true;
    if (normalized == '::1' || normalized == '0:0:0:0:0:0:0:1') return true;
    if (normalized.startsWith('fe80:')) return true;
    if (normalized.startsWith('fc') || normalized.startsWith('fd')) return true;
    if (normalized.startsWith('ff')) return true;
    if (normalized.startsWith('::ffff:')) {
      return _isPrivateIpv4(normalized.substring('::ffff:'.length));
    }
    return false;
  }

  bool _looksLikeAmbiguousIpv4Alias(String host) {
    final normalized = _normalizeNetworkHost(host);
    if (_isIpv6Literal(normalized)) return false;
    if (RegExp(r'^0x[0-9a-f]+$', caseSensitive: false).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(r'^0[0-7]+$').hasMatch(normalized) && normalized.length > 1) {
      return true;
    }
    if (RegExp(r'^\d+$').hasMatch(normalized)) return true;
    final labels = normalized.split('.');
    if (labels.length <= 1) return false;
    final allNumericOrHex = labels.every((label) {
      if (label.isEmpty) return false;
      return RegExp(r'^\d+$').hasMatch(label) ||
          RegExp(r'^0x[0-9a-f]+$', caseSensitive: false).hasMatch(label);
    });
    if (!allNumericOrHex) return false;
    if (labels.length != 4) return true;
    return labels.any((label) {
      if (RegExp(r'^0x[0-9a-f]+$', caseSensitive: false).hasMatch(label)) {
        return true;
      }
      return label.length > 1 && label.startsWith('0');
    });
  }

  bool _isPrivateIpv4(String host) {
    final match = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    ).firstMatch(host);
    if (match == null) return false;
    final octets = [
      for (var i = 1; i <= 4; i++) int.tryParse(match.group(i) ?? ''),
    ];
    if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
      return false;
    }
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        (first == 169 && second == 254);
  }

  String _networkDescription(NetworkAccessKind kind, String? domain) {
    final label = switch (kind) {
      NetworkAccessKind.none => 'unknown network target',
      NetworkAccessKind.localhost => 'localhost',
      NetworkAccessKind.privateNetwork => 'private network',
      NetworkAccessKind.publicInternet => 'public internet',
    };
    final cleanedDomain = domain?.trim();
    if (cleanedDomain == null || cleanedDomain.isEmpty) return label;
    return '$label: $cleanedDomain';
  }

  ToolPermissionDecision? _blockedNetworkDecision(
    NetworkAccessKind kind,
    String? domain,
  ) {
    if (kind != NetworkAccessKind.localhost &&
        kind != NetworkAccessKind.privateNetwork) {
      return null;
    }
    return ToolPermissionDecision(
      verdict: ToolPermissionVerdict.deny,
      reason: ToolPermissionReason.networkRequiresReview,
      message:
          'Network target is blocked (${_networkDescription(kind, domain)}). Studio can only request review for public internet access.',
    );
  }

  ToolPermissionDecision? _grantDecision(
    ToolCallInfo toolCall,
    String message,
    String grantKey,
  ) {
    if (request.approvalGrant == ApprovalGrant.none) return null;
    final activeGrantKey = request.approvalGrantKey;
    if (activeGrantKey == null) return null;
    if (request.approvalGrant == ApprovalGrant.once) {
      if (activeGrantKey != _onceGrantKey(toolCall)) return null;
    } else if (request.approvalGrant == ApprovalGrant.turn) {
      if (activeGrantKey != grantKey) return null;
    }
    return ToolPermissionDecision(
      verdict: ToolPermissionVerdict.allow,
      reason: ToolPermissionReason.approvalGranted,
      message: message,
    );
  }

  String onceApprovalGrantKeyFor(ToolCallInfo toolCall) =>
      _onceGrantKey(toolCall);

  String _onceGrantKey(ToolCallInfo toolCall) => 'once:${toolCall.id}';

  String _approvalGrantKey(ToolCallInfo toolCall) {
    final name = toolCall.name;
    if (name == 'run_command') {
      final command = toolCall.arguments['command'] as String? ?? '';
      final category = _commandCategory(command);
      if (category == CommandCategory.network) {
        final domain = _networkDomainFromText(command);
        final accessKind = _networkAccessKindFromDomain(domain);
        return _commandGrantKey(
          category,
          accessKind: accessKind,
          domain: domain,
          command: command,
        );
      }
      return _commandGrantKey(category, command: command);
    }
    if (_networkTools.contains(name)) {
      final domain = _networkDomain(toolCall);
      return _networkGrantKey(
        name,
        _networkAccessKindFromDomain(domain),
        domain,
        toolCall: toolCall,
      );
    }
    if (name == 'git_branch') {
      final action = (toolCall.arguments['action'] as String? ?? 'list')
          .toLowerCase();
      return _gitBranchGrantKey(action);
    }
    if (_gitMutationTools.contains(name)) return _toolGrantKey(name);
    if (name.startsWith('mcp_')) {
      final mcpName = request.mcpToolName ?? name;
      final mcpRisk = request.mcpToolRisk == McpToolRisk.unknown
          ? _mcpRiskFromToolName(mcpName)
          : request.mcpToolRisk;
      return _mcpGrantKey(mcpName, mcpRisk);
    }
    return _toolGrantKey(name);
  }

  String _toolGrantKey(String toolName) => 'tool:${toolName.toLowerCase()}';

  String _gitBranchGrantKey(String action) =>
      'git_branch:${action.toLowerCase()}';

  String _commandGrantKey(
    CommandCategory category, {
    NetworkAccessKind accessKind = NetworkAccessKind.none,
    String? domain,
    String? command,
  }) {
    final normalizedDomain = domain?.trim().toLowerCase();
    final fingerprint = _shouldFingerprintCommand(category)
        ? _commandFingerprint(command)
        : null;
    if (category == CommandCategory.network) {
      return [
        'command',
        category.name,
        accessKind.name,
        if (normalizedDomain != null && normalizedDomain.isNotEmpty)
          normalizedDomain,
        ?fingerprint,
      ].join(':');
    }
    return ['command', category.name, ?fingerprint].join(':');
  }

  String _networkGrantKey(
    String toolName,
    NetworkAccessKind accessKind,
    String? domain, {
    ToolCallInfo? toolCall,
  }) {
    final normalizedDomain = domain?.trim().toLowerCase();
    final fingerprint = normalizedDomain == null || normalizedDomain.isEmpty
        ? _toolArgumentsFingerprint(toolCall)
        : null;
    return [
      'network',
      toolName.toLowerCase(),
      accessKind.name,
      if (normalizedDomain != null && normalizedDomain.isNotEmpty)
        normalizedDomain,
      ?fingerprint,
    ].join(':');
  }

  String _mcpGrantKey(String toolName, McpToolRisk risk) =>
      'mcp:${risk.name}:${toolName.toLowerCase()}';

  String? _toolArgumentsFingerprint(ToolCallInfo? toolCall) {
    if (toolCall == null) return null;
    return _commandFingerprint(_stableJson(toolCall.arguments));
  }

  String _stableJson(Object? value) {
    if (value is Map) {
      final normalized = <String, Object?>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        normalized[key] = _stableJsonValue(value[key]);
      }
      return jsonEncode(normalized);
    }
    return jsonEncode(_stableJsonValue(value));
  }

  Object? _stableJsonValue(Object? value) {
    if (value is Map) {
      final normalized = <String, Object?>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        normalized[key] = _stableJsonValue(value[key]);
      }
      return normalized;
    }
    if (value is Iterable) {
      return value.map(_stableJsonValue).toList();
    }
    if (value is num || value is bool || value is String || value == null) {
      return value;
    }
    return value.toString();
  }

  String? _commandFingerprint(String? command) {
    final normalized = command
        ?.trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    var hash = 0xcbf29ce484222325;
    for (final unit in normalized.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  bool _shouldFingerprintCommand(CommandCategory category) {
    return switch (category) {
      CommandCategory.unknown ||
      CommandCategory.git ||
      CommandCategory.install ||
      CommandCategory.network ||
      CommandCategory.readOnly ||
      CommandCategory.test ||
      CommandCategory.build ||
      CommandCategory.devServer => true,
      CommandCategory.compound ||
      CommandCategory.secretAccess ||
      CommandCategory.privileged ||
      CommandCategory.destructive => false,
    };
  }

  bool _hasUnquotedShellControlOperator(String command) {
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var escaped = false;
    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '\\') {
        escaped = true;
        continue;
      }
      if (char == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
        continue;
      }
      if (char == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
        continue;
      }
      if (inSingleQuote || inDoubleQuote) continue;
      if (char == '\n' || char == ';' || char == '|') return true;
      if (char == '&' && i + 1 < command.length && command[i + 1] == '&') {
        return true;
      }
    }
    return false;
  }
}

const _readOnlyTools = {
  'read_file',
  'list_files',
  'search_files',
  'git_status',
  'git_diff',
  'git_log',
};

const _gitMutationTools = {'git_commit', ..._githubMutationTools};

const _githubMutationTools = {
  'github_create_repo',
  'github_create_issue',
  'github_close_issue',
};

const _networkTools = {
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
