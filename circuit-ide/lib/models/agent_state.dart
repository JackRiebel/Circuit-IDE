import '../enums/connection_status.dart';
import 'chat_message.dart';
import 'token_usage.dart';
import 'cost_info.dart';

class AgentState {
  final ConnectionStatus connectionStatus;
  final String model;
  final String workingDir;
  final bool autoApprove;
  final bool thinkingMode;
  final bool streamResponses;
  final bool isProcessing;
  final bool isThinking;
  final List<ChatMessage> messages;
  final String? error;
  final TokenUsage tokenUsage;
  final TokenUsage lastTokenUsage;
  final CostInfo costInfo;

  const AgentState({
    this.connectionStatus = ConnectionStatus.disconnected,
    this.model = 'gpt-4.1',
    this.workingDir = '',
    this.autoApprove = false,
    this.thinkingMode = false,
    this.streamResponses = true,
    this.isProcessing = false,
    this.isThinking = false,
    this.messages = const [],
    this.error,
    this.tokenUsage = const TokenUsage(),
    this.lastTokenUsage = const TokenUsage(),
    this.costInfo = const CostInfo(),
  });

  AgentState copyWith({
    ConnectionStatus? connectionStatus,
    String? model,
    String? workingDir,
    bool? autoApprove,
    bool? thinkingMode,
    bool? streamResponses,
    bool? isProcessing,
    bool? isThinking,
    List<ChatMessage>? messages,
    String? error,
    TokenUsage? tokenUsage,
    TokenUsage? lastTokenUsage,
    CostInfo? costInfo,
  }) {
    return AgentState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      model: model ?? this.model,
      workingDir: workingDir ?? this.workingDir,
      autoApprove: autoApprove ?? this.autoApprove,
      thinkingMode: thinkingMode ?? this.thinkingMode,
      streamResponses: streamResponses ?? this.streamResponses,
      isProcessing: isProcessing ?? this.isProcessing,
      isThinking: isThinking ?? this.isThinking,
      messages: messages ?? this.messages,
      error: error,
      tokenUsage: tokenUsage ?? this.tokenUsage,
      lastTokenUsage: lastTokenUsage ?? this.lastTokenUsage,
      costInfo: costInfo ?? this.costInfo,
    );
  }
}
