import 'dart:async';
import 'dart:io';

import 'package:circuit_ide/agent/providers/provider_interface.dart';
import 'package:circuit_ide/agent/studio_turn_runner.dart';
import 'package:circuit_ide/agent/tools/tool_executor.dart';
import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/enums/message_role.dart';
import 'package:circuit_ide/models/chat_message.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/services/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'StudioTurnRunner sends pixels only through image-capable providers',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'studio-image-runner-',
      );
      addTearDown(() => root.delete(recursive: true));
      final provider = _ImageCaptureProvider();
      final runner = StudioTurnRunner(
        provider: provider,
        workingDir: root.path,
        events: EventBus(),
        model: 'vision-test',
        toolExecutor: ToolExecutor(workingDir: root.path),
      );

      final result = await runner.run(
        requestId: 'request-image',
        userMessage: 'What is visible in this screenshot?',
        history: [
          ChatMessage(
            id: 'previous',
            role: MessageRole.assistant,
            content: 'Previous response',
            timestamp: DateTime(2026),
          ),
        ],
        toolMode: AgentToolMode.ask,
        intent: TurnIntent.ask,
        images: const [
          ProviderImageInput(
            id: 'image:screen',
            label: 'screen.png',
            mimeType: 'image/png',
            base64Data: 'cGl4ZWxz',
            byteLength: 6,
            width: 1200,
            height: 800,
            estimatedTokens: 1280,
          ),
        ],
      );

      expect(result.content, contains('visible primary action'));
      final request = provider.capturedRequest;
      expect(request, isNotNull);
      expect(request!.images, hasLength(1));
      expect(
        request.images.single.toOpenAiContentPart()['image_url']['url'],
        'data:image/png;base64,cGl4ZWxz',
      );
      expect(
        request.messages.map((message) => message.content).join('\n'),
        isNot(contains('cGl4ZWxz')),
      );
    },
  );
}

class _ImageCaptureProvider implements AIProvider, ImageCapableProvider {
  ProviderChatRequest? capturedRequest;

  @override
  String get name => 'Image capture provider';

  @override
  List<ModelInfo> get availableModels => const [
    ModelInfo(
      id: 'vision-test',
      displayName: 'Vision test',
      contextWindow: 120000,
    ),
  ];

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: 'image-capture',
    displayName: 'Image capture',
    shortName: 'Image',
    capabilities: ProviderCapabilities(
      supportsImageInput: true,
      supportedImageMimeTypes: {'image/png'},
      maxImageBytes: 1024 * 1024,
      maxImageDimension: 2048,
    ),
  );

  @override
  bool get isConnected => true;

  @override
  ProviderCapabilities get capabilities => descriptor.capabilities;

  @override
  Future<void> connect(Map<String, String> credentials) async {}

  @override
  void disconnect() {}

  @override
  void cancelActiveRequest() {}

  @override
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: ConnectorHealthStatus.connected,
    message: 'Connected',
    checkedAt: DateTime(2026),
  );

  @override
  Future<List<ConnectorModelInfo>> refreshModels() async => const [
    ConnectorModelInfo(id: 'vision-test', displayName: 'Vision test'),
  ];

  @override
  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) => Stream<ChatChunk>.error(
    StateError('Image-capable request must use the typed image boundary.'),
  );

  @override
  Stream<ChatChunk> chatWithRequest(ProviderChatRequest request) async* {
    capturedRequest = request;
    yield const ChatChunk(
      content: 'The visible primary action is the blue Save button.',
    );
    yield const ChatChunk(finishReason: 'stop', isDone: true);
  }
}
