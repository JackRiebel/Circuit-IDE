import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../agent/config/config.dart';
import '../agent/config/models_config.dart';
import '../agent/tools/tool_registry.dart';
import '../agent/providers/provider_interface.dart';
import '../enums/connection_status.dart';
import '../enums/event_type.dart';
import '../enums/message_role.dart';
import '../enums/ai_provider.dart';
import '../models/agent_preflight.dart';
import '../models/chat_message.dart';
import '../models/confirmation_request.dart';
import '../models/context_attachment.dart';
import '../models/token_usage.dart';
import '../models/cost_info.dart';
import '../models/tool_call_info.dart';
import '../models/agent_run.dart';
import '../models/agent_request.dart';
import 'agent_run_provider.dart';
import 'agent_request_provider.dart';
import 'connection_provider.dart';
import 'file_tree_provider.dart';
import 'settings_provider.dart';
import 'workspace_context_provider.dart';

// Sentinel for distinguishing "not passed" from "explicitly null" in copyWith
const _sentinel = Object();

class ChatState {
  final List<ChatMessage> messages;
  final bool isProcessing;
  final bool isStreaming;
  final String streamingContent;
  final TokenUsage tokenUsage;
  final TokenUsage lastTokenUsage;
  final CostInfo costInfo;
  final ConfirmationRequest? pendingConfirmation;
  final AgentPreflightResult? preflight;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isProcessing = false,
    this.isStreaming = false,
    this.streamingContent = '',
    this.tokenUsage = const TokenUsage(),
    this.lastTokenUsage = const TokenUsage(),
    this.costInfo = const CostInfo(),
    this.pendingConfirmation,
    this.preflight,
    this.error,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isProcessing,
    bool? isStreaming,
    String? streamingContent,
    TokenUsage? tokenUsage,
    TokenUsage? lastTokenUsage,
    CostInfo? costInfo,
    Object? pendingConfirmation = _sentinel,
    Object? preflight = _sentinel,
    Object? error = _sentinel,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isProcessing: isProcessing ?? this.isProcessing,
      isStreaming: isStreaming ?? this.isStreaming,
      streamingContent: streamingContent ?? this.streamingContent,
      tokenUsage: tokenUsage ?? this.tokenUsage,
      lastTokenUsage: lastTokenUsage ?? this.lastTokenUsage,
      costInfo: costInfo ?? this.costInfo,
      pendingConfirmation: identical(pendingConfirmation, _sentinel)
          ? this.pendingConfirmation
          : pendingConfirmation as ConfirmationRequest?,
      preflight: identical(preflight, _sentinel)
          ? this.preflight
          : preflight as AgentPreflightResult?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _uuid = Uuid();

class ChatNotifier extends Notifier<ChatState> {
  bool _listening = false;
  Timer? _safetyTimer;
  bool _wasCancelled = false;
  String? _activeRequestId;
  bool? _temporaryAutoApprovePrevious;

  @override
  ChatState build() {
    _listenToEvents();
    return const ChatState();
  }

