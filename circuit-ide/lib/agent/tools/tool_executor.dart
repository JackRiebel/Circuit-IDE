import 'dart:async';

import '../../core/utils/logger.dart';
import '../../models/tool_call_info.dart';
import '../../models/checkpoint.dart';
import '../../models/command_run.dart';
import '../../models/confirmation_request.dart';
import '../../enums/tool_status.dart';
import '../checkpoint/checkpoint_manager.dart';
import '../security/secret_detector.dart';
import '../security/agent_tool_permission_policy.dart';
import '../security/command_sanitizer.dart';
import '../mcp/mcp_client.dart';
import 'tool_registry.dart';
import 'file_tools.dart';
import 'git_tools.dart';
import 'command_tools.dart';
import 'web_tools.dart';
import 'github_tools.dart';
import 'orchestrate_tool.dart';

typedef ConfirmationCallback = Future<bool> Function(ConfirmationRequest);

class ToolExecutionResult {
  final String toolCallId;
  final String result;
  final bool success;
  final bool wasCancelled;

  const ToolExecutionResult({
    required this.toolCallId,
    required this.result,
    this.success = true,
    this.wasCancelled = false,
  });
}

class ToolExecutor {
  final String workingDir;
  final ConfirmationCallback? onConfirmationNeeded;
  final void Function(ToolCallInfo)? onToolCallUpdate;
  bool autoApprove;

  late final FileTools _fileTools;
  late final GitTools _gitTools;
  late final CommandTools _commandTools;
  late final WebTools _webTools;
  late final GitHubTools _githubTools;
  late final AgentToolPermissionPolicy _permissionPolicy;
  final _secretDetector = SecretDetector();
  McpClient? _mcpClient;
  OrchestrateToolExecutor? _orchestrateTool;

  /// Checkpoint manager for snapshotting files before writes/edits.
  late final CheckpointManager checkpointManager;

  /// Snapshots collected during the current agent turn.
  final List<FileSnapshot> _turnSnapshots = [];

  ToolExecutor({
    required this.workingDir,
    this.onConfirmationNeeded,
    this.onToolCallUpdate,
    this.autoApprove = false,
  }) {
    _fileTools = FileTools(workingDir: workingDir);
    _gitTools = GitTools(workingDir: workingDir);
    _commandTools = CommandTools(workingDir: workingDir);
    _webTools = WebTools();
    _githubTools = GitHubTools();
    _permissionPolicy = AgentToolPermissionPolicy(workingDir: workingDir);
    checkpointManager = CheckpointManager(workingDir: workingDir);
  }

  /// Called at the start of each agent turn to reset checkpoint tracking.
  void beginTurn() {
    _turnSnapshots.clear();
    checkpointManager.beginTurn();
  }

  /// Called at the end of each agent turn to finalize checkpoints.
  Checkpoint? commitTurn(String description) {
    if (_turnSnapshots.isEmpty) return null;
    final cp = checkpointManager.commitTurn(
      List.of(_turnSnapshots),
      description,
    );
    _turnSnapshots.clear();
    return cp;
  }

  /// Configure GitHub token for GitHub tools
  void configureGithub(String token) {
    _githubTools.configure(token: token);
  }

  /// Set the MCP client for proxying MCP tool calls
  void setMcpClient(McpClient? client) {
    _mcpClient = client;
  }

  /// Set the orchestration tool executor for subagent spawning
  void setOrchestrateTool(OrchestrateToolExecutor? tool) {
    _orchestrateTool = tool;
  }

  /// Execute tool calls, running read-only tools in parallel
  Future<List<ToolExecutionResult>> executeToolCalls(
    List<ToolCallInfo> toolCalls,
  ) async {
    // Separate policy-allowed read-only calls (parallel) from calls that need
    // ordering, review, or denial handling.
    final readOnly = <ToolCallInfo>[];
    final writeOps = <ToolCallInfo>[];

    for (final tc in toolCalls) {
      final decision = _permissionPolicy.evaluate(tc);
      if (decision.allowed && decision.isReadOnly) {
        readOnly.add(tc);
      } else {
        writeOps.add(tc);
      }
    }

    final results = <ToolExecutionResult>[];

    // Run read-only tools in parallel
    if (readOnly.isNotEmpty) {
      final futures = readOnly.map((tc) => _executeSingle(tc));
      results.addAll(await Future.wait(futures));
    }

    // Run write tools sequentially
    for (final tc in writeOps) {
      results.add(await _executeSingle(tc));
    }

    return results;
  }

