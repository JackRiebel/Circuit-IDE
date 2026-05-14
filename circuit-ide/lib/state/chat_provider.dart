import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../enums/connection_status.dart';
import '../enums/event_type.dart';
import '../enums/message_role.dart';
import '../models/chat_message.dart';
import '../models/confirmation_request.dart';
import '../models/token_usage.dart';
import '../models/cost_info.dart';
import '../models/tool_call_info.dart';
import 'connection_provider.dart';
import 'file_tree_provider.dart';

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
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _uuid = Uuid();

class ChatNotifier extends Notifier<ChatState> {
  bool _listening = false;
  Timer? _safetyTimer;
  bool _wasCancelled = false;

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
      final content = event.data['content'] as String? ?? '';
      state = state.copyWith(
        isStreaming: true,
        streamingContent: state.streamingContent + content,
      );
    });

    // Message completed — create assistant message from event data
    // ChatNotifier is the SOLE owner of the UI message list.
    service.events.on(EventType.messageCompleted, (event) {
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
      } else {
        state = state.copyWith(
          isStreaming: false,
          isProcessing: false,
          streamingContent: '',
        );
      }
      _cancelSafetyTimer();
    });

    // Message error — add error info to chat
    service.events.on(EventType.messageError, (event) {
      final errorMsg = event.data['error'] as String? ?? 'Unknown error';
      state = state.copyWith(
        isStreaming: false,
        isProcessing: false,
        streamingContent: '',
        error: errorMsg,
      );
      _cancelSafetyTimer();
    });

    service.events.on(EventType.confirmationNeeded, (event) {
      final request = event.data['request'] as ConfirmationRequest;
      state = state.copyWith(pendingConfirmation: request);
    });

    service.events.on(EventType.confirmationReceived, (event) {
      state = state.copyWith(pendingConfirmation: null);
    });

    service.events.on(EventType.tokensUpdated, (event) {
      state = state.copyWith(
        tokenUsage: event.data['usage'] as TokenUsage? ?? state.tokenUsage,
        lastTokenUsage:
            event.data['lastUsage'] as TokenUsage? ?? state.lastTokenUsage,
        costInfo: event.data['cost'] as CostInfo? ?? state.costInfo,
      );
    });
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;
    if (state.isProcessing) return;

    final service = ref.read(agentServiceProvider);
    final connectionStatus = ref.read(connectionStatusProvider);
    if (connectionStatus != ConnectionStatus.connected) {
      state = state.copyWith(
        error: 'Not connected — configure credentials in Settings.',
      );
      return;
    }

    // Add the user message to the chat immediately so it's visible
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
    );

    _wasCancelled = false;
    state = state.copyWith(
      isProcessing: true,
      messages: [...state.messages, userMsg],
      streamingContent: '',
      error: null,
    );

    // Start safety timer — auto-reset stuck state after 30 seconds
    _startSafetyTimer();

    try {
      final result = await service.sendMessage(content);

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
        state = state.copyWith(
          isStreaming: false,
          isProcessing: false,
          streamingContent: '',
          error:
              service.state.error ??
              'Request failed — check credentials and try again.',
        );
      }
    } catch (e) {
      _cancelSafetyTimer();
      state = state.copyWith(
        isStreaming: false,
        isProcessing: false,
        streamingContent: '',
        error: e.toString().replaceFirst('Exception: ', ''),
      );
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
    }
  }

  /// Cancel the current AI operation
  void cancelOperation() {
    final service = ref.read(agentServiceProvider);
    service.cancelCurrentOperation();
    _wasCancelled = true;
    _cancelSafetyTimer();
    state = state.copyWith(
      isProcessing: false,
      isStreaming: false,
      streamingContent: '',
    );
  }

  /// Clear the current error
  void clearError() {
    state = state.copyWith(error: null);
  }

  void approveConfirmation(String id) {
    ref.read(agentServiceProvider).approveConfirmation(id);
  }

  void rejectConfirmation(String id) {
    ref.read(agentServiceProvider).rejectConfirmation(id);
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
    _cancelSafetyTimer();
    state = const ChatState();
  }

  void _startSafetyTimer() {
    _cancelSafetyTimer();
    _safetyTimer = Timer(const Duration(seconds: 60), () {
      if (state.isProcessing) {
        state = state.copyWith(
          isProcessing: false,
          isStreaming: false,
          streamingContent: '',
          error: 'Request timed out. Please try again.',
        );
      }
    });
  }

  void _cancelSafetyTimer() {
    _safetyTimer?.cancel();
    _safetyTimer = null;
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