  void _listenToEvents() {
    if (_listening) return;
    _listening = true;

    final service = ref.read(agentServiceProvider);

    // Streaming content chunks — accumulate for live preview
    service.events.on(EventType.messageChunk, (event) {
      if (!_eventBelongsToActiveRequest(event.data)) return;
      final content = event.data['content'] as String? ?? '';
      state = state.copyWith(
        isStreaming: true,
        streamingContent: state.streamingContent + content,
      );
      ref
          .read(agentRequestProvider.notifier)
          .markStreaming(AgentRequestLane.chat);
    });

    // Message completed — create assistant message from event data
    // ChatNotifier is the SOLE owner of the UI message list.
    service.events.on(EventType.messageCompleted, (event) {
      if (!_eventBelongsToActiveRequest(event.data)) return;
      // Ignore stale completed events after cancel/timeout
      if (_wasCancelled) return;

      final content = event.data['content'] as String? ?? '';
      final toolCalls =
          (event.data['toolCalls'] as List<dynamic>?)?.cast<ToolCallInfo>() ??
          [];

      // Only add an assistant message if there's actual content or tool calls
      if (content.isNotEmpty || toolCalls.isNotEmpty) {
        final assistantMsg = ChatMessage(
          id: _uuid.v4(),
          role: MessageRole.assistant,
          content: content,
          timestamp: DateTime.now(),
          toolCalls: toolCalls,
        );
        state = state.copyWith(
          isStreaming: false,
          isProcessing: false,
          streamingContent: '',
          messages: [...state.messages, assistantMsg],
        );
        // Auto-refresh file tree if any tool calls were made (files may have changed)
        if (toolCalls.isNotEmpty) {
          ref.read(fileTreeProvider.notifier).refresh();
        }
        _restoreTemporaryAutoApprove();
      } else {
        state = state.copyWith(
          isStreaming: false,
          isProcessing: false,
          streamingContent: '',
        );
      }
      _cancelSafetyTimer();
      _activeRequestId = null;
      ref.read(agentRequestProvider.notifier).finish(AgentRequestLane.chat);
    });

    // Message error — add error info to chat
    service.events.on(EventType.messageError, (event) {
      if (!_eventBelongsToActiveRequest(event.data)) return;
      final errorMsg = event.data['error'] as String? ?? 'Unknown error';
      state = state.copyWith(
        isStreaming: false,
        isProcessing: false,
        streamingContent: '',
        error: errorMsg,
      );
      _cancelSafetyTimer();
      _activeRequestId = null;
      ref
          .read(agentRequestProvider.notifier)
          .finish(AgentRequestLane.chat, error: errorMsg);
      _restoreTemporaryAutoApprove();
    });

    service.events.on(EventType.confirmationNeeded, (event) {
      if (!_eventBelongsToActiveRequest(event.data)) return;
      final request = event.data['request'] as ConfirmationRequest;
      state = state.copyWith(pendingConfirmation: request);
    });

    service.events.on(EventType.confirmationReceived, (event) {
      if (!_eventBelongsToActiveRequest(event.data)) return;
      state = state.copyWith(pendingConfirmation: null);
    });

    service.events.on(EventType.tokensUpdated, (event) {
      if (!_eventBelongsToActiveRequest(event.data)) return;
      state = state.copyWith(
        tokenUsage: event.data['usage'] as TokenUsage? ?? state.tokenUsage,
        lastTokenUsage:
            event.data['lastUsage'] as TokenUsage? ?? state.lastTokenUsage,
        costInfo: event.data['cost'] as CostInfo? ?? state.costInfo,
      );
    });
  }

  Future<void> sendMessage(
    String content, {
    List<ContextAttachment> attachments = const [],
    List<ChatMessage>? historyOverride,
    AgentToolMode toolMode = AgentToolMode.code,
    String? requestId,
  }) async {
    if (content.trim().isEmpty && attachments.isEmpty) return;
    if (state.isProcessing) return;

    final service = ref.read(agentServiceProvider);
    final resolvedAttachments = await _resolveAttachments(attachments);
    final preflight = await preflightMessage(content, resolvedAttachments);
    state = state.copyWith(preflight: preflight);
    if (!preflight.canSend) {
      state = state.copyWith(
        error: preflight.primaryIssue?.message ?? 'Request cannot be sent yet.',
      );
      return;
    }

    // Add the user message to the chat immediately so it's visible
    final visibleContent = content.trim().isEmpty
        ? '[Context-only request]'
        : content;
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: visibleContent,
      timestamp: DateTime.now(),
    );

    _wasCancelled = false;
    final runNotifier = ref.read(agentRunProvider.notifier);
    final runId = runNotifier.startRun(
      id: requestId,
      kind: AgentRunKind.chat,
      model: service.state.model,
      message: 'User message sent',
      title: _preview(visibleContent),
      inputPreview: _preview(visibleContent),
      retryPrompt: visibleContent,
      retryAttachments: resolvedAttachments,
      contextAttachmentCount: resolvedAttachments.length,
    );
    ref
        .read(agentRequestProvider.notifier)
        .start(
          lane: AgentRequestLane.chat,
          requestId: runId,
          model: service.state.model,
        );
    _activeRequestId = runId;
    state = state.copyWith(
      isProcessing: true,
      messages: [...state.messages, userMsg],
      streamingContent: '',
      error: null,
      preflight: preflight,
    );

    // Start safety timer — only reset genuinely stuck requests.
    _startSafetyTimer();

