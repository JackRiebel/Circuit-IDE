enum ProposedFileEditType { create, modify, delete }

enum PatchApplyStatus { applied, rejected, conflict, failed }

enum PatchApprovalStatus { proposed, approved, rejected, revisionRequested }

enum ToolApprovalPolicy { reviewWrites, autoApproveReadOnly, autoApproveAll }

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
  final String? planMarkdown;
  final List<String> plannedFiles;

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
    this.planMarkdown,
    this.plannedFiles = const [],
  });

  bool get isEmpty => edits.isEmpty && plannedFiles.isEmpty;
  bool get isPlanOnly => edits.isEmpty && plannedFiles.isNotEmpty;
  int get fileCount => edits.isNotEmpty ? edits.length : plannedFiles.length;

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
    Object? planMarkdown = _sentinel,
    List<String>? plannedFiles,
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
      planMarkdown: identical(planMarkdown, _sentinel)
          ? this.planMarkdown
          : planMarkdown as String?,
      plannedFiles: plannedFiles ?? this.plannedFiles,
    );
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

  const PatchApplyResult({
    required this.status,
    this.changedFiles = const [],
    this.checkpointId,
    this.conflictMessage,
    this.message,
    this.diffSummary,
    this.verificationSuggestions = const [],
  });

  bool get applied => status == PatchApplyStatus.applied;
}

typedef PatchTransactionResult = PatchApplyResult;

const _sentinel = Object();
