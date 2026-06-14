import 'package:path/path.dart' as p;

import '../../models/agent_tool_permission.dart';
import '../../models/tool_call_info.dart';
import 'command_sanitizer.dart';

class AgentToolPermissionPolicy {
  final String workingDir;

  const AgentToolPermissionPolicy({required this.workingDir});

  ToolPermissionDecision evaluate(ToolCallInfo toolCall) {
    final name = toolCall.name;
    if (name.startsWith('mcp_')) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.ask,
        reason: ToolPermissionReason.mcpRequiresReview,
        message:
            'MCP tool requires review because its side effects are unknown.',
      );
    }

    if (_readOnlyTools.contains(name)) {
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
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.allow,
        reason: ToolPermissionReason.readOnlyInsideWorkspace,
        message: 'Patch proposal does not modify files.',
      );
    }
    if (_writeTools.contains(name)) return _writeDecision(toolCall);
    if (name == 'run_command') return _commandDecision(toolCall);
    if (_gitMutationTools.contains(name)) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.ask,
        reason: ToolPermissionReason.gitMutationRequiresReview,
        message: 'Git mutation requires review.',
      );
    }
    if (_networkTools.contains(name)) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.ask,
        reason: ToolPermissionReason.networkRequiresReview,
        message: 'Network access requires review.',
      );
    }

    return const ToolPermissionDecision(
      verdict: ToolPermissionVerdict.ask,
      reason: ToolPermissionReason.unknownTool,
      message: 'Unknown tool requires review.',
    );
  }

  ToolPermissionDecision _writeDecision(ToolCallInfo toolCall) {
    final pathDecision = _pathDecision(toolCall);
    if (pathDecision != null) return pathDecision;
    return const ToolPermissionDecision(
      verdict: ToolPermissionVerdict.ask,
      reason: ToolPermissionReason.writeRequiresReview,
      message: 'File write requires review.',
    );
  }

  ToolPermissionDecision _commandDecision(ToolCallInfo toolCall) {
    final command = toolCall.arguments['command'] as String? ?? '';
    final danger = CommandSanitizer.checkDangerous(command);
    if (danger != null) {
      return ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.dangerousCommand,
        message: 'Command blocked: $danger',
      );
    }
    return const ToolPermissionDecision(
      verdict: ToolPermissionVerdict.ask,
      reason: ToolPermissionReason.commandRequiresReview,
      message: 'Shell command requires review.',
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
    return const ToolPermissionDecision(
      verdict: ToolPermissionVerdict.ask,
      reason: ToolPermissionReason.gitMutationRequiresReview,
      message: 'Branch mutation requires review.',
    );
  }

  ToolPermissionDecision? _pathDecision(ToolCallInfo toolCall) {
    final rawPath = toolCall.arguments['path'] as String?;
    if (rawPath == null || rawPath.trim().isEmpty) return null;
    if (_looksSecret(rawPath)) {
      return const ToolPermissionDecision(
        verdict: ToolPermissionVerdict.deny,
        reason: ToolPermissionReason.secretPath,
        message: 'Secret or environment files are not available to the agent.',
      );
    }
    final resolved = p.normalize(
      p.isAbsolute(rawPath) ? rawPath : p.join(workingDir, rawPath),
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

  bool _looksSecret(String rawPath) {
    final normalized = rawPath.toLowerCase();
    return normalized == '.env' ||
        normalized.startsWith('.env.') ||
        normalized.contains('/.env') ||
        normalized.contains('secret') ||
        normalized.contains('credentials');
  }
}

const _readOnlyTools = {
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

const _writeTools = {'write_file', 'edit_file', 'apply_patch_set'};

const _gitMutationTools = {
  'git_commit',
  'github_create_repo',
  'github_create_issue',
  'github_close_issue',
};

const _networkTools = {'web_fetch', 'web_search'};
