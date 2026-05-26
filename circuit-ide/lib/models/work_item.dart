import 'project_profile.dart';

enum WorkItemStatus {
  idle,
  planning,
  ready,
  running,
  verifying,
  completed,
  failed,
  cancelled,
}

class WorkItemStep {
  final String id;
  final String title;
  final String detail;
  final bool completed;
  final bool running;
  final String? result;
  final String? error;

  const WorkItemStep({
    required this.id,
    required this.title,
    required this.detail,
    this.completed = false,
    this.running = false,
    this.result,
    this.error,
  });

  WorkItemStep copyWith({
    String? title,
    String? detail,
    bool? completed,
    bool? running,
    Object? result = _sentinel,
    Object? error = _sentinel,
  }) {
    return WorkItemStep(
      id: id,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      completed: completed ?? this.completed,
      running: running ?? this.running,
      result: identical(result, _sentinel) ? this.result : result as String?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

class WorkItem {
  final String id;
  final String prompt;
  final WorkItemStatus status;
  final List<WorkItemStep> steps;
  final String? activeRunId;
  final List<String> changedFiles;
  final List<ProjectCommand> verificationCommands;
  final List<VerificationResultSummary> verificationResults;
  final String? result;
  final List<String> suggestedNextSteps;
  final DateTime createdAt;
  final DateTime? completedAt;

  const WorkItem({
    required this.id,
    required this.prompt,
    this.status = WorkItemStatus.idle,
    this.steps = const [],
    this.activeRunId,
    this.changedFiles = const [],
    this.verificationCommands = const [],
    this.verificationResults = const [],
    this.result,
    this.suggestedNextSteps = const [],
    required this.createdAt,
    this.completedAt,
  });

  WorkItem copyWith({
    String? prompt,
    WorkItemStatus? status,
    List<WorkItemStep>? steps,
    Object? activeRunId = _sentinel,
    List<String>? changedFiles,
    List<ProjectCommand>? verificationCommands,
    List<VerificationResultSummary>? verificationResults,
    Object? result = _sentinel,
    List<String>? suggestedNextSteps,
    DateTime? completedAt,
  }) {
    return WorkItem(
      id: id,
      prompt: prompt ?? this.prompt,
      status: status ?? this.status,
      steps: steps ?? this.steps,
      activeRunId: identical(activeRunId, _sentinel)
          ? this.activeRunId
          : activeRunId as String?,
      changedFiles: changedFiles ?? this.changedFiles,
      verificationCommands: verificationCommands ?? this.verificationCommands,
      verificationResults: verificationResults ?? this.verificationResults,
      result: identical(result, _sentinel) ? this.result : result as String?,
      suggestedNextSteps: suggestedNextSteps ?? this.suggestedNextSteps,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  int get completedStepCount => steps.where((step) => step.completed).length;
}

const _sentinel = Object();
