import '../../models/chat_message.dart';

class ModelInfo {
  final String id;
  final String displayName;
  final int contextWindow;
  final double inputCostPer1k;
  final double outputCostPer1k;

  const ModelInfo({
    required this.id,
    required this.displayName,
    required this.contextWindow,
    this.inputCostPer1k = 0,
    this.outputCostPer1k = 0,
  });
}

class ChatChunk {
  final String? content;
  final String? toolCallId;
  final String? toolCallName;
  final String? toolCallArguments;
  final int? toolCallIndex;
  final int promptTokens;
  final int completionTokens;
  final String? finishReason;
  final bool isDone;

  const ChatChunk({
    this.content,
    this.toolCallId,
    this.toolCallName,
    this.toolCallArguments,
    this.toolCallIndex,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.finishReason,
    this.isDone = false,
  });
}

class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toOpenAIFormat() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };

  Map<String, dynamic> toAnthropicFormat() => {
        'name': name,
        'description': description,
        'input_schema': parameters,
      };
}

abstract class AIProvider {
  String get name;
  List<ModelInfo> get availableModels;
  bool get isConnected;

  Future<void> connect(Map<String, String> credentials);
  void disconnect();

  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  });
}
