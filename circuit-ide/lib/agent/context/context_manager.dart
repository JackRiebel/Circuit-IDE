import '../../core/constants/app_constants.dart';
import '../../models/chat_message.dart';
import '../../enums/message_role.dart';

class ContextManager {
  final int maxTokens;
  final int reserveTokens;

  ContextManager({
    this.maxTokens = AppConstants.defaultContextWindow,
    this.reserveTokens = AppConstants.reserveTokens,
  });

  int get availableTokens => maxTokens - reserveTokens;

  int estimateTokens(String content) {
    return (content.length / AppConstants.charsPerToken).ceil();
  }

  /// Optimize messages to fit within context window
  List<ChatMessage> optimizeContext(List<ChatMessage> messages) {
    if (messages.isEmpty) return messages;

    int totalTokens = 0;
    for (final msg in messages) {
      totalTokens += estimateTokens(msg.content);
    }

    if (totalTokens <= availableTokens) return messages;

    // Keep system messages, first user message, and recent messages
    final optimized = <ChatMessage>[];
    final systemMsgs =
        messages.where((m) => m.role == MessageRole.system).toList();
    final nonSystem =
        messages.where((m) => m.role != MessageRole.system).toList();

    // Always keep system messages
    optimized.addAll(systemMsgs);
    int used = systemMsgs.fold(0, (sum, m) => sum + estimateTokens(m.content));

    // Add messages from the end (most recent first)
    final reversed = nonSystem.reversed.toList();
    final kept = <ChatMessage>[];

    for (final msg in reversed) {
      final tokens = estimateTokens(msg.content);
      if (used + tokens > availableTokens) {
        // Compress tool results that are too long
        if (msg.role == MessageRole.tool && msg.content.length > 1000) {
          final compressed = compressToolResult(msg.content);
          final compressedTokens = estimateTokens(compressed);
          if (used + compressedTokens <= availableTokens) {
            kept.add(msg.copyWith(content: compressed));
            used += compressedTokens;
          }
          continue;
        }
        break; // Stop adding messages
      }
      kept.add(msg);
      used += tokens;
    }

    optimized.addAll(kept.reversed);
    return optimized;
  }

  String compressToolResult(String result, {int maxLength = 1000}) {
    if (result.length <= maxLength) return result;

    final halfLen = maxLength ~/ 2 - 20;
    return '${result.substring(0, halfLen)}\n'
        '... (${result.length - maxLength} chars truncated) ...\n'
        '${result.substring(result.length - halfLen)}';
  }
}
