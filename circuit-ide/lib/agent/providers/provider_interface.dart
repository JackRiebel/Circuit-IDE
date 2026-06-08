import '../../models/chat_message.dart';

class ModelInfo {
  final String id;
  final String displayName;
  final int contextWindow;
  final double inputCostPer1k;
  final double outputCostPer1k;
  final bool supportsTools;

  const ModelInfo({
    required this.id,
    required this.displayName,
    required this.contextWindow,
    this.inputCostPer1k = 0,
    this.outputCostPer1k = 0,
    this.supportsTools = true,
  });
}

enum ConnectorHealthStatus {
  unknown,
  credentialsMissing,
  connecting,
  connected,
  degraded,
  tokenFailed,
  modelUnavailable,
  requestFailed,
}

class ProviderCapabilities {
  final bool supportsStreaming;
  final bool supportsNativeToolCalls;
  final bool supportsModelRefresh;
  final bool supportsCancellation;

  const ProviderCapabilities({
    this.supportsStreaming = true,
    this.supportsNativeToolCalls = true,
    this.supportsModelRefresh = true,
    this.supportsCancellation = true,
  });
}

class ProviderDescriptor {
  final String id;
  final String displayName;
  final String shortName;
  final ProviderCapabilities capabilities;

  const ProviderDescriptor({
    required this.id,
    required this.displayName,
    required this.shortName,
    this.capabilities = const ProviderCapabilities(),
  });
}

class ConnectorModelInfo {
  final String id;
  final String displayName;
  final int contextWindow;
  final bool supportsTools;
  final double inputCostPer1k;
  final double outputCostPer1k;

  const ConnectorModelInfo({
    required this.id,
    required this.displayName,
    this.contextWindow = 120000,
    this.supportsTools = true,
    this.inputCostPer1k = 0,
    this.outputCostPer1k = 0,
  });

  ModelInfo toModelInfo() => ModelInfo(
    id: id,
    displayName: displayName,
    contextWindow: contextWindow,
    supportsTools: supportsTools,
    inputCostPer1k: inputCostPer1k,
    outputCostPer1k: outputCostPer1k,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'contextWindow': contextWindow,
    'supportsTools': supportsTools,
    'inputCostPer1k': inputCostPer1k,
    'outputCostPer1k': outputCostPer1k,
  };

  static ConnectorModelInfo? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.trim().isEmpty) return null;
    return ConnectorModelInfo(
      id: id,
      displayName: json['displayName'] as String? ?? id,
      contextWindow: json['contextWindow'] as int? ?? 120000,
      supportsTools: json['supportsTools'] as bool? ?? true,
      inputCostPer1k: (json['inputCostPer1k'] as num?)?.toDouble() ?? 0,
      outputCostPer1k: (json['outputCostPer1k'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ConnectorHealth {
  final ConnectorHealthStatus status;
  final String message;
  final DateTime checkedAt;

  const ConnectorHealth({
    required this.status,
    required this.message,
    required this.checkedAt,
  });
}

enum ProviderStreamEventType { textDelta, toolCallDelta, usage, done, error }

class ProviderRequestError {
  final String message;
  final int? statusCode;
  final String? requestId;
  final String? modelId;
  final bool retryable;
  final String? rawSnippet;

  const ProviderRequestError({
    required this.message,
    this.statusCode,
    this.requestId,
    this.modelId,
    this.retryable = false,
    this.rawSnippet,
  });
}

class ProviderStreamEvent {
  final ProviderStreamEventType type;
  final String? textDelta;
  final ChatChunk? toolCallDelta;
  final int promptTokens;
  final int completionTokens;
  final ProviderRequestError? error;

  const ProviderStreamEvent({
    required this.type,
    this.textDelta,
    this.toolCallDelta,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.error,
  });
}

class ProviderRequestHandle {
  bool _cancelRequested = false;

  bool get cancelRequested => _cancelRequested;

  void cancel() {
    _cancelRequested = true;
  }
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
}

abstract class AIProvider {
  String get name;
  List<ModelInfo> get availableModels;
  ProviderDescriptor get descriptor;
  ProviderCapabilities get capabilities => descriptor.capabilities;
  bool get isConnected;

  Future<void> connect(Map<String, String> credentials);
  void disconnect();
  Future<ConnectorHealth> checkHealth() async => ConnectorHealth(
    status: isConnected
        ? ConnectorHealthStatus.connected
        : ConnectorHealthStatus.unknown,
    message: isConnected ? 'Connected' : 'Not connected',
    checkedAt: DateTime.now(),
  );

  Future<List<ConnectorModelInfo>> refreshModels() async {
    return availableModels
        .map(
          (model) => ConnectorModelInfo(
            id: model.id,
            displayName: model.displayName,
            contextWindow: model.contextWindow,
            supportsTools: model.supportsTools,
            inputCostPer1k: model.inputCostPer1k,
            outputCostPer1k: model.outputCostPer1k,
          ),
        )
        .toList();
  }

  void cancelActiveRequest() {}

  Stream<ChatChunk> chat(
    List<ChatMessage> messages, {
    required String model,
    required List<ToolDefinition> tools,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 4096,
  });
}
