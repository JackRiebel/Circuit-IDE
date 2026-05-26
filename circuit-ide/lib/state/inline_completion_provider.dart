import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/logger.dart';
import '../models/agent_run.dart';
import 'agent_run_provider.dart';
import 'connection_provider.dart';

class InlineCompletionState {
  final String? suggestion;
  final int cursorLine;
  final int cursorColumn;
  final bool isLoading;
  final bool isVisible;

  const InlineCompletionState({
    this.suggestion,
    this.cursorLine = 0,
    this.cursorColumn = 0,
    this.isLoading = false,
    this.isVisible = false,
  });

  InlineCompletionState copyWith({
    String? suggestion,
    int? cursorLine,
    int? cursorColumn,
    bool? isLoading,
    bool? isVisible,
  }) {
    return InlineCompletionState(
      suggestion: suggestion ?? this.suggestion,
      cursorLine: cursorLine ?? this.cursorLine,
      cursorColumn: cursorColumn ?? this.cursorColumn,
      isLoading: isLoading ?? this.isLoading,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}

class InlineCompletionNotifier extends Notifier<InlineCompletionState> {
  Timer? _debounceTimer;
  String? _lastRequestId;

  @override
  InlineCompletionState build() => const InlineCompletionState();

  /// Called when the user pauses typing. Debounces and requests a completion.
  void onCursorChange({
    required String filePath,
    required String fileContent,
    required int line,
    required int column,
    required String language,
  }) {
    // Cancel any pending request
    _debounceTimer?.cancel();
    _lastRequestId = null;

    // Don't show if already visible with same position
    if (state.isVisible &&
        state.cursorLine == line &&
        state.cursorColumn == column) {
      return;
    }

    // Dismiss current suggestion
    if (state.isVisible) dismiss();

    // Debounce — wait 800ms of no typing before requesting
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      _requestCompletion(
        filePath: filePath,
        fileContent: fileContent,
        line: line,
        column: column,
        language: language,
      );
    });
  }

  Future<void> _requestCompletion({
    required String filePath,
    required String fileContent,
    required int line,
    required int column,
    required String language,
  }) async {
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) return;

    // Don't interfere with active chat
    if (service.state.isProcessing) return;

    final requestId =
        '${line}_${column}_${DateTime.now().millisecondsSinceEpoch}';
    _lastRequestId = requestId;

    state = state.copyWith(
      isLoading: true,
      cursorLine: line,
      cursorColumn: column,
    );
    final runNotifier = ref.read(agentRunProvider.notifier);
    runNotifier.startRun(
      kind: AgentRunKind.inlineCompletion,
      model: service.state.model,
      message: 'Inline completion requested',
    );

    try {
      // Extract context around the cursor (up to 50 lines before, 10 after)
      final lines = fileContent.split('\n');
      final startLine = (line - 50).clamp(0, lines.length);
      final endLine = (line + 10).clamp(0, lines.length);
      final contextBefore = lines.sublist(startLine, line).join('\n');
      final currentLine = line < lines.length
          ? lines[line].substring(0, column.clamp(0, lines[line].length))
          : '';
      final contextAfter = line + 1 < endLine
          ? lines.sublist(line + 1, endLine).join('\n')
          : '';

      // Build a focused completion prompt
      final prompt =
          'Complete the code at the cursor position. Return ONLY the completion text (the code that should be inserted), nothing else. No markdown, no explanation, no backticks.\n\n'
          'File: $filePath ($language)\n'
          'Code before cursor:\n```\n$contextBefore\n$currentLine\n```\n'
          '--- CURSOR IS HERE ---\n'
          '${contextAfter.isNotEmpty ? 'Code after cursor:\n```\n$contextAfter\n```\n' : ''}'
          '\nComplete from the cursor position:';

      // Use a lightweight approach — send as a message but don't add to chat history
      final response = await service.sendOneShot(prompt);

      // Check if this request is still current
      if (_lastRequestId != requestId) return;

      if (response != null && response.trim().isNotEmpty) {
        // Clean up the response — strip markdown code blocks if present
        var suggestion = response.trim();
        if (suggestion.startsWith('```')) {
          suggestion = suggestion
              .replaceFirst(RegExp(r'^```\w*\n?'), '')
              .replaceFirst(RegExp(r'\n?```$'), '');
        }

        // Only show short suggestions (1-3 lines max for inline)
        final suggestionLines = suggestion.split('\n');
        if (suggestionLines.length > 3) {
          suggestion = suggestionLines.take(3).join('\n');
        }

        if (suggestion.isNotEmpty) {
          state = InlineCompletionState(
            suggestion: suggestion,
            cursorLine: line,
            cursorColumn: column,
            isLoading: false,
            isVisible: true,
          );
          runNotifier.finishRun(AgentRunKind.inlineCompletion);
          return;
        }
      }

      state = state.copyWith(isLoading: false);
      runNotifier.finishRun(AgentRunKind.inlineCompletion);
    } catch (e) {
      Logger.warning('Inline completion error: $e', 'InlineCompletion');
      runNotifier.finishRun(AgentRunKind.inlineCompletion, error: e.toString());
      if (_lastRequestId == requestId) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  void showSuggestion(String suggestion, int line, int column) {
    state = InlineCompletionState(
      suggestion: suggestion,
      cursorLine: line,
      cursorColumn: column,
      isVisible: true,
    );
  }

  void accept() {
    // The editor will read the suggestion and insert it
    dismiss();
  }

  void dismiss() {
    _debounceTimer?.cancel();
    _lastRequestId = null;
    state = const InlineCompletionState();
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }
}

final inlineCompletionProvider =
    NotifierProvider<InlineCompletionNotifier, InlineCompletionState>(
      InlineCompletionNotifier.new,
    );
