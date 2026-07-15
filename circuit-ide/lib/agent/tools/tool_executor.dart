import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../models/tool_call_info.dart';
import '../../models/tool_result_envelope.dart';
import '../../models/agent_tool_permission.dart';
import '../../models/agent_workspace.dart';
import '../../models/checkpoint.dart';
import '../../models/command_run.dart';
import '../../models/confirmation_request.dart';
import '../../models/turn_intent.dart';
import '../../enums/tool_status.dart';
import '../checkpoint/checkpoint_manager.dart';
import '../security/secret_detector.dart';
import '../security/agent_tool_permission_policy.dart';
import '../security/command_sanitizer.dart';
import '../verification_command_filter.dart' as verification_command_filter;
import '../mcp/mcp_client.dart';
import '../../models/subagent_delegation.dart';
import 'tool_registry.dart';
import 'file_tools.dart';
import 'git_tools.dart';
import 'command_tools.dart';
import 'web_tools.dart';
import 'github_tools.dart';

typedef ConfirmationCallback = Future<bool> Function(ConfirmationRequest);
typedef SubagentDelegationHandler =
    Future<SubagentDelegationResult> Function(
      SubagentDelegationRequest request,
    );

class ToolExecutionResult {
  final String toolCallId;
  final String toolName;
  final String result;
  final bool success;
  final bool wasCancelled;
  final ToolResultEnvelope? envelope;

  const ToolExecutionResult({
    required this.toolCallId,
    required this.toolName,
    required this.result,
    this.success = true,
    this.wasCancelled = false,
    this.envelope,
  });

  ToolResultEnvelope get structured =>
      envelope ??
      ToolResultEnvelope(
        toolCallId: toolCallId,
        toolName: toolName,
        status: wasCancelled
            ? ToolResultStatus.cancelled
            : success
            ? ToolResultStatus.success
            : ToolResultStatus.error,
        summary: result,
        retryable: !success && !wasCancelled,
      );
}

class ToolExecutor {
  final String workingDir;
  final WorkspacePermissionDisposition networkDisposition;
  final List<WorkspaceNetworkRule> networkRules;
  final ConfirmationCallback? onConfirmationNeeded;
  final void Function(ToolCallInfo)? onToolCallUpdate;
  final SubagentDelegationHandler? onSubagentDelegation;
  final void Function()? onCancelSubagents;
  bool autoApprove;

  late final FileTools _fileTools;
  late final GitTools _gitTools;
  late final CommandTools _commandTools;
  late final WebTools _webTools;
  late final GitHubTools _githubTools;
  ToolPermissionRequest _permissionRequest = const ToolPermissionRequest(
    intent: TurnIntent.ask,
    phase: ToolPermissionPhase.inspect,
  );
  final _secretDetector = SecretDetector();
  McpClient? _mcpClient;

  /// Checkpoint manager for snapshotting files before writes/edits.
  late final CheckpointManager checkpointManager;

  /// Snapshots collected during the current agent turn.
  final List<FileSnapshot> _turnSnapshots = [];

  ToolExecutor({
    required this.workingDir,
    this.networkDisposition = WorkspacePermissionDisposition.review,
    this.networkRules = const [],
    this.onConfirmationNeeded,
    this.onToolCallUpdate,
    this.onSubagentDelegation,
    this.onCancelSubagents,
    this.autoApprove = false,
  }) {
    _fileTools = FileTools(workingDir: workingDir);
    _gitTools = GitTools(workingDir: workingDir);
    _commandTools = CommandTools(workingDir: workingDir);
    _webTools = WebTools();
    _githubTools = GitHubTools();
    checkpointManager = CheckpointManager(workingDir: workingDir);
  }

  AgentToolPermissionPolicy get _permissionPolicy => AgentToolPermissionPolicy(
    workingDir: workingDir,
    request: _permissionRequest,
    networkDisposition: networkDisposition,
    networkRules: networkRules,
  );

