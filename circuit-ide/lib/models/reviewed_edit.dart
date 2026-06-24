enum ProposedFileEditType { create, modify, delete }

enum PatchApplyStatus { applied, restored, rejected, conflict, failed }

enum PatchApprovalStatus { proposed, approved, rejected, revisionRequested }

enum ToolApprovalPolicy { reviewWrites, autoApproveReadOnly, autoApproveAll }

class PlannedFileTarget {
  final String path;
  final String intent;
  final ProposedFileEditType? operation;

  const PlannedFileTarget({
    required this.path,
    required this.intent,
    this.operation,
  });

  factory PlannedFileTarget.fromDisplayString(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const PlannedFileTarget(path: '', intent: '');
    }
    final separatorMatch = RegExp(r'\s(?:—|-|–|:)\s').firstMatch(trimmed);
    if (separatorMatch == null) {
      return PlannedFileTarget(path: trimmed, intent: '');
    }
    return PlannedFileTarget(
      path: trimmed.substring(0, separatorMatch.start).trim(),
      intent: trimmed.substring(separatorMatch.end).trim(),
    );
  }

  String get displayString {
    final intentText = intent.trim();
    return intentText.isEmpty ? path : '$path — $intentText';
  }

  String get contractString {
    final operationText = operation == null ? '' : ' [${operation!.name}]';
    final intentText = intent.trim();
    return intentText.isEmpty
        ? '$path$operationText'
        : '$path$operationText — $intentText';
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'intent': intent,
    if (operation != null) 'operation': operation!.name,
  };

  static PlannedFileTarget? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      final operationName = json['operation'] as String?;
      return PlannedFileTarget(
        path: json['path'] as String? ?? '',
        intent: json['intent'] as String? ?? '',
        operation: operationName == null
            ? null
            : ProposedFileEditType.values.firstWhere(
                (candidate) => candidate.name == operationName,
                orElse: () => ProposedFileEditType.create,
              ),
      );
    } catch (_) {
      return null;
    }
  }
}

class ProposedFileEdit {
  final String path;
  final ProposedFileEditType type;
  final String? before;
  final String? after;
  final String? unifiedDiff;
  final PatchApplyStatus? applyStatus;
  final String? conflictMessage;

  const ProposedFileEdit({
    required this.path,
    required this.type,
    this.before,
    this.after,
    this.unifiedDiff,
    this.applyStatus,
    this.conflictMessage,
  });

  bool get requiresApproval =>
      type != ProposedFileEditType.modify || before != after;

  Map<String, dynamic> toJson() => {
    'path': path,
    'type': type.name,
    'before': before,
    'after': after,
    'unifiedDiff': unifiedDiff,
    'applyStatus': applyStatus?.name,
    'conflictMessage': conflictMessage,
  };

