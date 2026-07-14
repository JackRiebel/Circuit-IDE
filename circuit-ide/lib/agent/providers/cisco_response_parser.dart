import 'dart:convert';

import '../../core/utils/logger.dart';
import '../../models/provider_lifecycle_event.dart';
import 'provider_interface.dart';

/// Stateless JSON fallback parser for the Circuit provider protocol.
///
/// It is deliberately separate from the HTTP/OAuth adapter so malformed
/// payloads, lifecycle diagnostics, token accounting, and tool-call shape
/// validation can be regression-tested without a transport.
class CiscoResponseParser {
  const CiscoResponseParser._();

  /// Parse a plain JSON chat completion response (non-streaming fallback).
  static Stream<ChatChunk> parseJsonResponse(String body) async* {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      Logger.error('Failed to parse Circuit API response as JSON.');
      throw Exception('Invalid response from Circuit API');
    }

    yield* parseJsonData(data);
  }

  static Stream<ChatChunk> parseJsonData(Map<String, dynamic> data) async* {
    final errorMessage = ciscoJsonErrorPayloadMessage(data);
    if (errorMessage != null) {
      final detail =
          'Circuit JSON fallback returned an error payload: $errorMessage';
      yield ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }

    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      const detail =
          'Circuit JSON fallback contained no choices with assistant text or tool calls.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.noTextOrTool,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }

    final rawChoice = choices[0];
    if (rawChoice is! Map<String, dynamic>) {
      const detail =
          'Circuit JSON fallback contained a malformed choice entry.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }
    final choice = rawChoice;
    final rawMessage = choice['message'];
    if (rawMessage != null && rawMessage is! Map<String, dynamic>) {
      const detail = 'Circuit JSON fallback contained a malformed message.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }
    final message = rawMessage as Map<String, dynamic>? ?? {};
    final content = message['content'] as String? ?? '';
    final finishReason = choice['finish_reason'] as String? ?? 'stop';

    final usage = data['usage'] as Map<String, dynamic>?;
    final promptTokens = usage?['prompt_tokens'] as int? ?? 0;
    final completionTokens = usage?['completion_tokens'] as int? ?? 0;
    final promptDetails = usage?['prompt_tokens_details'];
    final cachedInputTokens = promptDetails is Map
        ? promptDetails['cached_tokens'] as int? ?? 0
        : 0;
    final completionDetails = usage?['completion_tokens_details'];
    final reasoningTokens = completionDetails is Map
        ? completionDetails['reasoning_tokens'] as int? ?? 0
        : 0;
    final toolTokens = usage?['tool_tokens'] as int? ?? 0;

    if (content.isNotEmpty) {
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.firstTextDelta,
        lifecycleDetail: 'Circuit returned the first assistant text delta.',
      );
      yield ChatChunk(content: content);
    }

    final rawToolCalls = message['tool_calls'];
    if (rawToolCalls != null && rawToolCalls is! List<dynamic>) {
      const detail =
          'Circuit JSON fallback contained a malformed tool_calls field.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }
    final toolCalls = rawToolCalls as List<dynamic>?;
    final parsedToolCalls = <Map<String, dynamic>>[];
    if (toolCalls != null) {
      for (final toolCall in toolCalls) {
        if (toolCall is! Map<String, dynamic>) {
          const detail =
              'Circuit JSON fallback contained a malformed tool-call entry.';
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
            lifecycleDetail: detail,
          );
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: detail,
          );
          throw Exception(detail);
        }
        final function = toolCall['function'];
        if (function is! Map<String, dynamic>) {
          const detail =
              'Circuit JSON fallback contained a malformed tool-call function.';
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
            lifecycleDetail: detail,
          );
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: detail,
          );
          throw Exception(detail);
        }
        final name = function['name'];
        final arguments = function['arguments'];
        if (name is! String || name.trim().isEmpty || arguments is! String) {
          const detail =
              'Circuit JSON fallback contained an incomplete tool-call function.';
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.malformedChunk,
            lifecycleDetail: detail,
          );
          yield const ChatChunk(
            lifecycleKind: ProviderLifecycleEventKind.failed,
            lifecycleDetail: detail,
          );
          throw Exception(detail);
        }
        parsedToolCalls.add(toolCall);
      }
    }

    if (parsedToolCalls.isNotEmpty) {
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.firstToolDelta,
        lifecycleDetail: 'Circuit returned the first tool-call delta.',
      );
    }
    if (content.isEmpty && parsedToolCalls.isNotEmpty) {
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.toolOnly,
        lifecycleDetail:
            'Circuit returned tool calls without assistant text in JSON fallback.',
      );
    } else if (content.isEmpty && parsedToolCalls.isEmpty) {
      const detail =
          'Circuit JSON fallback contained no assistant text or tool calls.';
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.noTextOrTool,
        lifecycleDetail: detail,
      );
      yield const ChatChunk(
        lifecycleKind: ProviderLifecycleEventKind.failed,
        lifecycleDetail: detail,
      );
      throw Exception(detail);
    }
    if (parsedToolCalls.isNotEmpty) {
      for (var index = 0; index < parsedToolCalls.length; index++) {
        final toolCall = parsedToolCalls[index];
        final function = toolCall['function'] as Map<String, dynamic>;
        yield ChatChunk(
          toolCallIndex: index,
          toolCallId: toolCall['id'] as String?,
          toolCallName: function['name'] as String,
          toolCallArguments: function['arguments'] as String,
        );
      }
    }

    yield const ChatChunk(
      lifecycleKind: ProviderLifecycleEventKind.completed,
      lifecycleDetail: 'Circuit provider JSON response completed.',
    );
    yield ChatChunk(
      finishReason: finishReason,
      promptTokens: promptTokens,
      cachedInputTokens: cachedInputTokens,
      completionTokens: completionTokens,
      reasoningTokens: reasoningTokens,
      toolTokens: toolTokens,
      isDone: true,
    );
  }
}

/// Detects an explicit provider error payload without copying response text
/// into a durable lifecycle diagnostic. Provider error bodies are untrusted:
/// an upstream can reflect request content or connector-sensitive details.
String? ciscoJsonErrorPayloadMessage(Map<String, dynamic> data) {
  final error = data['error'];
  if (error is Map<String, dynamic> ||
      error is String && error.trim().isNotEmpty) {
    return 'Circuit provider reported an error.';
  }

  final type = data['type'];
  final message = data['message'] ?? data['detail'];
  if (type is String &&
      type.toLowerCase().contains('error') &&
      message is String &&
      message.trim().isNotEmpty) {
    return 'Circuit provider reported an error.';
  }
  return null;
}
