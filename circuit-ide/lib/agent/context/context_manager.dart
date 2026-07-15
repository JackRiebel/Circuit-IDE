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

    final totalTokens = messages.fold<int>(
      0,
      (sum, msg) => sum + _messageTokenCost(msg),
    );

    if (totalTokens <= availableTokens) return messages;

    final budget = availableTokens.clamp(1, maxTokens).toInt();
    var used = 0;

    final systemMessages = messages
        .where((m) => m.role == MessageRole.system)
        .toList();
    final nonSystem = messages
        .where((m) => m.role != MessageRole.system)
        .toList();

    final groups = _contextGroups(nonSystem);
    if (groups.isEmpty) {
      return _fitSystemMessages(systemMessages, budget);
    }

    final selectedMessages = <ChatMessage>[];
    final selectedIds = <String>{};
    void addRequired(_ContextGroup? group) {
      if (group == null ||
          group.messages.any((message) => selectedIds.contains(message.id))) {
        return;
      }
      final compacted = _fitGroup(group, budget - used);
      if (compacted.messages.isEmpty) return;
      selectedMessages.addAll(compacted.messages);
      selectedIds.addAll(compacted.messages.map((message) => message.id));
      used += compacted.tokenCost(this);
    }

    addRequired(groups.last);
    addRequired(_firstUserGroup(groups));

    final selectedSystemMessages = <ChatMessage>[];
    for (final message in systemMessages) {
      final remaining = budget - used;
      if (remaining <= 0) break;
      final compacted = _fitMessage(message, remaining);
      if (_messageTokenCost(compacted) > remaining) continue;
      selectedSystemMessages.add(compacted);
      used += _messageTokenCost(compacted);
    }

    for (final group in groups.reversed) {
      if (group.messages.any((message) => selectedIds.contains(message.id)) ||
          used >= budget) {
        continue;
      }
      final cost = group.tokenCost(this);
      if (used + cost > budget) continue;
      selectedMessages.addAll(group.messages);
      selectedIds.addAll(group.messages.map((message) => message.id));
      used += cost;
    }

    final compactedById = {
      for (final message in selectedMessages) message.id: message,
    };
    return [
      ...selectedSystemMessages,
      ...nonSystem
          .where((message) => selectedIds.contains(message.id))
          .map((message) => compactedById[message.id] ?? message),
    ];
  }

  String compressToolResult(String result, {int maxLength = 1000}) {
    if (result.length <= maxLength) return result;
    if (maxLength < 80) {
      return result.substring(0, maxLength.clamp(0, result.length).toInt());
    }

    final halfLen = maxLength ~/ 2 - 20;
    return '${result.substring(0, halfLen)}\n'
        '... (${result.length - maxLength} chars truncated) ...\n'
        '${result.substring(result.length - halfLen)}';
  }

  List<ChatMessage> _fitSystemMessages(List<ChatMessage> messages, int budget) {
    final selected = <ChatMessage>[];
    var used = 0;
    for (final message in messages) {
      final remaining = budget - used;
      if (remaining <= 0) break;
      final compacted = _fitMessage(message, remaining);
      if (_messageTokenCost(compacted) > remaining) continue;
      selected.add(compacted);
      used += _messageTokenCost(compacted);
    }
    return selected;
  }

  int _messageTokenCost(ChatMessage message) {
    return estimateTokens(message.content) +
        message.toolCalls.fold<int>(
          0,
          (sum, call) => sum + estimateTokens(call.argumentsJson) + 8,
        );
  }

  List<_ContextGroup> _contextGroups(List<ChatMessage> messages) {
    final groups = <_ContextGroup>[];
    var index = 0;
    while (index < messages.length) {
      final message = messages[index];
      if (message.role == MessageRole.assistant &&
          message.toolCalls.isNotEmpty) {
        final toolCallIds = message.toolCalls.map((call) => call.id).toSet();
        final grouped = <ChatMessage>[message];
        var cursor = index + 1;
        while (cursor < messages.length &&
            messages[cursor].role == MessageRole.tool &&
            (messages[cursor].toolCallId == null ||
                toolCallIds.contains(messages[cursor].toolCallId))) {
          grouped.add(messages[cursor]);
          cursor += 1;
        }
        groups.add(_ContextGroup(grouped));
        index = cursor;
        continue;
      }

      if (message.role == MessageRole.tool) {
        // Avoid sending orphaned tool results after compaction. Providers expect
        // a tool result to follow the assistant tool call that requested it.
        index += 1;
        continue;
      }

      groups.add(_ContextGroup([message]));
      index += 1;
    }
    return groups;
  }

  _ContextGroup? _firstUserGroup(List<_ContextGroup> groups) {
    for (final group in groups) {
      if (group.messages.any((message) => message.role == MessageRole.user)) {
        return group;
      }
    }
    return null;
  }

  _ContextGroup _fitGroup(_ContextGroup group, int remainingTokens) {
    if (remainingTokens <= 0) return const _ContextGroup([]);
    if (group.messages.length == 1) {
      final message = _fitMessage(group.messages.single, remainingTokens);
      if (_messageTokenCost(message) > remainingTokens) {
        return const _ContextGroup([]);
      }
      return _ContextGroup([message]);
    }

    final messages = <ChatMessage>[];
    var used = 0;
    for (final message in group.messages) {
      final remaining = remainingTokens - used;
      if (remaining <= 0) break;
      final compacted = _fitMessage(message, remaining);
      if (_messageTokenCost(compacted) > remaining) {
        return const _ContextGroup([]);
      }
      messages.add(compacted);
      used += _messageTokenCost(compacted);
    }
    return messages.length == group.messages.length
        ? _ContextGroup(messages)
        : const _ContextGroup([]);
  }

  ChatMessage _fitMessage(ChatMessage message, int remainingTokens) {
    if (_messageTokenCost(message) <= remainingTokens) return message;
    final maxChars = (remainingTokens * AppConstants.charsPerToken).floor();
    if (message.role == MessageRole.tool) {
      return message.copyWith(
        content: compressToolResult(message.content, maxLength: maxChars),
      );
    }
    return message.copyWith(
      content: _middleTruncate(message.content, maxChars),
    );
  }

  String _middleTruncate(String content, int maxLength) {
    if (maxLength <= 0) return '';
    if (content.length <= maxLength) return content;
    if (maxLength < 80) return content.substring(0, maxLength);
    final marker =
        '\n... (${content.length - maxLength} chars truncated) ...\n';
    final side = ((maxLength - marker.length) / 2).floor();
    if (side <= 0) return content.substring(0, maxLength);
    return '${content.substring(0, side)}$marker'
        '${content.substring(content.length - side)}';
  }
}

class _ContextGroup {
  final List<ChatMessage> messages;

  const _ContextGroup(this.messages);

  int tokenCost(ContextManager manager) {
    return messages.fold<int>(
      0,
      (sum, message) => sum + manager._messageTokenCost(message),
    );
  }
}
