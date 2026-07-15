import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/utils/logger.dart';
import '../models/test_generation_models.dart';
import '../services/test_generator_service.dart';
import 'connection_provider.dart';
import 'editor_provider.dart';

class TestGenerationState {
  final TestGenerationResult? result;
  final bool isGenerating;
  final String? error;
  final TestFramework? selectedFramework;
  final bool includeEdgeCases;
  final bool includeMocks;
  final List<String> history;

  const TestGenerationState({
    this.result,
    this.isGenerating = false,
    this.error,
    this.selectedFramework,
    this.includeEdgeCases = true,
    this.includeMocks = true,
    this.history = const [],
  });

  TestGenerationState copyWith({
    TestGenerationResult? result,
    bool? isGenerating,
    String? error,
    TestFramework? selectedFramework,
    bool? includeEdgeCases,
    bool? includeMocks,
    List<String>? history,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return TestGenerationState(
      result: clearResult ? null : (result ?? this.result),
      isGenerating: isGenerating ?? this.isGenerating,
      error: clearError ? null : (error ?? this.error),
      selectedFramework: selectedFramework ?? this.selectedFramework,
      includeEdgeCases: includeEdgeCases ?? this.includeEdgeCases,
      includeMocks: includeMocks ?? this.includeMocks,
      history: history ?? this.history,
    );
  }
}

class TestGenerationNotifier extends Notifier<TestGenerationState> {
  @override
  TestGenerationState build() => const TestGenerationState();

  void setFramework(TestFramework framework) {
    state = state.copyWith(selectedFramework: framework);
  }

  void setIncludeEdgeCases(bool value) {
    state = state.copyWith(includeEdgeCases: value);
  }

  void setIncludeMocks(bool value) {
    state = state.copyWith(includeMocks: value);
  }

  /// Generate tests for the given source file.
  Future<void> generate(String sourceFilePath) async {
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) {
      state = state.copyWith(error: 'Not connected to AI');
      return;
    }

    state = state.copyWith(
      isGenerating: true,
      clearError: true,
      clearResult: true,
    );

    try {
      final file = File(sourceFilePath);
      if (!await file.exists()) {
        state = state.copyWith(
          isGenerating: false,
          error: 'Source file not found',
        );
        return;
      }

      final sourceContent = await file.readAsString();
      final ext = p.extension(sourceFilePath).replaceFirst('.', '');
      final language = _extToLanguage(ext);
      final framework =
          state.selectedFramework ??
          TestGeneratorService.detectFramework(language);

      final request = TestGenerationRequest(
        sourceFilePath: sourceFilePath,
        sourceContent: sourceContent,
        language: language,
        framework: framework,
        includeEdgeCases: state.includeEdgeCases,
        includeMocks: state.includeMocks,
      );

      final prompt = TestGeneratorService.buildPrompt(request);
      final response = await service.sendOneShot(prompt);

      if (response == null || response.trim().isEmpty) {
        state = state.copyWith(
          isGenerating: false,
          error: 'No response from AI',
        );
        return;
      }

      final testContent = TestGeneratorService.parseResponse(response);
      final testPath = TestGeneratorService.deriveTestPath(
        sourceFilePath,
        language,
      );
      final testCount = TestGeneratorService.countTests(testContent, framework);

      state = state.copyWith(
        isGenerating: false,
        result: TestGenerationResult(
          testFilePath: testPath,
          testContent: testContent,
          testCount: testCount,
          summary:
              '$testCount tests generated for ${p.basename(sourceFilePath)}',
        ),
        selectedFramework: framework,
      );
    } catch (e) {
      Logger.error('Test generation failed', e);
      state = state.copyWith(isGenerating: false, error: e.toString());
    }
  }

  /// Save the generated test file and open it in the editor.
  Future<void> saveAndOpen() async {
    final result = state.result;
    if (result == null) return;

    try {
      final file = File(result.testFilePath);
      final dir = Directory(p.dirname(result.testFilePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(result.testContent);

      // Track in history
      final newHistory = [
        result.testFilePath,
        ...state.history.where((h) => h != result.testFilePath),
      ].take(20).toList();
      state = state.copyWith(history: newHistory);

      // Open in editor
      ref.read(editorProvider.notifier).openFile(result.testFilePath);
    } catch (e) {
      Logger.error('Failed to save test file', e);
      state = state.copyWith(error: 'Failed to save: $e');
    }
  }

  String _extToLanguage(String ext) {
    return switch (ext) {
      'dart' => 'dart',
      'py' => 'python',
      'js' => 'javascript',
      'ts' || 'tsx' => 'typescript',
      'go' => 'go',
      'rs' => 'rust',
      'java' => 'java',
      'rb' => 'ruby',
      _ => ext,
    };
  }
}

final testGenerationProvider =
    NotifierProvider<TestGenerationNotifier, TestGenerationState>(
      TestGenerationNotifier.new,
    );
