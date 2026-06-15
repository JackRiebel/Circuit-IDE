import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../enums/event_type.dart';
import '../models/agent_request.dart';
import '../models/agent_run.dart';
import '../models/confirmation_request.dart';
import '../models/studio_request_lifecycle.dart';
import '../models/studio_source_artifact.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import '../models/token_usage.dart';
import '../models/tool_call_info.dart';
import '../models/reviewed_edit.dart';
import '../services/event_bus.dart';
import 'agent_request_provider.dart';
import 'agent_run_provider.dart';
import 'agent_workspace_provider.dart';
import 'connection_provider.dart';
import 'patch_proposal_provider.dart';
import 'studio_shell_provider.dart';
import 'studio_thread_provider.dart';
import 'studio_turn_provider.dart';

class StudioRequestLifecycleController
    extends Notifier<StudioRequestLifecycleState> {
  final _softTimers = <String, Timer>{};
  final _hardTimers = <String, Timer>{};
  final _handlers = <EventType, EventHandler>{};

  @override
  StudioRequestLifecycleState build() {
    final events = ref.read(agentServiceProvider).events;
    _listenToAgentEvents(events);
    ref.onDispose(() {
      for (final timer in [..._softTimers.values, ..._hardTimers.values]) {
        timer.cancel();
      }
      for (final entry in _handlers.entries) {
        events.off(entry.key, entry.value);
      }
    });
    return const StudioRequestLifecycleState();
  }

  void registerRequest({
    required String requestId,
    required String threadId,
    required String model,
    required StudioContextSummary contextSummary,
    String? taskId,
  }) {
    final now = DateTime.now();
    final entry = StudioRequestLifecycleEntry(
      requestId: requestId,
      threadId: threadId,
      taskId: taskId,
      model: model,
      contextSummary: contextSummary,
      startedAt: now,
      lastEventAt: now,
      lastEventKind: StudioRequestLifecycleEventKind.requestStarted,
      lastEventDetail: 'Request sent to Circuit AI.',
    );
    state = state.copyWith(
      activeRequests: {...state.activeRequests, requestId: entry},
    );
    ref
        .read(studioThreadProvider.notifier)
        .markPhase(
          threadId,
          status: StudioThreadStatus.preflighting,
          phase: StudioSendPhase.preflighting,
          requestId: requestId,
          model: model,
          contextSummary: contextSummary,
        );
    ref
        .read(studioTurnProvider.notifier)
        .markProgress(
          requestId,
          title: 'Request sent',
          detail: 'Waiting for Circuit AI.',
          status: StudioTurnStatus.waitingForModel,
        );
    _scheduleWatchdogs(entry);
  }

  void cancelRequest(
    String requestId, {
    String message = 'Request cancelled.',
  }) {
    final entry = state.active(requestId);
    if (entry == null) return;
    _finish(entry, StudioRequestLifecycleEventKind.cancelled, message);
  }

  void failRequest(String requestId, String message) {
    final entry = state.active(requestId);
    if (entry == null) return;
    _finish(entry, StudioRequestLifecycleEventKind.failed, message);
  }

  void _listenToAgentEvents(EventBus events) {
    void on(EventType type, EventHandler handler) {
      _handlers[type] = handler;
      events.on(type, handler);
    }

    on(EventType.messageStarted, _handleMessageStarted);
    on(EventType.messageChunk, _handleMessageChunk);
    on(EventType.tokensUpdated, _handleTokensUpdated);
    on(EventType.toolCallStarted, _handleToolStarted);
    on(EventType.toolCallCompleted, _handleToolCompleted);
    on(EventType.toolCallError, _handleToolError);
    on(EventType.confirmationNeeded, _handleConfirmationNeeded);
    on(EventType.confirmationReceived, _handleConfirmationReceived);
    on(EventType.messageCompleted, _handleMessageCompleted);
    on(EventType.messageError, _handleMessageError);
  }

  StudioRequestLifecycleEntry? _entryFor(Event event) {
    final requestId = event.data['requestId'] as String?;
    if (requestId == null) return null;
    return state.active(requestId);
  }

  void _handleMessageStarted(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    _touch(
      entry,
      StudioRequestLifecycleEventKind.requestStarted,
      detail: 'Circuit AI accepted the request.',
    );
    ref
        .read(studioTurnProvider.notifier)
        .markProgress(
          entry.requestId,
          title: 'Connected',
          detail: 'Circuit AI accepted the request.',
          status: StudioTurnStatus.waitingForModel,
        );
  }

  void _handleMessageChunk(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final content = event.data['content'] as String? ?? '';
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == entry.threadId)
        .firstOrNull;
    final streamingContent = '${thread?.streamingContent ?? ''}$content';
    _touch(
      entry,
      StudioRequestLifecycleEventKind.streaming,
      detail: 'Circuit AI is responding.',
    );
    ref
        .read(studioTurnProvider.notifier)
        .appendAssistantDelta(entry.requestId, content);
    ref
        .read(studioThreadProvider.notifier)
        .markPhase(
          entry.threadId,
          status: StudioThreadStatus.streaming,
          phase: StudioSendPhase.streaming,
          requestId: entry.requestId,
          model: entry.model,
          contextSummary: entry.contextSummary,
          streamingContent: streamingContent,
        );
  }

  void _handleTokensUpdated(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final usage = event.data['lastUsage'] as TokenUsage?;
    if (usage == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .updateTokenUsage(entry.threadId, usage);
  }

  void _handleToolStarted(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final tool = event.data['toolCall'] as ToolCallInfo?;
    final activity = _toolActivity(tool, running: true);
    _touch(
      entry,
      StudioRequestLifecycleEventKind.toolRunning,
      detail: activity.detail,
    );
    ref
        .read(studioThreadProvider.notifier)
        .markPhase(
          entry.threadId,
          status: StudioThreadStatus.runningCommand,
          phase: StudioSendPhase.runningCommand,
          requestId: entry.requestId,
          model: entry.model,
          contextSummary: entry.contextSummary,
        );
    if (tool != null) {
      _upsertToolEvent(
        entry,
        tool,
        activity.title,
        activity.detail,
        running: true,
      );
    } else {
      ref
          .read(studioTurnProvider.notifier)
          .markProgress(
            entry.requestId,
            title: 'Tool running',
            detail: 'running',
            status: StudioTurnStatus.toolRunning,
            transcriptVisible: true,
          );
    }
  }

  void _handleToolCompleted(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final tool = event.data['toolCall'] as ToolCallInfo?;
    final activity = _toolActivity(tool, running: false);
    _touch(
      entry,
      StudioRequestLifecycleEventKind.toolRunning,
      detail: activity.detail,
    );
    if (tool != null) {
      _upsertToolEvent(entry, tool, activity.title, activity.detail);
      if (tool.name == 'propose_patch') {
        _createPatchPlan(entry, tool);
      }
    } else {
      ref
          .read(studioTurnProvider.notifier)
          .markProgress(
            entry.requestId,
            title: 'Tool completed',
            detail: 'completed',
            transcriptVisible: true,
          );
    }
  }

  void _handleToolError(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final tool = event.data['toolCall'] as ToolCallInfo?;
    final activity = _toolActivity(tool, running: false, failed: true);
    _touch(
      entry,
      StudioRequestLifecycleEventKind.toolRunning,
      detail: activity.detail,
    );
    if (tool != null) {
      _upsertToolEvent(entry, tool, activity.title, activity.detail);
    } else {
      ref
          .read(studioTurnProvider.notifier)
          .markProgress(
            entry.requestId,
            title: 'Tool failed',
            detail: 'failed',
            transcriptVisible: true,
          );
    }
  }

  void _handleConfirmationNeeded(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    _touch(
      entry,
      StudioRequestLifecycleEventKind.approvalNeeded,
      detail: 'Waiting for approval.',
    );
    ref.read(studioThreadProvider.notifier).waitForApproval(entry.threadId);
    final request = event.data['request'] as ConfirmationRequest?;
    if (request != null) {
      ref
          .read(studioTurnProvider.notifier)
          .upsertApproval(entry.requestId, request);
    }
    if (entry.taskId != null) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .markWaitingForApproval(
            entry.taskId!,
            message: 'Waiting for approval.',
          );
    }
  }

  void _handleConfirmationReceived(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final approvalId = event.data['id'] as String?;
    if (approvalId == null) return;
    final approved = event.data['approved'] as bool? ?? false;
    ref
        .read(studioTurnProvider.notifier)
        .resolveApproval(
          entry.requestId,
          approvalId,
          approved
              ? ApprovalRequestState.approved
              : ApprovalRequestState.rejected,
        );
    _touch(
      entry,
      StudioRequestLifecycleEventKind.toolRunning,
      detail: approved ? 'Approval granted.' : 'Approval rejected.',
    );
  }

  void _handleMessageCompleted(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final content = event.data['content'] as String? ?? '';
    unawaited(_addCompletionSummary(entry, content: content));
    if (content.trim().isNotEmpty) {
      ref
          .read(studioThreadProvider.notifier)
          .appendAssistantMessage(entry.threadId, content);
      for (final url in detectLocalUrls(content)) {
        ref
            .read(studioThreadProvider.notifier)
            .upsertSourceArtifact(
              entry.threadId,
              StudioSourceArtifact(
                id: 'assistant-url-${entry.threadId}-${entry.requestId}-$url',
                kind: StudioSourceArtifactKind.localUrl,
                title: Uri.tryParse(url)?.host ?? 'Local preview',
                subtitle: url,
                value: url,
                threadId: entry.threadId,
                requestId: entry.requestId,
                localUrl: url,
                createdAt: DateTime.now(),
              ),
            );
      }
    }
    final usage = event.data['lastUsage'] as TokenUsage?;
    ref
        .read(studioThreadProvider.notifier)
        .complete(entry.threadId, tokenUsage: usage);
    if (entry.taskId != null) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .completeTask(entry.taskId!, result: _preview(content));
    }
    _finish(entry, StudioRequestLifecycleEventKind.completed, 'Completed.');
  }

  void _handleMessageError(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final error = event.data['error'] as String? ?? 'Request failed.';
    ref.read(studioThreadProvider.notifier).fail(entry.threadId, error);
    ref.read(studioTurnProvider.notifier).fail(entry.requestId, error);
    if (entry.taskId != null) {
      ref.read(agentWorkspaceProvider.notifier).failTask(entry.taskId!, error);
    }
    _finish(entry, StudioRequestLifecycleEventKind.failed, error);
  }

  void _touch(
    StudioRequestLifecycleEntry entry,
    StudioRequestLifecycleEventKind kind, {
    String? detail,
  }) {
    final updated = entry.copyWith(
      lastEventAt: DateTime.now(),
      lastEventKind: kind,
      lastEventDetail: detail,
    );
    state = state.copyWith(
      activeRequests: {...state.activeRequests, entry.requestId: updated},
    );
    _scheduleSoftWatchdog(updated);
  }

  void _finish(
    StudioRequestLifecycleEntry entry,
    StudioRequestLifecycleEventKind kind,
    String detail,
  ) {
    _cancelTimers(entry.requestId);
    final finished = entry.copyWith(
      lastEventAt: DateTime.now(),
      lastEventKind: kind,
      lastEventDetail: detail,
    );
    final active = {...state.activeRequests}..remove(entry.requestId);
    final recent = {entry.requestId: finished, ...state.recentRequests};
    state = state.copyWith(
      activeRequests: active,
      recentRequests: Map.fromEntries(recent.entries.take(30)),
    );
    if (kind == StudioRequestLifecycleEventKind.failed) {
      ref.read(studioTurnProvider.notifier).fail(entry.requestId, detail);
    } else if (kind == StudioRequestLifecycleEventKind.cancelled) {
      ref.read(studioTurnProvider.notifier).cancel(entry.requestId, detail);
    } else if (kind == StudioRequestLifecycleEventKind.completed) {
      ref
          .read(studioTurnProvider.notifier)
          .markProgress(
            entry.requestId,
            title: _titleFor(kind),
            detail: detail,
            status: StudioTurnStatus.completed,
          );
    }
  }

  void _scheduleWatchdogs(StudioRequestLifecycleEntry entry) {
    _scheduleSoftWatchdog(entry);
    _hardTimers[entry.requestId]?.cancel();
    _hardTimers[entry.requestId] = Timer(const Duration(minutes: 4), () {
      final current = state.active(entry.requestId);
      if (current == null) return;
      const message =
          'Request timed out after 4 minutes. Try again or check the Circuit AI connection.';
      ref
          .read(agentRequestProvider.notifier)
          .finish(AgentRequestLane.chat, error: message);
      ref
          .read(agentRunProvider.notifier)
          .finishRun(AgentRunKind.chat, error: message);
      ref.read(agentServiceProvider).cancelCurrentOperation();
      ref.read(studioThreadProvider.notifier).fail(current.threadId, message);
      if (current.taskId != null) {
        ref
            .read(agentWorkspaceProvider.notifier)
            .failTask(current.taskId!, message);
      }
      _finish(current, StudioRequestLifecycleEventKind.failed, message);
    });
  }

  void _scheduleSoftWatchdog(StudioRequestLifecycleEntry entry) {
    _softTimers[entry.requestId]?.cancel();
    _softTimers[entry.requestId] = Timer(const Duration(seconds: 18), () {
      final current = state.active(entry.requestId);
      if (current == null) return;
      _touch(
        current,
        StudioRequestLifecycleEventKind.waitingForModel,
        detail: 'Still waiting for Circuit AI.',
      );
      ref
          .read(studioThreadProvider.notifier)
          .markPhase(
            current.threadId,
            status: StudioThreadStatus.preflighting,
            phase: StudioSendPhase.preflighting,
            requestId: current.requestId,
            model: current.model,
            contextSummary: current.contextSummary,
          );
      ref
          .read(studioTurnProvider.notifier)
          .markProgress(
            current.requestId,
            title: 'Still waiting',
            detail: 'Circuit AI has not returned output yet.',
            status: StudioTurnStatus.waitingForModel,
          );
    });
  }

  void _cancelTimers(String requestId) {
    _softTimers.remove(requestId)?.cancel();
    _hardTimers.remove(requestId)?.cancel();
  }

  void _upsertToolEvent(
    StudioRequestLifecycleEntry entry,
    ToolCallInfo tool,
    String title,
    String detail, {
    bool running = false,
  }) {
    ref
        .read(studioTurnProvider.notifier)
        .upsertTool(
          entry.requestId,
          toolCallId: tool.id,
          toolName: tool.name,
          title: title,
          detail: detail,
          filePath: _pathForTool(tool),
          running: running,
        );
  }

  void _createPatchPlan(StudioRequestLifecycleEntry entry, ToolCallInfo tool) {
    final args = tool.arguments;
    final title = args['title'] as String? ?? 'Implementation plan';
    final summary = args['summary'] as String? ?? '';
    final planMarkdown =
        args['plan_markdown'] as String? ??
        args['planMarkdown'] as String? ??
        summary;
    final files = (args['files'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final edits = <ProposedFileEdit>[];
    final plannedFiles = <String>[];
    for (final file in files) {
      final path = file['path'] as String?;
      if (path == null || path.trim().isEmpty) continue;
      final intent = file['intent'] as String? ?? '';
      plannedFiles.add(intent.trim().isEmpty ? path : '$path — $intent');
      final content = file['content'] as String? ?? file['after'] as String?;
      if (content == null) continue;
      final operation = (file['operation'] as String? ?? 'create')
          .toLowerCase();
      edits.add(
        ProposedFileEdit(
          path: path,
          type: switch (operation) {
            'delete' => ProposedFileEditType.delete,
            'modify' || 'update' => ProposedFileEditType.modify,
            _ => ProposedFileEditType.create,
          },
          before: file['before'] as String?,
          after: content,
          unifiedDiff: file['unified_diff'] as String?,
        ),
      );
    }
    final patch = ref
        .read(patchProposalProvider.notifier)
        .propose(
          title: title,
          edits: edits,
          planMarkdown: planMarkdown,
          plannedFiles: plannedFiles,
          agentTaskId: entry.taskId,
          runId: entry.requestId,
          comparisonSummary: summary.trim().isEmpty ? planMarkdown : summary,
        );
    ref.read(studioShellProvider.notifier).openReview();
    ref
        .read(studioTurnProvider.notifier)
        .markProgress(
          entry.requestId,
          title: patch.isPlanOnly ? 'Plan ready for review' : 'Patch ready',
          detail: patch.isPlanOnly
              ? 'Review the plan, then approve, revise, or reject it.'
              : '${patch.fileCount} files proposed.',
          transcriptVisible: true,
        );
  }

  Future<void> _addCompletionSummary(
    StudioRequestLifecycleEntry entry, {
    required String content,
  }) async {
    final rootPath = entry.contextSummary.rootPath;
    final gitSummary = await _gitChangeSummary(rootPath);
    final detail = gitSummary ?? 'Ready for the next prompt.';
    ref
        .read(studioTurnProvider.notifier)
        .complete(entry.requestId, content: content, summary: detail);
  }

  Future<String?> _gitChangeSummary(String? rootPath) async {
    if (rootPath == null || rootPath.trim().isEmpty) return null;
    try {
      final gitDir = Directory('$rootPath/.git');
      if (!await gitDir.exists()) return null;
      final status = await Process.run('git', [
        '-C',
        rootPath,
        'status',
        '--short',
      ]).timeout(const Duration(seconds: 2));
      final lines = (status.stdout as String)
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList(growable: false);
      if (lines.isEmpty) return 'No file changes detected.';

      final numstat = await Process.run('git', [
        '-C',
        rootPath,
        'diff',
        '--numstat',
      ]).timeout(const Duration(seconds: 2));
      var additions = 0;
      var deletions = 0;
      for (final line in (numstat.stdout as String).split('\n')) {
        final parts = line.split('\t');
        if (parts.length < 3) continue;
        additions += int.tryParse(parts[0]) ?? 0;
        deletions += int.tryParse(parts[1]) ?? 0;
      }
      final fileLabel = lines.length == 1
          ? '1 file changed'
          : '${lines.length} files changed';
      final delta = additions == 0 && deletions == 0
          ? ''
          : ' +$additions -$deletions';
      return '$fileLabel$delta';
    } catch (_) {
      return null;
    }
  }

  _ToolActivity _toolActivity(
    ToolCallInfo? tool, {
    required bool running,
    bool failed = false,
  }) {
    if (tool == null) {
      return _ToolActivity(
        failed
            ? 'Tool failed'
            : running
            ? 'Using tool'
            : 'Used tool',
        failed
            ? 'failed'
            : running
            ? 'running'
            : 'completed',
      );
    }
    final action = failed
        ? _failedToolTitle(tool.name)
        : running
        ? _runningToolTitle(tool.name)
        : _completedToolTitle(tool.name);
    return _ToolActivity(action, _toolDetail(tool, failed: failed));
  }

  String _runningToolTitle(String name) => switch (name) {
    'read_file' => 'Reading file',
    'list_files' => 'Listing files',
    'search_files' => 'Searching files',
    'git_status' => 'Checking git status',
    'git_diff' => 'Reviewing diff',
    'run_command' => 'Running command',
    'write_file' || 'edit_file' => 'Editing file',
    'propose_patch' => 'Preparing changes',
    _ => 'Using ${_prettyToolName(name)}',
  };

  String _completedToolTitle(String name) => switch (name) {
    'read_file' => 'Read file',
    'list_files' => 'Listed files',
    'search_files' => 'Searched files',
    'git_status' => 'Checked git status',
    'git_diff' => 'Reviewed diff',
    'run_command' => 'Ran command',
    'write_file' || 'edit_file' => 'Edited file',
    'propose_patch' => 'Prepared changes',
    _ => 'Used ${_prettyToolName(name)}',
  };

  String _failedToolTitle(String name) => switch (name) {
    'run_command' => 'Command failed',
    'write_file' || 'edit_file' => 'Edit failed',
    _ => '${_prettyToolName(name)} failed',
  };

  String _toolDetail(ToolCallInfo tool, {required bool failed}) {
    final args = tool.arguments;
    final status = failed ? 'failed' : tool.status.name;
    final path = _pathForTool(tool);
    if (path != null) return '$path · $status';
    if (tool.name == 'run_command') {
      return '${args['command'] ?? 'command'} · $status';
    }
    if (tool.name == 'search_files') {
      return '${args['query'] ?? 'search'} · $status';
    }
    if (tool.name == 'propose_patch') {
      return '${args['title'] ?? 'Patch proposal'} · $status';
    }
    return status;
  }

  String? _pathForTool(ToolCallInfo tool) {
    final value =
        tool.arguments['path'] ??
        tool.arguments['file'] ??
        tool.arguments['directory'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  String _prettyToolName(String name) {
    return name.replaceAll('_', ' ');
  }

  String _titleFor(StudioRequestLifecycleEventKind kind) => switch (kind) {
    StudioRequestLifecycleEventKind.completed => 'Completed',
    StudioRequestLifecycleEventKind.failed => 'Failed',
    StudioRequestLifecycleEventKind.cancelled => 'Cancelled',
    StudioRequestLifecycleEventKind.approvalNeeded => 'Approval needed',
    StudioRequestLifecycleEventKind.toolRunning => 'Tool activity',
    StudioRequestLifecycleEventKind.streaming => 'Streaming',
    StudioRequestLifecycleEventKind.waitingForModel => 'Still waiting',
    StudioRequestLifecycleEventKind.requestStarted => 'Request sent',
  };

  String _preview(String content) {
    final trimmed = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.length <= 180) return trimmed;
    return '${trimmed.substring(0, 177)}...';
  }
}

final studioRequestLifecycleProvider =
    NotifierProvider<
      StudioRequestLifecycleController,
      StudioRequestLifecycleState
    >(StudioRequestLifecycleController.new);

class _ToolActivity {
  final String title;
  final String detail;

  const _ToolActivity(this.title, this.detail);
}
