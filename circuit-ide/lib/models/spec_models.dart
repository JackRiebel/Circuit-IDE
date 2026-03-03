enum SpecStatus { draft, planning, ready, executing, completed, failed }

class SpecStep {
  final String id;
  final String description;
  final String executionPrompt;
  final bool isCompleted;
  final bool isRunning;
  final String? result;
  final String? error;
  final int order;

  const SpecStep({
    required this.id,
    required this.description,
    required this.executionPrompt,
    this.isCompleted = false,
    this.isRunning = false,
    this.result,
    this.error,
    required this.order,
  });

  SpecStep copyWith({
    String? description,
    String? executionPrompt,
    bool? isCompleted,
    bool? isRunning,
    String? result,
    String? error,
    int? order,
  }) {
    return SpecStep(
      id: id,
      description: description ?? this.description,
      executionPrompt: executionPrompt ?? this.executionPrompt,
      isCompleted: isCompleted ?? this.isCompleted,
      isRunning: isRunning ?? this.isRunning,
      result: result ?? this.result,
      error: error,
      order: order ?? this.order,
    );
  }
}

class Spec {
  final String id;
  final String name;
  final String content;
  final List<SpecStep> steps;
  final SpecStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;

  const Spec({
    required this.id,
    required this.name,
    this.content = '',
    this.steps = const [],
    this.status = SpecStatus.draft,
    required this.createdAt,
    this.completedAt,
  });

  Spec copyWith({
    String? name,
    String? content,
    List<SpecStep>? steps,
    SpecStatus? status,
    DateTime? completedAt,
  }) {
    return Spec(
      id: id,
      name: name ?? this.name,
      content: content ?? this.content,
      steps: steps ?? this.steps,
      status: status ?? this.status,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  int get completedCount => steps.where((s) => s.isCompleted).length;
  double get progress =>
      steps.isEmpty ? 0 : completedCount / steps.length;
}
