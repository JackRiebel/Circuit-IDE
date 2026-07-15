import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlanStep {
  final String id;
  final String description;
  final bool isCompleted;
  final bool isRunning;
  final String? result;
  final int order;

  const PlanStep({
    required this.id,
    required this.description,
    this.isCompleted = false,
    this.isRunning = false,
    this.result,
    required this.order,
  });

  PlanStep copyWith({
    String? description,
    bool? isCompleted,
    bool? isRunning,
    String? result,
    int? order,
  }) {
    return PlanStep(
      id: id,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      isRunning: isRunning ?? this.isRunning,
      result: result ?? this.result,
      order: order ?? this.order,
    );
  }
}

class PlanModeState {
  final bool isActive;
  final List<PlanStep> steps;
  final bool isExecuting;
  final int currentStepIndex;

  const PlanModeState({
    this.isActive = false,
    this.steps = const [],
    this.isExecuting = false,
    this.currentStepIndex = -1,
  });

  PlanModeState copyWith({
    bool? isActive,
    List<PlanStep>? steps,
    bool? isExecuting,
    int? currentStepIndex,
  }) {
    return PlanModeState(
      isActive: isActive ?? this.isActive,
      steps: steps ?? this.steps,
      isExecuting: isExecuting ?? this.isExecuting,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
    );
  }

  int get completedCount => steps.where((s) => s.isCompleted).length;
  double get progress => steps.isEmpty ? 0 : completedCount / steps.length;
}

class PlanModeNotifier extends Notifier<PlanModeState> {
  @override
  PlanModeState build() => const PlanModeState();

  void activate(List<PlanStep> steps) {
    state = PlanModeState(isActive: true, steps: steps);
  }

  void deactivate() {
    state = const PlanModeState();
  }

  void completeStep(String stepId, {String? result}) {
    final updated = state.steps.map((s) {
      if (s.id == stepId) {
        return s.copyWith(isCompleted: true, isRunning: false, result: result);
      }
      return s;
    }).toList();
    state = state.copyWith(steps: updated);
  }

  void startStep(String stepId) {
    final updated = state.steps.map((s) {
      if (s.id == stepId) return s.copyWith(isRunning: true);
      return s.copyWith(isRunning: false);
    }).toList();
    final index = updated.indexWhere((s) => s.id == stepId);
    state = state.copyWith(steps: updated, currentStepIndex: index);
  }

  void removeStep(String stepId) {
    final updated = state.steps.where((s) => s.id != stepId).toList();
    state = state.copyWith(steps: updated);
  }

  void reorderSteps(int oldIndex, int newIndex) {
    final steps = List<PlanStep>.from(state.steps);
    final item = steps.removeAt(oldIndex);
    steps.insert(newIndex, item);
    state = state.copyWith(steps: steps);
  }

  void setExecuting(bool value) {
    state = state.copyWith(isExecuting: value);
  }
}

final planModeProvider = NotifierProvider<PlanModeNotifier, PlanModeState>(
  PlanModeNotifier.new,
);