    try {
      final finalContent = _buildMessageWithContext(
        visibleContent,
        resolvedAttachments,
      );
      final result = await service.sendMessage(
        finalContent,
        requestId: runId,
        historyOverride: historyOverride,
        toolMode: toolMode,
      );

      _cancelSafetyTimer();

      // Sync token/cost info from service (messages are NOT synced —
      // the messageCompleted event handler already added the assistant message)
      state = state.copyWith(
        tokenUsage: service.state.tokenUsage,
        lastTokenUsage: service.state.lastTokenUsage,
        costInfo: service.state.costInfo,
      );

      // If result is null and we're still processing, service hit timeout/error
      if (result == null && state.isProcessing) {
        runNotifier.finishRun(
          AgentRunKind.chat,
          error:
              service.state.error ??
              'Request failed — check credentials and try again.',
        );
        state = state.copyWith(
          isStreaming: false,
          isProcessing: false,
          streamingContent: '',
          error:
              service.state.error ??
              'Request failed — check credentials and try again.',
        );
        ref
            .read(agentRequestProvider.notifier)
            .finish(
              AgentRequestLane.chat,
              error:
                  service.state.error ??
                  'Request failed — check credentials and try again.',
            );
      }
      if (result != null) {
        runNotifier.finishRun(
          AgentRunKind.chat,
          outputPreview: _preview(result),
        );
        ref.read(agentRequestProvider.notifier).finish(AgentRequestLane.chat);
        if (_activeRequestId == runId) _activeRequestId = null;
      }
    } catch (e) {
      _cancelSafetyTimer();
      _restoreTemporaryAutoApprove();
      ref
          .read(agentRunProvider.notifier)
          .finishRun(
            AgentRunKind.chat,
            error: e.toString().replaceFirst('Exception: ', ''),
          );
      state = state.copyWith(
        isStreaming: false,
        isProcessing: false,
        streamingContent: '',
        error: e.toString().replaceFirst('Exception: ', ''),
      );
      ref
          .read(agentRequestProvider.notifier)
          .finish(AgentRequestLane.chat, error: e.toString());
      _activeRequestId = null;
    } finally {
      _cancelSafetyTimer();
      // Only clear stuck flags, don't add spurious errors
      if (state.isProcessing || state.isStreaming) {
        state = state.copyWith(
          isStreaming: false,
          isProcessing: false,
          streamingContent: '',
        );
      }
      if (!state.isProcessing && !state.isStreaming) {
        _restoreTemporaryAutoApprove();
      }
    }
  }

  /// Cancel the current AI operation
  void cancelOperation() {
    final service = ref.read(agentServiceProvider);
    service.cancelCurrentOperation();
    ref
        .read(agentRequestProvider.notifier)
        .requestCancel(AgentRequestLane.chat);
    ref.read(agentRunProvider.notifier).requestCancel(AgentRunKind.chat);
    ref
        .read(agentRunProvider.notifier)
        .finishRun(AgentRunKind.chat, cancelled: true);
    _wasCancelled = true;
    _activeRequestId = null;
    _cancelSafetyTimer();
    state = state.copyWith(
      isProcessing: false,
      isStreaming: false,
      streamingContent: '',
    );
    ref
        .read(agentRequestProvider.notifier)
        .finish(AgentRequestLane.chat, cancelled: true);
    _restoreTemporaryAutoApprove();
  }

  /// Clear the current error
  void clearError() {
    state = state.copyWith(error: null);
  }

  void setPreflight(AgentPreflightResult? result) {
    state = state.copyWith(preflight: result);
  }

  void approveConfirmation(String id) {
    ref.read(agentServiceProvider).approveConfirmation(id);
    if (state.pendingConfirmation?.id == id) {
      state = state.copyWith(pendingConfirmation: null);
    }
  }

  void approveConfirmationForCurrentTask(String id) {
    final service = ref.read(agentServiceProvider);
    _temporaryAutoApprovePrevious ??= service.state.autoApprove;
    service.setAutoApprove(true);
    service.approveConfirmation(id);
    if (state.pendingConfirmation?.id == id) {
      state = state.copyWith(pendingConfirmation: null);
    }
  }

  void rejectConfirmation(String id) {
    ref.read(agentServiceProvider).rejectConfirmation(id);
    if (state.pendingConfirmation?.id == id) {
      state = state.copyWith(pendingConfirmation: null);
    }
  }

  bool handlePendingApprovalText(String text) {
    final pending = state.pendingConfirmation;
    if (pending == null) return false;
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final compact = normalized.replaceAll(RegExp(r'[^a-z ]+'), ' ');
    if (RegExp(r'\b(reject|deny|cancel|stop)\b').hasMatch(compact)) {
      rejectConfirmation(pending.id);
      return true;
    }
    if (RegExp(r'\b(always|auto|all|this task)\b').hasMatch(compact) &&
        RegExp(r'\b(approve|yes|ok|proceed|continue)\b').hasMatch(compact)) {
      approveConfirmationForCurrentTask(pending.id);
      return true;
    }
    if (RegExp(
      r'^(approve|approved|yes|y|ok|okay|proceed|continue|do it|go ahead)( please)?$',
    ).hasMatch(compact.trim())) {
      approveConfirmation(pending.id);
      return true;
    }
    return false;
  }