  void setPermissionRequest(ToolPermissionRequest request) {
    _permissionRequest = request;
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
      var approvedByReview = false;
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
          toolName: toolCall.name,
          result: 'Action blocked: ${permission.message}',
          success: false,
          envelope: ToolResultEnvelope(
            toolCallId: toolCall.id,
            toolName: toolCall.name,
            status: ToolResultStatus.denied,
            summary: permission.message,
            diagnostic: permission.reason.name,
          ),
        );
      }

      if (permission.requiresApproval) {
        final preview = _generatePreview(toolCall);
        final warnings = [permission.message, ..._checkWarnings(toolCall)];

        if (onConfirmationNeeded == null) {
          onToolCallUpdate?.call(
            updated.copyWith(
              status: ToolStatus.error,
              completedAt: DateTime.now(),
              error: permission.message,
            ),
          );
          return ToolExecutionResult(
            toolCallId: toolCall.id,
            toolName: toolCall.name,
            result: 'Action blocked: ${permission.message}',
            success: false,
            envelope: ToolResultEnvelope(
              toolCallId: toolCall.id,
              toolName: toolCall.name,
              status: ToolResultStatus.waitingForApproval,
              summary:
                  'Action requires review, but no approval handler is attached.',
              diagnostic: permission.reason.name,
              retryable: true,
            ),
          );
        }

        final request = ConfirmationRequest(
          id: toolCall.id,
          toolCall: toolCall,
          preview: preview,
          warnings: warnings,
          risk: permission.reason,
          normalizedAction: _permissionPolicy.approvalGrantKeyFor(toolCall),
        );

        final approved = await onConfirmationNeeded!(request);
        if (!approved || request.isExpired) {
          final expired = request.isExpired;
          onToolCallUpdate?.call(
            updated.copyWith(
              status: ToolStatus.cancelled,
              completedAt: DateTime.now(),
            ),
          );
          return ToolExecutionResult(
            toolCallId: toolCall.id,
            toolName: toolCall.name,
            result: expired
                ? 'Approval expired before the action ran.'
                : 'Action rejected by user.',
            wasCancelled: true,
            envelope: ToolResultEnvelope(
              toolCallId: toolCall.id,
              toolName: toolCall.name,
              status: ToolResultStatus.cancelled,
              summary: expired
                  ? 'Approval expired before the action ran.'
                  : 'Action rejected by user.',
            ),
          );
        }
        approvedByReview = true;
      }

      // Auto-snapshot files before write/edit for checkpoint rewind
      if (toolCall.name == 'write_file' || toolCall.name == 'edit_file') {
        final path = toolCall.arguments['path'] as String?;
        if (path != null) {
          final snapshot = await checkpointManager.snapshotFile(path);
          if (snapshot != null) _turnSnapshots.add(snapshot);
        }
      }

      if (toolCall.name == 'apply_patch_set') {
        final applyResult = await _executeApplyPatchSet(toolCall, updated);
        onToolCallUpdate?.call(
          updated.copyWith(
            status: applyResult.success ? ToolStatus.success : ToolStatus.error,
            result: applyResult.result,
            error: applyResult.success ? null : applyResult.result,
            completedAt: DateTime.now(),
          ),
        );
        return applyResult;
      }

      SubagentDelegationResult? delegationResult;
      final result = toolCall.name == 'run_command'
          ? await _executeCommandTool(
              toolCall,
              updated,
              permission,
              approvedByReview: approvedByReview,
            )
          : toolCall.name == 'delegate_subagent'
          ? await _delegateSubagent(toolCall).then((value) {
              delegationResult = value;
              return value.toPromptBlock();
            })
          : await _dispatch(
              toolCall.name,
              toolCall.arguments,
              networkApproved:
                  approvedByReview ||
                  (permission.allowed &&
                      permission.reason ==
                          ToolPermissionReason.approvalGranted),
            );
      final resultIsError = _isErrorResult(result);
      final commandExitCode = toolCall.name == 'run_command'
          ? _commandExitCode(result)
          : null;

      onToolCallUpdate?.call(
        updated.copyWith(
          status: resultIsError ? ToolStatus.error : ToolStatus.success,
          result: result,
          error: resultIsError ? result : null,
          completedAt: DateTime.now(),
        ),
      );

      return ToolExecutionResult(
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        result: result,
        success: !resultIsError,
        envelope: ToolResultEnvelope(
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          status: resultIsError
              ? ToolResultStatus.error
              : ToolResultStatus.success,
          summary: _summarizeToolResult(toolCall.name, result),
          stdout: toolCall.name == 'run_command' ? result : null,
          diagnostic: resultIsError ? result : null,
          retryable: resultIsError,
          data: {
            'rawResult': result,
            if (delegationResult != null)
              'delegation': delegationResult!.toJson(),
            if (toolCall.name == 'run_command')
              'command': toolCall.arguments['command'],
            ..._commandResultData(commandExitCode),
            if (toolCall.name == 'propose_patch') ...toolCall.arguments,
          },
          artifacts: delegationResult?.artifacts ?? const [],
        ),
      );
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
        toolName: toolCall.name,
        result: 'Error: $e',
        success: false,
        envelope: ToolResultEnvelope(
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          status: ToolResultStatus.error,
          summary: 'Error: $e',
          diagnostic: e.toString(),
          retryable: true,
        ),
      );
    }
  }

  String _summarizeToolResult(String toolName, String result) {
    final clean = result.trim().replaceAll(RegExp(r'\s+'), ' ');
    final summary = clean.length <= 240
        ? clean
        : '${clean.substring(0, 237)}...';
    return summary.isEmpty ? '$toolName completed.' : summary;
  }

  bool _isErrorResult(String result) {
    final clean = result.trim().toLowerCase();
    return clean.startsWith('error:') ||
        clean.startsWith('unknown tool:') ||
        clean.startsWith('action blocked:') ||
        RegExp(r'\[exit code:\s*[1-9][0-9]*\]').hasMatch(clean);
  }

  int? _commandExitCode(String result) {
    final match = RegExp(
      r'\[exit code:\s*([0-9]+)\]',
      caseSensitive: false,
    ).firstMatch(result);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  Map<String, dynamic> _commandResultData(int? exitCode) {
    if (exitCode == null) return const {};
    return {'exitCode': exitCode};
  }

  Future<String> _executeCommandTool(
    ToolCallInfo toolCall,
    ToolCallInfo running,
    ToolPermissionDecision permission, {
    required bool approvedByReview,
  }) {
    final output = StringBuffer();
    final command = toolCall.arguments['command'] as String? ?? '';
    final allowNetwork =
        CommandSanitizer.checkNetworkAccess(command) != null &&
        ((permission.allowed &&
                permission.reason == ToolPermissionReason.approvalGranted) ||
            (permission.requiresApproval && approvedByReview));
    return _commandTools.runCommand(
      toolCall.arguments,
      runId: toolCall.id,
      allowNetwork: allowNetwork,
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

  int cancelActiveCommands() {
    onCancelSubagents?.call();
    return _commandTools.cancelAll();
  }

  Future<SubagentDelegationResult> _delegateSubagent(
    ToolCallInfo toolCall,
  ) async {
    if (onSubagentDelegation == null) {
      throw StateError(
        'Subagent delegation is unavailable because this Studio runtime has no isolated delegation service.',
      );
    }
    return onSubagentDelegation!(
      SubagentDelegationRequest.fromToolArguments(toolCall.arguments),
    );
  }

  Future<ToolExecutionResult> _executeApplyPatchSet(
    ToolCallInfo toolCall,
    ToolCallInfo running,
  ) async {
    final files = toolCall.arguments['files'] as List<dynamic>? ?? const [];
    if (files.isEmpty) {
      return ToolExecutionResult(
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        result: 'Patch application failed: no files were provided.',
        success: false,
        envelope: ToolResultEnvelope(
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          status: ToolResultStatus.error,
          summary: 'Patch application failed: no files were provided.',
          retryable: true,
        ),
      );
    }

    final snapshots = <FileSnapshot>[];
    final changedFiles = <String>[];
    final diffSummary = <String>[];
    final prepared = <_PreparedPatchSetEdit>[];
    final seenTargets = <String>{};
    final createdDirectories = <String>[];

    try {
      for (final entry in files.whereType<Map<String, dynamic>>()) {
        final rawPath = entry['path'] as String? ?? '';
        final operation = (entry['operation'] as String? ?? 'modify')
            .toLowerCase();
        final target = _resolvePatchPath(rawPath);
        if (target == null) {
          return _patchConflict(
            toolCall,
            'Patch includes a path outside the active workspace: $rawPath',
          );
        }
        if (!seenTargets.add(target)) {
          return _patchConflict(
            toolCall,
            'Patch includes multiple edits for the same file: $rawPath',
          );
        }
        if (_pathTraversesSymlink(target)) {
          return _patchConflict(
            toolCall,
            'Patch path traverses a symlink and could escape the workspace: $rawPath',
          );
        }
        if (_targetIsDirectory(target)) {
          return _patchConflict(
            toolCall,
            'Patch target is a directory, not a file: $rawPath',
          );
        }
        if (_pathHasNonDirectoryParent(target)) {
          return _patchConflict(
            toolCall,
            'Patch target has a non-directory parent path: $rawPath',
          );
        }

        final file = File(target);
        final existed = await file.exists();
        final expected = entry['before'] as String?;

        if ((operation == 'create') && existed) {
          return _patchConflict(toolCall, 'File already exists: $rawPath');
        }
        if (operation == 'modify' && !existed) {
          return _patchConflict(toolCall, 'File missing for modify: $rawPath');
        }
        if (operation == 'delete' && !existed) {
          return _patchConflict(toolCall, 'File missing for delete: $rawPath');
        }
        final before = existed
            ? await _readPatchTargetText(toolCall, file, rawPath)
            : null;
        if (before is ToolExecutionResult) {
          return before;
        }
        if ((operation == 'modify' || operation == 'delete') &&
            expected == null) {
          return _patchConflict(
            toolCall,
            'Patch file is missing expected prior content for $operation: $rawPath',
          );
        }
        if (expected != null && before != expected) {
          return _patchConflict(
            toolCall,
            'File changed since patch was proposed: $rawPath',
          );
        }

        String? after;
        switch (operation) {
          case 'create':
          case 'modify':
            after = entry['content'] as String?;
            if (after == null) {
              return _patchConflict(
                toolCall,
                'Patch file is missing content for $operation: $rawPath',
              );
            }
            final secrets = _secretDetector.scan(after);
            if (secrets.isNotEmpty) {
              final first = secrets.first;
              return _patchConflict(
                toolCall,
                'Patch includes possible ${first.severity} ${first.type} in $rawPath on line ${first.line}.',
              );
            }
            if (operation == 'modify' &&
                expected != null &&
                after == expected) {
              return _patchConflict(
                toolCall,
                'Patch does not change file content: $rawPath',
              );
            }
            break;
          case 'delete':
            break;
          default:
            return _patchConflict(
              toolCall,
              'Unsupported patch operation "$operation" for $rawPath',
            );
        }

        snapshots.add(
          FileSnapshot(
            path: rawPath,
            originalContent: before as String?,
            wasCreated: !existed,
            createdParentDirs: existed
                ? const []
                : _missingParentDirectories(target)
                      .map((dir) => p.relative(dir, from: workingDir))
                      .toList(growable: false),
          ),
        );
        prepared.add(
          _PreparedPatchSetEdit(
            path: rawPath,
            target: target,
            operation: operation,
            before: before,
            after: after,
          ),
        );
      }

      if (prepared.length != files.length) {
        return _patchConflict(
          toolCall,
          'Patch application failed: one or more file entries are malformed.',
        );
      }

      for (final edit in prepared) {
        final file = File(edit.target);
        switch (edit.operation) {
          case 'create':
          case 'modify':
            final parentDirsToCreate = _missingParentDirectories(edit.target);
            await file.parent.create(recursive: true);
            createdDirectories.addAll(parentDirsToCreate);
            await file.writeAsString(edit.after ?? '');
            changedFiles.add(edit.path);
            diffSummary.add(
              _diffLine(edit.path, edit.before, edit.after, edit.operation),
            );
            break;
          case 'delete':
            if (await file.exists()) {
              await file.delete();
            }
            changedFiles.add(edit.path);
            diffSummary.add(
              _diffLine(edit.path, edit.before, null, edit.operation),
            );
            break;
        }

        onToolCallUpdate?.call(
          running.copyWith(result: 'Applied ${changedFiles.length} files...'),
        );
      }

      final title =
          toolCall.arguments['title'] as String? ?? 'Applied patch set';
      final checkpoint = checkpointManager.commitTurn(
        snapshots,
        'Applied patch set: $title',
      );
      final verificationSuggestions = _verificationSuggestions();
      final summary = 'Applied ${changedFiles.length} files.';
      return ToolExecutionResult(
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        result: [
          summary,
          if (checkpoint != null) 'Checkpoint: ${checkpoint.id}',
          if (diffSummary.isNotEmpty)
            'Diff summary:\n${diffSummary.join('\n')}',
          if (changedFiles.isNotEmpty)
            'Changed files: ${changedFiles.join(', ')}',
          if (verificationSuggestions.isNotEmpty)
            'Suggested verification: ${verificationSuggestions.join('; ')}',
        ].join('\n'),
        envelope: ToolResultEnvelope(
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          status: ToolResultStatus.success,
          summary: summary,
          changedFiles: changedFiles,
          artifacts: [if (checkpoint != null) 'checkpoint:${checkpoint.id}'],
          data: {
            'checkpointId': checkpoint?.id,
            'diffSummary': diffSummary,
            'verificationSuggestions': verificationSuggestions,
          },
        ),
      );
    } catch (error) {
      final rollbackErrors = await _restorePatchSnapshots(
        snapshots,
        createdDirectories: createdDirectories,
      );
      final diagnostic = rollbackErrors.isEmpty
          ? error.toString()
          : '${error.toString()}\nRollback errors:\n${rollbackErrors.join('\n')}';
      return ToolExecutionResult(
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        result: [
          'Patch application failed: $error',
          if (snapshots.isNotEmpty && rollbackErrors.isEmpty)
            'Rolled back files changed before the failure.',
          if (rollbackErrors.isNotEmpty)
            'Rollback errors:\n${rollbackErrors.join('\n')}',
        ].join('\n'),
        success: false,
        envelope: ToolResultEnvelope(
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          status: ToolResultStatus.error,
          summary: 'Patch application failed.',
          diagnostic: diagnostic,
          retryable: true,
        ),
      );
    }
  }

  List<String> _verificationSuggestions() {
    final suggestions = <String>[];
    final packageJson = File(p.join(workingDir, 'package.json'));
    if (packageJson.existsSync()) {
      try {
        final json = jsonDecode(packageJson.readAsStringSync());
        if (json is Map<String, dynamic>) {
          final scripts = json['scripts'];
          if (scripts is Map) {
            if (verification_command_filter.isSafePackageScriptBody(
              scripts['test'],
            )) {
              suggestions.add('npm test');
            }
            if (verification_command_filter.isSafePackageScriptBody(
              scripts['lint'],
            )) {
              suggestions.add('npm run lint');
            }
            if (verification_command_filter.isSafePackageScriptBody(
              scripts['build'],
            )) {
              suggestions.add('npm run build');
            }
          }
        }
      } catch (_) {}
    }
    if (File(p.join(workingDir, 'pubspec.yaml')).existsSync()) {
      suggestions.addAll(['flutter analyze', 'flutter test']);
    }
    if (File(p.join(workingDir, 'pyproject.toml')).existsSync() ||
        File(p.join(workingDir, 'pytest.ini')).existsSync()) {
      suggestions.add('python -m pytest');
    }
    if (File(p.join(workingDir, 'Cargo.toml')).existsSync()) {
      suggestions.add('cargo test');
    }
    if (File(p.join(workingDir, 'go.mod')).existsSync()) {
      suggestions.add('go test ./...');
    }
    final makefile = File(p.join(workingDir, 'Makefile'));
    if (makefile.existsSync()) {
      final text = makefile.readAsStringSync();
      final targets = RegExp(
        r'^([A-Za-z0-9_.-]+):',
        multiLine: true,
      ).allMatches(text).map((match) => match.group(1) ?? '').toSet();
      if (targets.contains('test')) suggestions.add('make test');
      if (targets.contains('lint')) suggestions.add('make lint');
      if (targets.contains('build')) suggestions.add('make build');
    }
    return suggestions.toSet().take(5).toList(growable: false);
  }

  Future<List<String>> _restorePatchSnapshots(
    List<FileSnapshot> snapshots, {
    List<String> createdDirectories = const [],
  }) async {
    final errors = <String>[];
    for (final snapshot in snapshots.reversed) {
      try {
        final target = _resolvePatchPath(snapshot.path);
        if (target == null) {
          errors.add('Skipped ${snapshot.path}: outside workspace');
          continue;
        }
        final file = File(target);
        if (snapshot.wasCreated) {
          if (await file.exists()) {
            await file.delete();
          }
        } else if (snapshot.originalContent != null) {
          await file.parent.create(recursive: true);
          await file.writeAsString(snapshot.originalContent!);
        }
      } catch (error) {
        errors.add('Failed to restore ${snapshot.path}: $error');
      }
    }
    for (final path in createdDirectories.reversed) {
      try {
        if (path == workingDir || !p.isWithin(workingDir, path)) continue;
        final directory = Directory(path);
        if (!await directory.exists()) continue;
        if (await directory.list().isEmpty) {
          await directory.delete();
        }
      } catch (error) {
        errors.add(
          'Failed to remove created directory ${p.relative(path, from: workingDir)}: $error',
        );
      }
    }
    return errors;
  }

  List<String> _missingParentDirectories(String target) {
    final root = p.normalize(workingDir);
    final relative = p.relative(p.dirname(target), from: root);
    if (relative == '.' || relative.startsWith('..')) return const [];

    final missing = <String>[];
    var current = root;
    for (final segment in p.split(relative)) {
      if (segment.isEmpty || segment == '.') continue;
      current = p.join(current, segment);
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.notFound) {
        missing.add(current);
      }
    }
    return missing;
  }

  ToolExecutionResult _patchConflict(ToolCallInfo toolCall, String message) {
    return ToolExecutionResult(
      toolCallId: toolCall.id,
      toolName: toolCall.name,
      result: message,
      success: false,
      envelope: ToolResultEnvelope(
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        status: ToolResultStatus.error,
        summary: message,
        diagnostic: 'patch_conflict',
        retryable: true,
      ),
    );
  }

  Future<Object?> _readPatchTargetText(
    ToolCallInfo toolCall,
    File file,
    String displayPath,
  ) async {
    try {
      return await file.readAsString();
    } on FormatException {
      return _patchConflict(
        toolCall,
        'Patch target is not readable as UTF-8 text: $displayPath. Ask Circuit to revise the patch or skip this binary file.',
      );
    } on FileSystemException catch (error) {
      if (error.message.toLowerCase().contains('decode')) {
        return _patchConflict(
          toolCall,
          'Patch target is not readable as UTF-8 text: $displayPath. Ask Circuit to revise the patch or skip this binary file.',
        );
      }
      return _patchConflict(
        toolCall,
        'Patch target could not be read before applying: $displayPath (${error.message}).',
      );
    }
  }

  String? _resolvePatchPath(String rawPath) {
    final sanitized = _sanitizePatchPathInput(rawPath);
    if (sanitized.trim().isEmpty) return null;
    if (_looksLikeWindowsAbsolutePath(sanitized)) return null;
    final resolved = p.normalize(
      p.isAbsolute(sanitized) ? sanitized : p.join(workingDir, sanitized),
    );
    if (resolved != workingDir && !p.isWithin(workingDir, resolved)) {
      return null;
    }
    return resolved;
  }

  String _sanitizePatchPathInput(String rawPath) {
    return rawPath.trim().replaceAll('\\', '/');
  }

  bool _looksLikeWindowsAbsolutePath(String sanitizedPath) {
    return RegExp(r'^[A-Za-z]:/').hasMatch(sanitizedPath) ||
        sanitizedPath.startsWith('//');
  }

  bool _pathTraversesSymlink(String target) {
    final root = p.normalize(workingDir);
    final relative = p.relative(target, from: root);
    if (relative == '.') return false;

    var current = root;
    for (final segment in p.split(relative)) {
      if (segment.isEmpty || segment == '.') continue;
      current = p.join(current, segment);
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        return true;
      }
    }
    return false;
  }

  bool _targetIsDirectory(String target) {
    return FileSystemEntity.typeSync(target, followLinks: false) ==
        FileSystemEntityType.directory;
  }

  bool _pathHasNonDirectoryParent(String target) {
    final root = p.normalize(workingDir);
    final relative = p.relative(target, from: root);
    if (relative == '.') return false;

    var current = root;
    final segments = p.split(relative);
    for (final segment in segments.take(segments.length - 1)) {
      if (segment.isEmpty || segment == '.') continue;
      current = p.join(current, segment);
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.directory) return true;
    }
    return false;
  }

  String _diffLine(
    String path,
    String? before,
    String? after,
    String operation,
  ) {
    final beforeLines = before?.split('\n').length ?? 0;
    final afterLines = after?.split('\n').length ?? 0;
    final delta = afterLines - beforeLines;
    final suffix = delta == 0
        ? ''
        : delta > 0
        ? ' (+$delta lines)'
        : ' ($delta lines)';
    return '- ${operation[0].toUpperCase()}${operation.substring(1)} $path$suffix';
  }

  Future<String> _dispatch(
    String name,
    Map<String, dynamic> args, {
    bool networkApproved = false,
  }) async {
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
      case 'apply_patch_set':
        return 'Error: apply_patch_set must run through the patch transaction path.';

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
        return 'Error: run_command must run through the reviewed command execution path.';
      case 'delegate_subagent':
        return 'Error: delegate_subagent must run through the isolated delegation path.';

      // Web tools
      case 'web_fetch':
      case 'web_search':
        return _webTools.execute(name, args, allowNetwork: networkApproved);

      // GitHub tools
      case 'github_whoami':
      case 'github_list_repos':
      case 'github_get_repo':
      case 'github_list_issues':
      case 'github_get_issue':
      case 'github_list_prs':
      case 'github_get_pr':
      case 'github_search_repos':
      case 'github_search_issues':
        return _githubTools.execute(name, args);
      case 'github_create_issue':
      case 'github_close_issue':
      case 'github_create_repo':
        return 'Error: GitHub mutation tools are unavailable in Studio turns until the connector is explicitly feature-enabled and scoped.';

      default:
        // MCP tool dispatch
        if (ToolRegistry.isMcpTool(name)) {
          return _dispatchMcpTool(name, args);
        }
        return 'Unknown tool: $name';
    }
  }

  Future<String> _dispatchMcpTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    final guard = _permissionPolicy.evaluate(
      ToolCallInfo(id: 'mcp-dispatch-guard', name: name, arguments: args),
    );
    if (!guard.allowed || !guard.isReadOnly) {
      return 'Error: MCP tool blocked: ${guard.message}';
    }
    if (_mcpClient == null) {
      return 'Error: MCP client not configured';
    }
    final parsed = _mcpClient!.parseMcpToolName(name);
    if (parsed == null) {
      return 'Error: Could not parse MCP tool name: $name';
    }
    return _mcpClient!.callToolOnServer(parsed.$1, parsed.$2, args);
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
      case 'delegate_subagent':
        final task = (args['task'] as String? ?? '').trim();
        final grant = (args['tool_grant'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .join(', ');
        return 'Delegate bounded task: ${task.isEmpty ? 'Untitled task' : task}${grant.isEmpty ? '' : ' (tools: $grant)'}';
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
    var concreteEditCount = 0;
    final fileLines = files
        .whereType<Map<String, dynamic>>()
        .map((file) {
          final operation = file['operation'] ?? 'plan';
          final hasContent =
              file['content'] is String || file['after'] is String;
          final isDelete = operation == 'delete';
          if (hasContent || isDelete) concreteEditCount++;
          return '- ${file['path'] ?? 'unknown'}: ${file['intent'] ?? ''} ($operation${hasContent || isDelete ? ', concrete' : ', plan-only'})';
        })
        .join('\n');
    return [
      'Patch proposal: $title',
      if (summary.trim().isNotEmpty) summary.trim(),
      if (fileLines.trim().isNotEmpty) fileLines,
      concreteEditCount == 0
          ? 'No files were changed. CircuitCode has captured this as a reviewable plan. Do not ask the user to type approve; wait for the app review controls or user feedback.'
          : 'No files were changed yet. CircuitCode captured $concreteEditCount concrete file edit${concreteEditCount == 1 ? '' : 's'} for review/apply in the app.',
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
    if (toolCall.name == 'apply_patch_set') {
      final files = args['files'] as List<dynamic>? ?? const [];
      for (final entry in files.whereType<Map<String, dynamic>>()) {
        final path = entry['path'] as String? ?? 'unknown';
        final content = entry['content'] as String? ?? '';
        if (content.isEmpty) continue;
        final secrets = _secretDetector.scan(content);
        for (final s in secrets) {
          warnings.add(
            '${s.severity.toUpperCase()}: Possible ${s.type} detected in $path',
          );
        }
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

class _PreparedPatchSetEdit {
  final String path;
  final String target;
  final String operation;
  final String? before;
  final String? after;

  const _PreparedPatchSetEdit({
    required this.path,
    required this.target,
    required this.operation,
    this.before,
    this.after,
  });
}