  static ProposedFileEdit? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      final typeName = json['type'] as String?;
      final statusName = json['applyStatus'] as String?;
      return ProposedFileEdit(
        path: json['path'] as String? ?? '',
        type: ProposedFileEditType.values.firstWhere(
          (candidate) => candidate.name == typeName,
          orElse: () => ProposedFileEditType.modify,
        ),
        before: json['before'] as String?,
        after: json['after'] as String?,
        unifiedDiff: json['unifiedDiff'] as String?,
        applyStatus: statusName == null
            ? null
            : PatchApplyStatus.values.firstWhere(
                (candidate) => candidate.name == statusName,
                orElse: () => PatchApplyStatus.failed,
              ),
        conflictMessage: json['conflictMessage'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class ProposedPatchSet {
  final String id;
  final String title;
  final String? workItemId;
  final String? agentTaskId;
  final String? runId;
  final String? comparisonSummary;
  final String? supersededBy;
  final List<ProposedFileEdit> edits;
  final DateTime createdAt;
  final String? checkpointId;
  final PatchApprovalStatus approvalStatus;
  final PatchApplyStatus? applyStatus;
  final String? conflictMessage;
  final String? revisionPrompt;
  final List<String> changedFiles;
  final String? diffSummary;
  final List<String> verificationSuggestions;
  final bool verificationRequested;
  final String? planMarkdown;
  final List<String> plannedFiles;
  final List<PlannedFileTarget> plannedTargets;

  const ProposedPatchSet({
    required this.id,
    required this.title,
    this.workItemId,
    this.agentTaskId,
    this.runId,
    this.comparisonSummary,
    this.supersededBy,
    required this.edits,
    required this.createdAt,
    this.checkpointId,
    this.approvalStatus = PatchApprovalStatus.proposed,
    this.applyStatus,
    this.conflictMessage,
    this.revisionPrompt,
    this.changedFiles = const [],
    this.diffSummary,
    this.verificationSuggestions = const [],
    this.verificationRequested = false,
    this.planMarkdown,
    this.plannedFiles = const [],
    this.plannedTargets = const [],
  });

  List<PlannedFileTarget> get effectivePlannedTargets =>
      plannedTargets.isNotEmpty
      ? plannedTargets
      : [
          for (final file in plannedFiles)
            PlannedFileTarget.fromDisplayString(file),
        ];

  bool get isEmpty =>
      edits.isEmpty && plannedFiles.isEmpty && plannedTargets.isEmpty;
  bool get isPlanOnly =>
      edits.isEmpty && (plannedFiles.isNotEmpty || plannedTargets.isNotEmpty);
  int get fileCount => edits.isNotEmpty
      ? edits.length
      : effectivePlannedTargets
            .where((target) => target.path.isNotEmpty)
            .length;

  ProposedPatchSet copyWith({
    String? workItemId,
    String? agentTaskId,
    String? runId,
    Object? comparisonSummary = _sentinel,
    Object? supersededBy = _sentinel,
    String? checkpointId,
    PatchApprovalStatus? approvalStatus,
    Object? applyStatus = _sentinel,
    Object? conflictMessage = _sentinel,
    Object? revisionPrompt = _sentinel,
    List<String>? changedFiles,
    Object? diffSummary = _sentinel,
    List<String>? verificationSuggestions,
    bool? verificationRequested,
    Object? planMarkdown = _sentinel,
    List<String>? plannedFiles,
    List<PlannedFileTarget>? plannedTargets,
  }) {
    return ProposedPatchSet(
      id: id,
      title: title,
      workItemId: workItemId ?? this.workItemId,
      agentTaskId: agentTaskId ?? this.agentTaskId,
      runId: runId ?? this.runId,
      comparisonSummary: identical(comparisonSummary, _sentinel)
          ? this.comparisonSummary
          : comparisonSummary as String?,
      supersededBy: identical(supersededBy, _sentinel)
          ? this.supersededBy
          : supersededBy as String?,
      edits: edits,
      createdAt: createdAt,
      checkpointId: checkpointId ?? this.checkpointId,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      applyStatus: identical(applyStatus, _sentinel)
          ? this.applyStatus
          : applyStatus as PatchApplyStatus?,
      conflictMessage: identical(conflictMessage, _sentinel)
          ? this.conflictMessage
          : conflictMessage as String?,
      revisionPrompt: identical(revisionPrompt, _sentinel)
          ? this.revisionPrompt
          : revisionPrompt as String?,
      changedFiles: changedFiles ?? this.changedFiles,
      diffSummary: identical(diffSummary, _sentinel)
          ? this.diffSummary
          : diffSummary as String?,
      verificationSuggestions:
          verificationSuggestions ?? this.verificationSuggestions,
      verificationRequested:
          verificationRequested ?? this.verificationRequested,
      planMarkdown: identical(planMarkdown, _sentinel)
          ? this.planMarkdown
          : planMarkdown as String?,
      plannedFiles: plannedFiles ?? this.plannedFiles,
      plannedTargets: plannedTargets ?? this.plannedTargets,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'workItemId': workItemId,
    'agentTaskId': agentTaskId,
    'runId': runId,
    'comparisonSummary': comparisonSummary,
    'supersededBy': supersededBy,
    'edits': edits.map((edit) => edit.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'checkpointId': checkpointId,
    'approvalStatus': approvalStatus.name,
    'applyStatus': applyStatus?.name,
    'conflictMessage': conflictMessage,
    'revisionPrompt': revisionPrompt,
    'changedFiles': changedFiles,
    'diffSummary': diffSummary,
    'verificationSuggestions': verificationSuggestions,
    'verificationRequested': verificationRequested,
    'planMarkdown': planMarkdown,
    'plannedFiles': plannedFiles,
    'plannedTargets': plannedTargets.map((target) => target.toJson()).toList(),
  };

  static ProposedPatchSet? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      final approvalName = json['approvalStatus'] as String?;
      final applyName = json['applyStatus'] as String?;
      return ProposedPatchSet(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Patch proposal',
        workItemId: json['workItemId'] as String?,
        agentTaskId: json['agentTaskId'] as String?,
        runId: json['runId'] as String?,
        comparisonSummary: json['comparisonSummary'] as String?,
        supersededBy: json['supersededBy'] as String?,
        edits: (json['edits'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ProposedFileEdit.fromJson)
            .nonNulls
            .toList(),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        checkpointId: json['checkpointId'] as String?,
        approvalStatus: PatchApprovalStatus.values.firstWhere(
          (candidate) => candidate.name == approvalName,
          orElse: () => PatchApprovalStatus.proposed,
        ),
        applyStatus: applyName == null
            ? null
            : PatchApplyStatus.values.firstWhere(
                (candidate) => candidate.name == applyName,
                orElse: () => PatchApplyStatus.failed,
              ),
        conflictMessage: json['conflictMessage'] as String?,
        revisionPrompt: json['revisionPrompt'] as String?,
        changedFiles:
            (json['changedFiles'] as List<dynamic>?)?.cast<String>() ??
            const [],
        diffSummary: json['diffSummary'] as String?,
        verificationSuggestions:
            (json['verificationSuggestions'] as List<dynamic>?)
                ?.cast<String>() ??
            const [],
        verificationRequested: json['verificationRequested'] as bool? ?? false,
        planMarkdown: json['planMarkdown'] as String?,
        plannedFiles:
            (json['plannedFiles'] as List<dynamic>?)?.cast<String>() ??
            const [],
        plannedTargets: (json['plannedTargets'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PlannedFileTarget.fromJson)
            .nonNulls
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

class PatchApplyResult {
  final PatchApplyStatus status;
  final List<String> changedFiles;
  final String? checkpointId;
  final String? conflictMessage;
  final String? message;
  final String? diffSummary;
  final List<String> verificationSuggestions;
  final bool verificationRequested;

  const PatchApplyResult({
    required this.status,
    this.changedFiles = const [],
    this.checkpointId,
    this.conflictMessage,
    this.message,
    this.diffSummary,
    this.verificationSuggestions = const [],
    this.verificationRequested = false,
  });

  bool get applied => status == PatchApplyStatus.applied;
}

typedef PatchTransactionResult = PatchApplyResult;

const _sentinel = Object();