  /// Save current chat session to disk
  Future<String?> saveSession() async {
    if (state.messages.isEmpty) return null;
    final service = ref.read(agentServiceProvider);
    return service.saveSession();
  }

  /// Load a saved session, replacing current messages
  Future<bool> loadSession(String name) async {
    final service = ref.read(agentServiceProvider);
    final messages = await service.loadSessionMessages(name);
    if (messages == null) return false;

    _wasCancelled = false;
    _cancelSafetyTimer();
    state = ChatState(messages: messages);
    return true;
  }

  /// Clear chat — fire-and-forget auto-save so callers stay synchronous
  void clearHistory() {
    if (state.messages.isNotEmpty) {
      ref.read(agentServiceProvider).saveSession();
    }
    ref.read(agentServiceProvider).clearHistory();
    _wasCancelled = false;
    _activeRequestId = null;
    _cancelSafetyTimer();
    state = const ChatState();
  }

  void _startSafetyTimer() {
    _cancelSafetyTimer();
    _safetyTimer = Timer(const Duration(minutes: 4), () {
      if (state.isProcessing) {
        ref.read(agentServiceProvider).cancelCurrentOperation();
        ref
            .read(agentRunProvider.notifier)
            .finishRun(
              AgentRunKind.chat,
              error:
                  'The AI request is still running after 4 minutes. Please try again or check the provider connection.',
            );
        state = state.copyWith(
          isProcessing: false,
          isStreaming: false,
          streamingContent: '',
          error:
              'The AI request is still running after 4 minutes. Please try again or check the provider connection.',
        );
        ref
            .read(agentRequestProvider.notifier)
            .finish(
              AgentRequestLane.chat,
              error:
                  'The AI request is still running after 4 minutes. Please try again or check the provider connection.',
            );
        _activeRequestId = null;
      }
    });
  }

  Future<AgentPreflightResult> preflightMessage(
    String content,
    List<ContextAttachment> attachments,
  ) async {
    final issues = <AgentPreflightIssue>[];
    final settings = ref.read(settingsProvider);
    final service = ref.read(agentServiceProvider);
    final connectionStatus = ref.read(connectionStatusProvider);
    final workspace = ref.read(workspaceContextProvider);
    final selectedModel = service.activeProviderType == AIProviderType.cisco
        ? service.state.model
        : settings.ciscoModel;
    ModelInfo? cachedModelInfo;
    for (final model in settings.connectorModels) {
      final info = model.toModelInfo();
      if (info.id == selectedModel) {
        cachedModelInfo = info;
        break;
      }
    }
    final modelInfo = cachedModelInfo ?? ModelsConfig.getModel(selectedModel);
    final contextWindow = modelInfo?.contextWindow ?? 120000;
    final estimatedTokens = _estimateTokens(
      _buildMessageWithContext(content, attachments),
    );

    if (state.isProcessing) {
      issues.add(
        const AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message: 'A chat request is already running.',
          recoveryAction: AgentPreflightRecoveryAction.waitForRequest,
        ),
      );
    }

