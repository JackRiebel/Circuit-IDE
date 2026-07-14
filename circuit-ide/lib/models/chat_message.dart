import '../enums/message_role.dart';
import 'tool_call_info.dart';

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<ToolCallInfo> toolCalls;
  final String? toolCallId;
  final bool isStreaming;
  final Map<String, dynamic> metadata;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolCalls = const [],
    this.toolCallId,
    this.isStreaming = false,
    this.metadata = const {},
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    List<ToolCallInfo>? toolCalls,
    String? toolCallId,
    bool? isStreaming,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
      isStreaming: isStreaming ?? this.isStreaming,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toApiMessage() {
    final msg = <String, dynamic>{'role': role.value, 'content': content};
    if (toolCallId != null) {
      msg['tool_call_id'] = toolCallId;
    }
    if (toolCalls.isNotEmpty) {
      msg['tool_calls'] = toolCalls
          .map(
            (tc) => {
              'id': tc.id,
              'type': 'function',
              'function': {'name': tc.name, 'arguments': tc.argumentsJson},
            },
          )
          .toList();
    }
    return msg;
  }
}
