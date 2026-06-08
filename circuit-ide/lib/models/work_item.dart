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

enum WorkItemArtifactType {
  context,
  patchSet,
  commandRun,
  checkpoint,
  verification,
  handoff,
}

class WorkItemArtifact {
  final String id;
  final WorkItemArtifactType type;
  final String title;
  final String detail;
  final DateTime createdAt;

  const WorkItemArtifact({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'detail': detail,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static WorkItemArtifact? fromJson(Map<String, dynamic> json) {
    try {
      return WorkItemArtifact(
        id: json['id'] as String,
        type: WorkItemArtifactType.values.firstWhere(
          (value) => value.name == json['type'],
          orElse: () => WorkItemArtifactType.context,
        ),
        title: json['title'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'detail': detail,
      'completed': completed,
      'running': running,
      'result': result,
      'error': error,
    };
  }

  static WorkItemStep? fromJson(Map<String, dynamic> json) {
    try {
      return WorkItemStep(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        completed: json['completed'] as bool? ?? false,
        running: json['running'] as bool? ?? false,
        result: json['result'] as String?,
        error: json['error'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class WorkItem {
  final String id;
  final String prompt;
  final WorkItemStatus status;
  final List<WorkItemStep> steps;
  final String? activeRunId;
  final List<String> contextPreview;
  final List<String> patchSetIds;
  final List<String> commandRunIds;
  final List<String> checkpointIds;
  final List<WorkItemArtifact> artifacts;
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
    this.contextPreview = const [],
    this.patchSetIds = const [],
    this.commandRunIds = const [],
    this.checkpointIds = const [],
    this.artifacts = const [],
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
    List<String>? contextPreview,
    List<String>? patchSetIds,
    List<String>? commandRunIds,
    List<String>? checkpointIds,
    List<WorkItemArtifact>? artifacts,
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
      contextPreview: contextPreview ?? this.contextPreview,
      patchSetIds: patchSetIds ?? this.patchSetIds,
      commandRunIds: commandRunIds ?? this.commandRunIds,
      checkpointIds: checkpointIds ?? this.checkpointIds,
      artifacts: artifacts ?? this.artifacts,
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'prompt': prompt,
      'status': status.name,
      'steps': steps.map((step) => step.toJson()).toList(),
      'activeRunId': activeRunId,
      'contextPreview': contextPreview,
      'patchSetIds': patchSetIds,
      'commandRunIds': commandRunIds,
      'checkpointIds': checkpointIds,
      'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
      'changedFiles': changedFiles,
      'verificationCommands': verificationCommands
          .map(
            (command) => {
              'id': command.id,
              'name': command.name,
              'command': command.command,
              'source': command.source,
              'enabled': command.enabled,
              'timeoutSeconds': command.timeoutSeconds,
            },
          )
          .toList(),
      'verificationResults': verificationResults
          .map(
            (result) => {
              'command': result.command,
              'passed': result.passed,
              'exitCode': result.exitCode,
              'durationMs': result.duration.inMilliseconds,
              'output': result.output,
            },
          )
          .toList(),
      'result': result,
      'suggestedNextSteps': suggestedNextSteps,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  static WorkItem? fromJson(Map<String, dynamic> json) {
    try {
      return WorkItem(
        id: json['id'] as String,
        prompt: json['prompt'] as String? ?? '',
        status: WorkItemStatus.values.firstWhere(
          (value) => value.name == json['status'],
          orElse: () => WorkItemStatus.ready,
        ),
        steps: (json['steps'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(WorkItemStep.fromJson)
            .nonNulls
            .toList(),
        activeRunId: json['activeRunId'] as String?,
        contextPreview:
            (json['contextPreview'] as List<dynamic>?)?.cast<String>() ??
            const [],
        patchSetIds:
            (json['patchSetIds'] as List<dynamic>?)?.cast<String>() ?? const [],
        commandRunIds:
            (json['commandRunIds'] as List<dynamic>?)?.cast<String>() ??
            const [],
        checkpointIds:
            (json['checkpointIds'] as List<dynamic>?)?.cast<String>() ??
            const [],
        artifacts: (json['artifacts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(WorkItemArtifact.fromJson)
            .nonNulls
            .toList(),
        changedFiles:
            (json['changedFiles'] as List<dynamic>?)?.cast<String>() ??
            const [],
        verificationCommands:
            (json['verificationCommands'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>()
                .map(
                  (command) => ProjectCommand(
                    id: command['id'] as String? ?? '',
                    name: command['name'] as String? ?? '',
                    command: command['command'] as String? ?? '',
                    source: command['source'] as String? ?? '',
                    enabled: command['enabled'] as bool? ?? true,
                    timeoutSeconds: command['timeoutSeconds'] as int? ?? 120,
                  ),
                )
                .toList(),
        verificationResults:
            (json['verificationResults'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>()
                .map(
                  (result) => VerificationResultSummary(
                    command: result['command'] as String? ?? '',
                    passed: result['passed'] as bool? ?? false,
                    exitCode: result['exitCode'] as int? ?? 1,
                    duration: Duration(
                      milliseconds: result['durationMs'] as int? ?? 0,
                    ),
                    output: result['output'] as String? ?? '',
                  ),
                )
                .toList(),
        result: json['result'] as String?,
        suggestedNextSteps:
            (json['suggestedNextSteps'] as List<dynamic>?)?.cast<String>() ??
            const [],
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}

const _sentinel = Object();