    if (connectionStatus != ConnectionStatus.connected) {
      final config = await AgentConfig.load();
      final hasCredentials = config.hasCiscoCredentials;
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message: hasCredentials
              ? 'AI is not connected. Reconnect before sending.'
              : 'Circuit credentials are missing. Add them in Settings.',
          recoveryAction: hasCredentials
              ? AgentPreflightRecoveryAction.reconnect
              : AgentPreflightRecoveryAction.openSettings,
        ),
      );
    }

    final availableModels = [
      ...ModelsConfig.ciscoModels,
      ...settings.connectorModels.map((model) => model.toModelInfo()),
    ];
    final modelAvailable = availableModels.any(
      (model) => model.id == selectedModel,
    );
    if (!modelAvailable) {
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message: '$selectedModel is not available from Circuit Company AI.',
          recoveryAction: AgentPreflightRecoveryAction.openSettings,
        ),
      );
    } else if (modelInfo?.supportsTools == false && attachments.isNotEmpty) {
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.warning,
          message:
              '$selectedModel does not advertise tool support, so coding actions may be limited.',
          recoveryAction: AgentPreflightRecoveryAction.openSettings,
        ),
      );
    }

    if (workspace.isBusy) {
      issues.add(
        const AgentPreflightIssue(
          severity: AgentPreflightSeverity.warning,
          message: 'Workspace context is still refreshing.',
          recoveryAction: AgentPreflightRecoveryAction.waitForWorkspace,
        ),
      );
    } else if (workspace.error != null) {
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.warning,
          message: 'Workspace context is degraded: ${workspace.error}',
          recoveryAction: AgentPreflightRecoveryAction.waitForWorkspace,
        ),
      );
    }

    if (estimatedTokens > contextWindow * 0.95) {
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.blocking,
          message:
              'Context is too large (${TokenUsage.formatCount(estimatedTokens)} of ${TokenUsage.formatCount(contextWindow)} tokens).',
          recoveryAction: AgentPreflightRecoveryAction.reduceContext,
        ),
      );
    } else if (estimatedTokens > contextWindow * 0.75) {
      issues.add(
        AgentPreflightIssue(
          severity: AgentPreflightSeverity.warning,
          message:
              'Context is large (${TokenUsage.formatCount(estimatedTokens)} of ${TokenUsage.formatCount(contextWindow)} tokens).',
          recoveryAction: AgentPreflightRecoveryAction.reduceContext,
        ),
      );
    }

    return AgentPreflightResult(
      issues: issues,
      estimatedTokens: estimatedTokens,
      contextWindow: contextWindow,
      checkedAt: DateTime.now(),
    );
  }

  bool _eventBelongsToActiveRequest(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;
    if (_activeRequestId == null) return false;
    return requestId == _activeRequestId;
  }

  void _cancelSafetyTimer() {
    _safetyTimer?.cancel();
    _safetyTimer = null;
  }

  void _restoreTemporaryAutoApprove() {
    final previous = _temporaryAutoApprovePrevious;
    if (previous == null) return;
    _temporaryAutoApprovePrevious = null;
    ref.read(agentServiceProvider).setAutoApprove(previous);
  }

  String _buildMessageWithContext(
    String content,
    List<ContextAttachment> attachments,
  ) {
    final parts = <String>[];
    if (attachments.isNotEmpty) {
      parts.add(
        attachments
            .map((attachment) => attachment.toPromptBlock())
            .join('\n\n'),
      );
    }
    parts.add(content);
    return parts.join('\n\n');
  }

  Future<List<ContextAttachment>> _resolveAttachments(
    List<ContextAttachment> attachments,
  ) async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    final resolved = <ContextAttachment>[];
    for (final attachment in attachments) {
      if (attachment.type != ContextAttachmentType.file ||
          attachment.path == null ||
          attachment.content?.startsWith('```') == true) {
        resolved.add(
          attachment.copyWith(
            resolutionStatus: ContextAttachmentResolutionStatus.resolved,
            estimatedTokens: _estimateTokens(attachment.toPromptBlock()),
          ),
        );
        continue;
      }

      final filePath = p.isAbsolute(attachment.path!)
          ? attachment.path!
          : rootPath == null
          ? null
          : p.normalize(p.join(rootPath, attachment.path!));
      if (filePath == null ||
          rootPath != null && !p.isWithin(rootPath, filePath)) {
        resolved.add(
          attachment.copyWith(
            resolutionStatus: ContextAttachmentResolutionStatus.missing,
            content: 'File could not be resolved inside the open workspace.',
            estimatedTokens: 20,
          ),
        );
        continue;
      }
      final file = File(filePath);
      if (!await file.exists()) {
        resolved.add(
          attachment.copyWith(
            resolutionStatus: ContextAttachmentResolutionStatus.missing,
            content: 'File was not found at send time.',
            estimatedTokens: 20,
          ),
        );
        continue;
      }

      final raw = await file.readAsString();
      const maxChars = 16000;
      final truncated = raw.length > maxChars;
      final body = truncated ? raw.substring(0, maxChars) : raw;
      resolved.add(
        attachment.copyWith(
          path: filePath,
          content: '```\n$body\n```',
          resolutionStatus: truncated
              ? ContextAttachmentResolutionStatus.tooLarge
              : ContextAttachmentResolutionStatus.resolved,
          estimatedTokens: _estimateTokens(body),
          truncationMessage: truncated
              ? '[Context truncated from ${raw.length} to $maxChars characters.]'
              : null,
        ),
      );
    }
    return resolved;
  }

  int _estimateTokens(String value) {
    if (value.trim().isEmpty) return 0;
    return (value.length / 4).ceil();
  }

  String _preview(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 120) return normalized;
    return '${normalized.substring(0, 120)}...';
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
