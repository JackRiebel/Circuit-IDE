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
  final String? runId;
  final List<ProposedFileEdit> edits;
  final DateTime createdAt;
  final String? checkpointId;
  final PatchApprovalStatus approvalStatus;
  final PatchApplyStatus? applyStatus;
  final String? conflictMessage;
  final String? revisionPrompt;
  final List<String> changedFiles;

  const ProposedPatchSet({
    required this.id,
    required this.title,
    this.workItemId,
    this.runId,
    required this.edits,
    required this.createdAt,
    this.checkpointId,
    this.approvalStatus = PatchApprovalStatus.proposed,
    this.applyStatus,
    this.conflictMessage,
    this.revisionPrompt,
    this.changedFiles = const [],
  });

  bool get isEmpty => edits.isEmpty;
  int get fileCount => edits.length;

  ProposedPatchSet copyWith({
    String? workItemId,
    String? runId,
    String? checkpointId,
    PatchApprovalStatus? approvalStatus,
    PatchApplyStatus? applyStatus,
    Object? conflictMessage = _sentinel,
    Object? revisionPrompt = _sentinel,
    List<String>? changedFiles,
  }) {
    return ProposedPatchSet(
      id: id,
      title: title,
      workItemId: workItemId ?? this.workItemId,
      runId: runId ?? this.runId,
      edits: edits,
      createdAt: createdAt,
      checkpointId: checkpointId ?? this.checkpointId,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      applyStatus: applyStatus ?? this.applyStatus,
      conflictMessage: identical(conflictMessage, _sentinel)
          ? this.conflictMessage
          : conflictMessage as String?,
      revisionPrompt: identical(revisionPrompt, _sentinel)
          ? this.revisionPrompt
          : revisionPrompt as String?,
      changedFiles: changedFiles ?? this.changedFiles,
    );
  }
}

class PatchApplyResult {
  final PatchApplyStatus status;
  final List<String> changedFiles;
  final String? checkpointId;
  final String? conflictMessage;
  final String? message;

  const PatchApplyResult({
    required this.status,
    this.changedFiles = const [],
    this.checkpointId,
    this.conflictMessage,
    this.message,
  });

  bool get applied => status == PatchApplyStatus.applied;
}

const _sentinel = Object();
