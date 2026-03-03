import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/logger.dart';
import '../models/spec_models.dart';
import 'connection_provider.dart';

const _uuid = Uuid();

class SpecNotifier extends Notifier<Spec?> {
  @override
  Spec? build() => null;

  void createSpec(String name) {
    state = Spec(
      id: _uuid.v4().substring(0, 8),
      name: name,
      createdAt: DateTime.now(),
    );
  }

  void updateContent(String content) {
    if (state == null) return;
    state = state!.copyWith(content: content);
  }

  /// Send the spec to AI and generate executable steps.
  Future<void> generatePlan() async {
    if (state == null || state!.content.isEmpty) return;

    state = state!.copyWith(status: SpecStatus.planning);

    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) {
      state = state!.copyWith(status: SpecStatus.draft);
      return;
    }

    try {
      final response = await service.sendOneShot(
        state!.content,
        systemPrompt: _planningSystemPrompt,
      );

      if (response == null || response.isEmpty) {
        state = state!.copyWith(status: SpecStatus.draft);
        return;
      }

      final steps = _parseSteps(response);
      state = state!.copyWith(
        steps: steps,
        status: SpecStatus.ready,
      );
    } catch (e) {
      Logger.error('Spec plan generation failed', e);
      state = state!.copyWith(status: SpecStatus.draft);
    }
  }

  /// Execute steps sequentially by sending each to the agent.
  Future<void> execute() async {
    if (state == null || state!.steps.isEmpty) return;

    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) return;

    state = state!.copyWith(status: SpecStatus.executing);

    for (int i = 0; i < state!.steps.length; i++) {
      final step = state!.steps[i];
      if (step.isCompleted) continue;

      // Mark current step as running
      _updateStep(step.id, (s) => s.copyWith(isRunning: true));

      try {
        final result = await service.sendMessage(step.executionPrompt);

        _updateStep(step.id, (s) => s.copyWith(
          isCompleted: true,
          isRunning: false,
          result: result ?? 'Completed',
        ));
      } catch (e) {
        _updateStep(step.id, (s) => s.copyWith(
          isRunning: false,
          error: e.toString(),
        ));
        state = state!.copyWith(status: SpecStatus.failed);
        return;
      }
    }

    state = state!.copyWith(
      status: SpecStatus.completed,
      completedAt: DateTime.now(),
    );
  }

  void pauseExecution() {
    if (state == null) return;
    // Mark any running step as not running
    final steps = state!.steps.map((s) {
      if (s.isRunning) return s.copyWith(isRunning: false);
      return s;
    }).toList();
    state = state!.copyWith(steps: steps, status: SpecStatus.ready);
  }

  void skipStep(String stepId) {
    _updateStep(stepId, (s) => s.copyWith(
      isCompleted: true,
      isRunning: false,
      result: 'Skipped',
    ));
  }

  Future<void> retryStep(String stepId) async {
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected || state == null) return;

    final step = state!.steps.firstWhere((s) => s.id == stepId);
    _updateStep(stepId, (s) => s.copyWith(isRunning: true, error: null));

    try {
      final result = await service.sendMessage(step.executionPrompt);
      _updateStep(stepId, (s) => s.copyWith(
        isCompleted: true,
        isRunning: false,
        result: result ?? 'Completed',
        error: null,
      ));
    } catch (e) {
      _updateStep(stepId, (s) => s.copyWith(
        isRunning: false,
        error: e.toString(),
      ));
    }
  }

  void removeStep(String stepId) {
    if (state == null) return;
    final steps = state!.steps.where((s) => s.id != stepId).toList();
    state = state!.copyWith(steps: steps);
  }

  void reorderSteps(int oldIndex, int newIndex) {
    if (state == null) return;
    final steps = List<SpecStep>.from(state!.steps);
    final item = steps.removeAt(oldIndex);
    steps.insert(newIndex, item);
    state = state!.copyWith(steps: steps);
  }

  void _updateStep(String id, SpecStep Function(SpecStep) updater) {
    if (state == null) return;
    final steps = state!.steps.map((s) {
      if (s.id == id) return updater(s);
      return s;
    }).toList();
    state = state!.copyWith(steps: steps);
  }

  List<SpecStep> _parseSteps(String response) {
    final steps = <SpecStep>[];
    final lines = response.split('\n');
    int order = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      // Match numbered steps: "1. description" or "- description"
      final match = RegExp(r'^(\d+\.\s*|- )(.+)').firstMatch(trimmed);
      if (match != null) {
        final description = match.group(2)!.trim();
        steps.add(SpecStep(
          id: _uuid.v4().substring(0, 8),
          description: description,
          executionPrompt: description,
          order: order++,
        ));
      }
    }

    // If no structured steps found, treat entire response as a single step
    if (steps.isEmpty && response.trim().isNotEmpty) {
      steps.add(SpecStep(
        id: _uuid.v4().substring(0, 8),
        description: response.trim().split('\n').first,
        executionPrompt: response.trim(),
        order: 0,
      ));
    }

    return steps;
  }

  static const _planningSystemPrompt = '''
You are a software architect. Given a specification, break it into a numbered list of executable implementation steps.

Rules:
- Each step should be a single, focused task that the AI agent can execute
- Steps should be in dependency order
- Each step should be actionable and specific
- Output ONLY the numbered list, nothing else
- Format: "1. Description of step"

Example output:
1. Create the data model class for UserProfile with name, email, and avatar fields
2. Add the UserProfile repository with CRUD operations
3. Create the UserProfile screen widget with form fields
4. Wire up the repository to the screen via Riverpod provider
5. Add input validation for email format and required fields
''';
}

final specProvider = NotifierProvider<SpecNotifier, Spec?>(
  SpecNotifier.new,
);
