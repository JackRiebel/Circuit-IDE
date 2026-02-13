import 'dart:async';

import '../agent/providers/provider_interface.dart';
import '../core/utils/debouncer.dart';
import '../core/utils/logger.dart';
import '../enums/message_role.dart';
import '../models/chat_message.dart';

class CompletionService {
  final AIProvider provider;
  final Debouncer _debouncer =
      Debouncer(delay: const Duration(milliseconds: 300));

  CompletionService({required this.provider});

  /// Get inline code completion
  Future<String?> getCompletion({
    required String fileContent,
    required int cursorLine,
    required int cursorColumn,
    required String language,
    String? model,
  }) async {
    try {
      final lines = fileContent.split('\n');
      final beforeCursor = lines.sublist(0, cursorLine).join('\n');
      final afterCursor =
          lines.sublist(cursorLine).join('\n');

      final prompt =
          'Complete the following $language code. Only provide the completion text, nothing else.\n\n'
          '```$language\n$beforeCursor<CURSOR>$afterCursor\n```';

      String result = '';
      await for (final chunk in provider.chat(
        [
          ChatMessage(
            id: 'completion',
            role: MessageRole.user,
            content: prompt,
            timestamp: DateTime.now(),
          ),
        ],
        model: model ?? 'gpt-4o-mini',
        tools: [],
        maxTokens: 256,
        temperature: 0.3,
      )) {
        if (chunk.content != null) {
          result += chunk.content!;
        }
      }

      // Clean up the result
      result = result.trim();
      if (result.startsWith('```')) {
        final lines = result.split('\n');
        if (lines.length > 2) {
          result = lines.sublist(1, lines.length - 1).join('\n');
        }
      }

      return result.isEmpty ? null : result;
    } catch (e) {
      Logger.error('Completion error', e);
      return null;
    }
  }

  void requestCompletion({
    required String fileContent,
    required int cursorLine,
    required int cursorColumn,
    required String language,
    required void Function(String? completion) onResult,
  }) {
    _debouncer.call(() async {
      final result = await getCompletion(
        fileContent: fileContent,
        cursorLine: cursorLine,
        cursorColumn: cursorColumn,
        language: language,
      );
      onResult(result);
    });
  }

  void dispose() {
    _debouncer.dispose();
  }
}
