import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/utils/logger.dart';
import '../models/agent_run.dart';
import '../models/edit_prediction.dart';
import 'agent_run_provider.dart';
import 'connection_provider.dart';
import 'editor_provider.dart';

class EditPredictionState {
  final EditPrediction? prediction;
  final bool isLoading;

  const EditPredictionState({this.prediction, this.isLoading = false});

  EditPredictionState copyWith({
    EditPrediction? prediction,
    bool? isLoading,
    bool clearPrediction = false,
  }) {
    return EditPredictionState(
      prediction: clearPrediction ? null : (prediction ?? this.prediction),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class EditPredictionNotifier extends Notifier<EditPredictionState> {
  Timer? _debounceTimer;
  Timer? _dismissTimer;
  String? _lastRequestId;

  @override
  EditPredictionState build() => const EditPredictionState();

  /// Called when a file is saved. Debounces before predicting.
  void onFileSaved({
    required String filePath,
    required String content,
    required String savedContent,
    required String language,
    required List<String> openTabPaths,
  }) {
    _debounceTimer?.cancel();
    _lastRequestId = null;

    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      _predictNextEdit(
        filePath: filePath,
        content: content,
        savedContent: savedContent,
        language: language,
        openTabPaths: openTabPaths,
      );
    });
  }

  Future<void> _predictNextEdit({
    required String filePath,
    required String content,
    required String savedContent,
    required String language,
    required List<String> openTabPaths,
  }) async {
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected || service.state.isProcessing) return;

    final requestId = '${filePath}_${DateTime.now().millisecondsSinceEpoch}';
    _lastRequestId = requestId;

    state = state.copyWith(isLoading: true);
    final runNotifier = ref.read(agentRunProvider.notifier);
    runNotifier.startRun(
      kind: AgentRunKind.editPrediction,
      model: service.state.model,
      message: 'Predicting next edit',
    );

    try {
      // Build a simple diff description
      final oldLines = savedContent.split('\n');
      final newLines = content.split('\n');
      final diffLines = <String>[];
      final maxLines = oldLines.length > newLines.length
          ? oldLines.length
          : newLines.length;
      for (var i = 0; i < maxLines && diffLines.length < 20; i++) {
        final oldLine = i < oldLines.length ? oldLines[i] : '';
        final newLine = i < newLines.length ? newLines[i] : '';
        if (oldLine != newLine) {
          if (oldLine.isNotEmpty) diffLines.add('- ${oldLine.trim()}');
          if (newLine.isNotEmpty) diffLines.add('+ ${newLine.trim()}');
        }
      }

      if (diffLines.isEmpty) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final openTabs = openTabPaths
          .where((t) => t != filePath && !t.startsWith('circuit://'))
          .map((t) => p.basename(t))
          .take(10)
          .join(', ');

      final prompt =
          '''Based on this code edit, predict where the user will likely need to edit next.

File: ${p.basename(filePath)} ($language)

Recent changes:
${diffLines.join('\n')}

${openTabs.isNotEmpty ? 'Open files: $openTabs' : ''}

Respond with ONLY a JSON object (no markdown, no explanation):
{"filePath": "<relative or basename>", "line": <number>, "description": "<what needs updating>", "confidence": <0.0-1.0>, "reasoning": "<why>"}

If no clear prediction, respond with: {"confidence": 0.0}''';

      final response = await service.sendOneShot(prompt);

      if (_lastRequestId != requestId) return;

      if (response != null) {
        try {
          // Strip markdown fences if present
          var cleaned = response.trim();
          if (cleaned.startsWith('```')) {
            cleaned = cleaned
                .replaceFirst(RegExp(r'^```\w*\n?'), '')
                .replaceFirst(RegExp(r'\n?```$'), '');
          }

          final json = jsonDecode(cleaned) as Map<String, dynamic>;
          final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;

          if (confidence > 0.6) {
            final prediction = EditPrediction(
              filePath: json['filePath'] as String? ?? filePath,
              line: (json['line'] as num?)?.toInt() ?? 1,
              description: json['description'] as String? ?? '',
              confidence: confidence,
              reasoning: json['reasoning'] as String? ?? '',
              createdAt: DateTime.now(),
            );

            state = EditPredictionState(prediction: prediction);
            runNotifier.finishRun(AgentRunKind.editPrediction);

            // Auto-dismiss after 30 seconds
            _dismissTimer?.cancel();
            _dismissTimer = Timer(const Duration(seconds: 30), dismiss);
            return;
          }
        } catch (e) {
          Logger.warning('Failed to parse prediction: $e', 'EditPrediction');
        }
      }

      state = state.copyWith(isLoading: false, clearPrediction: true);
      runNotifier.finishRun(AgentRunKind.editPrediction);
    } catch (e) {
      Logger.warning('Edit prediction error: $e', 'EditPrediction');
      runNotifier.finishRun(AgentRunKind.editPrediction, error: e.toString());
      if (_lastRequestId == requestId) {
        state = state.copyWith(isLoading: false, clearPrediction: true);
      }
    }
  }

  void dismiss() {
    _debounceTimer?.cancel();
    _dismissTimer?.cancel();
    _lastRequestId = null;
    state = const EditPredictionState();
  }

  /// Navigate to the predicted location.
  void navigateToPrediction() {
    final prediction = state.prediction;
    if (prediction == null) return;

    // Open the file and scroll to line via editor provider
    ref.read(editorProvider.notifier).openFile(prediction.filePath);
    dismiss();
  }
}

final editPredictionProvider =
    NotifierProvider<EditPredictionNotifier, EditPredictionState>(
      EditPredictionNotifier.new,
    );