  Future<ToolExecutionResult> _executeSingle(ToolCallInfo toolCall) async {
    final updated = toolCall.copyWith(
      status: ToolStatus.running,
      startedAt: DateTime.now(),
    );
    onToolCallUpdate?.call(updated);

    try {
      // Check policy before relying on model intent. Prompts guide behavior,
      // but this client-side policy is the enforcement layer.
      final permission = _permissionPolicy.evaluate(toolCall);
      if (permission.denied) {
        onToolCallUpdate?.call(
          updated.copyWith(
            status: ToolStatus.error,
            completedAt: DateTime.now(),
            error: permission.message,
          ),
        );
        return ToolExecutionResult(
          toolCallId: toolCall.id,
          result: 'Action blocked: ${permission.message}',
          success: false,
        );
      }

      if (permission.requiresApproval && !autoApprove) {
        final preview = _generatePreview(toolCall);
        final warnings = [permission.message, ..._checkWarnings(toolCall)];

        if (onConfirmationNeeded != null) {
          final request = ConfirmationRequest(
            id: toolCall.id,
            toolCall: toolCall,
            preview: preview,
            warnings: warnings,
          );

          final approved = await onConfirmationNeeded!(request);
          if (!approved) {
            onToolCallUpdate?.call(
              updated.copyWith(
                status: ToolStatus.cancelled,
                completedAt: DateTime.now(),
              ),
            );
            return ToolExecutionResult(
              toolCallId: toolCall.id,
              result: 'Action cancelled by user.',
              wasCancelled: true,
            );
          }
        }
      }

      // Auto-snapshot files before write/edit for checkpoint rewind
      if (toolCall.name == 'write_file' || toolCall.name == 'edit_file') {
        final path = toolCall.arguments['path'] as String?;
        if (path != null) {
          final snapshot = await checkpointManager.snapshotFile(path);
          if (snapshot != null) _turnSnapshots.add(snapshot);
        }
      }

      final result = toolCall.name == 'run_command'
          ? await _executeCommandTool(toolCall, updated)
          : await _dispatch(toolCall.name, toolCall.arguments);

      onToolCallUpdate?.call(
        updated.copyWith(
          status: ToolStatus.success,
          result: result,
          completedAt: DateTime.now(),
        ),
      );

      return ToolExecutionResult(toolCallId: toolCall.id, result: result);
    } catch (e) {
      Logger.error('Tool execution error: ${toolCall.name}', e);
      onToolCallUpdate?.call(
        updated.copyWith(
          status: ToolStatus.error,
          error: e.toString(),
          completedAt: DateTime.now(),
        ),
      );

      return ToolExecutionResult(
        toolCallId: toolCall.id,
        result: 'Error: $e',
        success: false,
      );
    }
  }

  Future<String> _executeCommandTool(
    ToolCallInfo toolCall,
    ToolCallInfo running,
  ) {
    final output = StringBuffer();
    return _commandTools.runCommand(
      toolCall.arguments,
      runId: toolCall.id,
      onEvent: (event) {
        if (event.type == CommandRunEventType.stdout ||
            event.type == CommandRunEventType.stderr) {
          output.write(event.text);
        }
        onToolCallUpdate?.call(
          running.copyWith(
            result: output.toString().trim(),
            error: event.type == CommandRunEventType.stderr
                ? event.text.trim()
                : null,
          ),
        );
      },
    );
  }

  int cancelActiveCommands() => _commandTools.cancelAll();

