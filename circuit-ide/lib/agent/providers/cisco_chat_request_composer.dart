import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../models/chat_message.dart';
import 'provider_interface.dart';

/// The redacted, typed payload passed from the Circuit adapter to its one
/// configured chat endpoint. Keeping this composition separate means HTTP,
/// OAuth, redirects, and stream decoding cannot silently alter multimodal or
/// tool request shape.
class CiscoComposedChatRequest {
  final String url;
  final Map<String, dynamic> body;
  final int messageCount;

  const CiscoComposedChatRequest({
    required this.url,
    required this.body,
    required this.messageCount,
  });
}

abstract final class CiscoChatRequestComposer {
  static CiscoComposedChatRequest compose({
    required String chatBaseUrl,
    required String model,
    required String? appKey,
    required ProviderProtocol protocol,
    required List<ChatMessage> messages,
    required List<ToolDefinition> tools,
    required double temperature,
    required int maxTokens,
    String? systemPrompt,
    List<ProviderImageInput> images = const [],
    bool reasoningEnabled = false,
  }) {
    final apiMessages = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }
    for (final message in messages) {
      apiMessages.add(message.toApiMessage());
    }
    if (images.isNotEmpty) {
      final userMessageIndex = apiMessages.lastIndexWhere(
        (message) => message['role'] == 'user',
      );
      if (userMessageIndex < 0) {
        throw const ProviderCapabilityException(
          'Image input requires a user message in the provider request.',
        );
      }
      final userMessage = Map<String, dynamic>.from(
        apiMessages[userMessageIndex],
      );
      final text = userMessage['content'] as String? ?? '';
      userMessage['content'] = [
        if (text.isNotEmpty) {'type': 'text', 'text': text},
        ...images.map((image) => image.toOpenAiContentPart()),
      ];
      apiMessages[userMessageIndex] = userMessage;
    }

    final body = <String, dynamic>{
      'messages': apiMessages,
      'user': jsonEncode({'appkey': appKey}),
      'circuit_protocol': protocol.toRequestJson(),
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': true,
    };
    if (reasoningEnabled) body['reasoning_effort'] = 'medium';
    if (tools.isNotEmpty) {
      body['tools'] = tools.map((tool) => tool.toOpenAIFormat()).toList();
      body['tool_choice'] = 'auto';
    }
    return CiscoComposedChatRequest(
      url:
          '$chatBaseUrl/$model/chat/completions?api-version=${AppConstants.ciscoApiVersion}',
      body: body,
      messageCount: apiMessages.length,
    );
  }
}
