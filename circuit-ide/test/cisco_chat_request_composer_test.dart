import 'dart:convert';

import 'package:circuit_ide/agent/providers/cisco_chat_request_composer.dart';
import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timestamp = DateTime.utc(2026, 7, 14);

  test(
    'Cisco request composer preserves typed system image tool and protocol fields',
    () {
      final request = CiscoChatRequestComposer.compose(
        chatBaseUrl: 'https://circuit.example.test',
        model: 'gpt-5-nano',
        appKey: 'scoped-app-key',
        protocol: const ProviderProtocol(version: 1, minimumCompatible: 1),
        messages: [
          ChatMessage(
            id: 'user-1',
            role: MessageRole.user,
            content: 'Review this screenshot',
            timestamp: timestamp,
          ),
        ],
        tools: const [
          ToolDefinition(
            name: 'read_file',
            description: 'Read one scoped file',
            parameters: {'type': 'object'},
          ),
        ],
        systemPrompt: 'Stay scoped.',
        temperature: 0.2,
        maxTokens: 123,
        reasoningEnabled: true,
        images: const [
          ProviderImageInput(
            id: 'image-1',
            label: 'Screenshot',
            mimeType: 'image/png',
            base64Data: 'aW1hZ2U=',
            byteLength: 5,
            width: 2,
            height: 2,
            estimatedTokens: 1,
          ),
        ],
      );

      expect(
        request.url,
        'https://circuit.example.test/gpt-5-nano/chat/completions?api-version=2025-04-01-preview',
      );
      expect(request.messageCount, 2);
      expect(request.body['circuit_protocol'], {
        'version': 1,
        'minimumCompatible': 1,
      });
      expect(request.body['temperature'], 0.2);
      expect(request.body['max_tokens'], 123);
      expect(request.body['stream'], isTrue);
      expect(request.body['reasoning_effort'], 'medium');
      expect(request.body['tool_choice'], 'auto');
      expect(jsonDecode(request.body['user'] as String), {
        'appkey': 'scoped-app-key',
      });
      final messages = request.body['messages'] as List<dynamic>;
      expect(messages.first, {'role': 'system', 'content': 'Stay scoped.'});
      final imageMessage = messages.last as Map<String, dynamic>;
      expect(imageMessage['role'], 'user');
      expect(imageMessage['content'], [
        {'type': 'text', 'text': 'Review this screenshot'},
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/png;base64,aW1hZ2U=',
            'detail': 'auto',
          },
        },
      ]);
    },
  );

  test('Cisco request composer refuses images without a user message', () {
    expect(
      () => CiscoChatRequestComposer.compose(
        chatBaseUrl: 'https://circuit.example.test',
        model: 'gpt-5-nano',
        appKey: 'scoped-app-key',
        protocol: const ProviderProtocol(),
        messages: const [],
        tools: const [],
        temperature: 0.7,
        maxTokens: 10,
        images: const [
          ProviderImageInput(
            id: 'image-1',
            label: 'Screenshot',
            mimeType: 'image/png',
            base64Data: 'aW1hZ2U=',
            byteLength: 5,
            estimatedTokens: 1,
          ),
        ],
      ),
      throwsA(isA<ProviderCapabilityException>()),
    );
  });
}