  Future<String> _dispatch(String name, Map<String, dynamic> args) async {
    switch (name) {
      // File tools
      case 'read_file':
        return _fileTools.readFile(args);
      case 'write_file':
        return _fileTools.writeFile(args);
      case 'edit_file':
        return _fileTools.editFile(args);
      case 'list_files':
        return _fileTools.listFiles(args);
      case 'search_files':
        return _fileTools.searchFiles(args);

      // Patch proposal tool
      case 'propose_patch':
        return _proposePatch(args);

      // Git tools
      case 'git_status':
        return _gitTools.gitStatus(args);
      case 'git_diff':
        return _gitTools.gitDiff(args);
      case 'git_log':
        return _gitTools.gitLog(args);
      case 'git_commit':
        return _gitTools.gitCommit(args);
      case 'git_branch':
        return _gitTools.gitBranch(args);

      // Command tools
      case 'run_command':
        return _commandTools.runCommand(args);

      // Web tools
      case 'web_fetch':
      case 'web_search':
        return _webTools.execute(name, args);

      // GitHub tools
      case 'github_whoami':
      case 'github_list_repos':
      case 'github_get_repo':
      case 'github_list_issues':
      case 'github_get_issue':
      case 'github_create_issue':
      case 'github_close_issue':
      case 'github_list_prs':
      case 'github_get_pr':
      case 'github_search_repos':
      case 'github_search_issues':
      case 'github_create_repo':
        return _githubTools.execute(name, args);

      // Orchestration tool
      case 'orchestrate':
        if (_orchestrateTool == null) {
          return 'Error: Orchestration not available';
        }
        return _orchestrateTool!.execute(args);

      default:
        // MCP tool dispatch
        if (ToolRegistry.isMcpTool(name) && _mcpClient != null) {
          final parsed = _mcpClient!.parseMcpToolName(name);
          if (parsed != null) {
            return _mcpClient!.callTool(parsed.$2, args);
          }
          return 'Error: Could not parse MCP tool name: $name';
        }
        return 'Unknown tool: $name';
    }
  }

  String _generatePreview(ToolCallInfo toolCall) {
    final args = toolCall.arguments;
    switch (toolCall.name) {
      case 'write_file':
        final path = args['path'] ?? 'unknown';
        final content = args['content'] as String? ?? '';
        final lines = content.split('\n').length;
        return 'Write $lines lines to $path';
      case 'edit_file':
        final path = args['path'] ?? 'unknown';
        return 'Edit file: $path';
      case 'propose_patch':
        final title = args['title'] ?? 'Patch proposal';
        return 'Propose patch: $title';
      case 'run_command':
        return 'Execute: ${args['command'] ?? ''}';
      case 'git_commit':
        return 'Commit: ${args['message'] ?? ''}';
      case 'github_create_issue':
        return 'Create issue: ${args['title'] ?? ''} in ${args['owner'] ?? ''}/${args['repo'] ?? ''}';
      case 'github_close_issue':
        return 'Close issue #${args['number'] ?? '?'} in ${args['owner'] ?? ''}/${args['repo'] ?? ''}';
      case 'github_create_repo':
        return 'Create repository: ${args['name'] ?? ''}${args['private'] == true ? ' (private)' : ''}';
      default:
        return '${toolCall.name}: ${args.toString().substring(0, 100.clamp(0, args.toString().length))}';
    }
  }

  String _proposePatch(Map<String, dynamic> args) {
    final title = args['title'] as String? ?? 'Patch proposal';
    final summary = args['summary'] as String? ?? '';
    final files = args['files'] as List<dynamic>? ?? const [];
    final fileLines = files
        .whereType<Map<String, dynamic>>()
        .map(
          (file) => '- ${file['path'] ?? 'unknown'}: ${file['intent'] ?? ''}',
        )
        .join('\n');
    return [
      'Patch proposal: $title',
      if (summary.trim().isNotEmpty) summary.trim(),
      if (fileLines.trim().isNotEmpty) fileLines,
      'No files were changed. CircuitCode has captured this as a reviewable plan. Do not ask the user to type approve; wait for the app review controls or user feedback.',
    ].join('\n\n');
  }

  List<String> _checkWarnings(ToolCallInfo toolCall) {
    final warnings = <String>[];
    final args = toolCall.arguments;

    // Check for secrets in file content
    if (toolCall.name == 'write_file' || toolCall.name == 'edit_file') {
      final content =
          args['content'] as String? ?? args['new_text'] as String? ?? '';
      final secrets = _secretDetector.scan(content);
      for (final s in secrets) {
        warnings.add(
          '${s.severity.toUpperCase()}: Possible ${s.type} detected',
        );
      }
    }

    // Check for dangerous commands
    if (toolCall.name == 'run_command') {
      final command = args['command'] as String? ?? '';
      final danger = CommandSanitizer.checkDangerous(command);
      if (danger != null) {
        warnings.add('DANGEROUS: $danger');
      }
    }

    return warnings;
  }
}
