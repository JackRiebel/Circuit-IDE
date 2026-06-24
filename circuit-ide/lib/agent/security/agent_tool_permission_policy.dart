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
    if (name.startsWith('mcp_')) {
      final mcpRisk = request.mcpToolRisk == McpToolRisk.unknown
          ? _mcpRiskFromToolName(request.mcpToolName ?? name)
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
        verdict: ToolPermissionVerdict.ask,
        reason: ToolPermissionReason.mcpRequiresReview,
        message:
            'MCP tool requires review because its side effects are unknown.',
      );
    }

    if (_networkTools.contains(name)) {
      final accessKind = request.networkAccessKind == NetworkAccessKind.none
          ? _networkAccessKind(toolCall)
          : request.networkAccessKind;
      final domain = request.networkDomain ?? _networkDomain(toolCall);
      final granted = _grantDecision(
        'Network tool approved for this turn (${_networkDescription(accessKind, domain)}).',
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
      final gitAvailability = _gitMutationAvailabilityDecision();
      if (gitAvailability != null) return gitAvailability;
      final granted = _grantDecision('Git mutation approved for this turn.');
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
    final granted = _grantDecision('File write approved for this turn.');
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
    if (category == CommandCategory.network) {
      final accessKind = request.networkAccessKind == NetworkAccessKind.none
          ? _networkAccessKindFromText(command)
          : request.networkAccessKind;
      final domain = request.networkDomain ?? _networkDomainFromText(command);
      final granted = _grantDecision(
        'Network shell command approved for this turn (${_networkDescription(accessKind, domain)}).',
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
        'Dependency installation approved for this turn.',
      );
      if (granted != null) return granted;
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.ask,
        reason: ToolPermissionReason.commandRequiresReview,
        message:
            'Dependency installation can modify the workspace and requires review.',
      );
    }
    final granted = _grantDecision('Shell command approved for this turn.');
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
      r'(^|\s)(cat|less|more|head|tail|grep|rg|sed|awk|perl)\s+[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.aws/|aws/credentials)',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(r'(^|\s)(env|printenv|set)\s*($|[|;&>])').hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(
      r'(<|>|>>|\bsource\b|\.)\s*[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.aws/|aws/credentials)',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(
      r'(^|\s)(python|python3|node|ruby|php|perl)\b[^\n]*(open|readfilesync|file_get_contents|read_text|readbytes|read\s*\()[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.aws/|aws/credentials)',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(
      r'(^|\s)(cp|rsync|tar|zip|7z|gzip|gpg|base64)\b[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.aws/|aws/credentials)',
    ).hasMatch(normalized)) {
      return CommandCategory.secretAccess;
    }
    if (RegExp(
      r'(^|\s)(curl|wget|scp|ssh|ftp|sftp|nc|ncat|telnet|openssl\s+s_client)\b',
    ).hasMatch(normalized)) {
      return CommandCategory.network;
    }
    if (RegExp(
      r'(^|\s)(npm|pnpm|yarn|bun|pip|pip3|poetry|uv|gem|bundle|cargo|go)\s+(install|add|get|update|upgrade)\b|(^|\s)(brew|apt|apt-get|dnf|yum|apk)\s+install\b',
    ).hasMatch(normalized)) {
      return CommandCategory.install;
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
    final gitAvailability = _gitMutationAvailabilityDecision();
    if (gitAvailability != null) return gitAvailability;
    final granted = _grantDecision('Branch mutation approved for this turn.');
    if (granted != null) return granted;
    return const ToolPermissionDecision(
      verdict: ToolPermissionVerdict.ask,
      reason: ToolPermissionReason.gitMutationRequiresReview,
      message: 'Branch mutation requires review.',
    );
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
    final normalized = rawPath.toLowerCase();
    return normalized == '.env' ||
        normalized.startsWith('.env.') ||
        normalized.contains('/.env') ||
        normalized.contains('secret') ||
        normalized.contains('credentials') ||
        normalized == '.npmrc' ||
        normalized.endsWith('/.npmrc') ||
        normalized == '.netrc' ||
        normalized.endsWith('/.netrc') ||
        normalized == 'id_rsa' ||
        normalized.endsWith('/id_rsa') ||
        normalized == 'id_ed25519' ||
        normalized.endsWith('/id_ed25519') ||
        normalized == '.aws' ||
        normalized.startsWith('.aws/') ||
        normalized.contains('/.aws/');
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

  NetworkAccessKind _networkAccessKind(ToolCallInfo toolCall) {
    final domain = _networkDomain(toolCall);
    return _networkAccessKindFromDomain(domain);
  }

  String? _networkDomain(ToolCallInfo toolCall) {
    for (final key in const ['url', 'uri', 'endpoint', 'domain', 'host']) {
      final value = toolCall.arguments[key];
      if (value is String) {
        final domain = _networkDomainFromText(value);
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

  String? _networkDomainFromText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final uriMatch = RegExp(
      r"""\b(?:https?|wss?|ftp)://[^\s'"<>]+""",
      caseSensitive: false,
    ).firstMatch(trimmed);
    final candidate = uriMatch?.group(0) ?? trimmed;
    final uri = Uri.tryParse(candidate);
    final host = uri?.host;
    if (host != null && host.isNotEmpty) return host.toLowerCase();
    final bareHost = RegExp(
      r'\b((?:localhost)|(?:\d{1,3}(?:\.\d{1,3}){3})|(?:[a-z0-9-]+\.)+[a-z]{2,})\b',
      caseSensitive: false,
    ).firstMatch(trimmed)?.group(1);
    return bareHost?.toLowerCase();
  }

  NetworkAccessKind _networkAccessKindFromDomain(String? domain) {
    if (domain == null || domain.trim().isEmpty) {
      return NetworkAccessKind.publicInternet;
    }
    final normalized = domain.toLowerCase();
    if (normalized == 'localhost' ||
        normalized == '::1' ||
        normalized.startsWith('127.')) {
      return NetworkAccessKind.localhost;
    }
    if (_isPrivateIpv4(normalized) ||
        normalized.endsWith('.local') ||
        normalized.endsWith('.internal') ||
        normalized.endsWith('.lan')) {
      return NetworkAccessKind.privateNetwork;
    }
    return NetworkAccessKind.publicInternet;
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

  ToolPermissionDecision? _grantDecision(String message) {
    if (request.approvalGrant == ApprovalGrant.none) return null;
    return ToolPermissionDecision(
      verdict: ToolPermissionVerdict.allow,
      reason: ToolPermissionReason.approvalGranted,
      message: message,
    );
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

const _gitMutationTools = {
  'git_commit',
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
