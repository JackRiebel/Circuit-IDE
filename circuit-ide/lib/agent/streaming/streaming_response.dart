import 'dart:convert';

class StreamingToolCall {
  String id;
  String name;
  String argumentsBuffer;

  StreamingToolCall({
    required this.id,
    this.name = '',
    this.argumentsBuffer = '',
  });

  Map<String, dynamic> get arguments {
    if (argumentsBuffer.isEmpty) return {};
    try {
      return jsonDecode(argumentsBuffer) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  bool get isComplete {
    if (argumentsBuffer.isEmpty) return name.isNotEmpty;
    try {
      jsonDecode(argumentsBuffer);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class StreamingResponse {
  String content = '';
  final List<StreamingToolCall> toolCalls = [];
  String? finishReason;
  int promptTokens = 0;
  int completionTokens = 0;

  bool get hasToolCalls => toolCalls.isNotEmpty;
  bool get isDone => finishReason != null;
  int get totalTokens => promptTokens + completionTokens;

  void addContent(String chunk) {
    content += chunk;
  }

  void addToolCallChunk({
    required int index,
    String? id,
    String? name,
    String? arguments,
  }) {
    // Ensure list is large enough
    while (toolCalls.length <= index) {
      toolCalls.add(StreamingToolCall(id: ''));
    }

    final tc = toolCalls[index];
    if (id != null && id.isNotEmpty) tc.id = id;
    if (name != null && name.isNotEmpty) tc.name += name;
    if (arguments != null) tc.argumentsBuffer += arguments;
  }

  void setUsage(int prompt, int completion) {
    promptTokens = prompt;
    completionTokens = completion;
  }

  void updateUsage(int prompt, int completion) {
    if (prompt > 0) promptTokens = prompt;
    if (completion > 0) completionTokens = completion;
  }
}
