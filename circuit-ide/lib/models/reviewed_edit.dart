enum ProposedFileEditType { create, modify, delete }

enum PatchApplyStatus { applied, rejected, conflict, failed }

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
  final List<ProposedFileEdit> edits;
  final DateTime createdAt;
  final String? checkpointId;
  final PatchApplyStatus? applyStatus;
  final String? conflictMessage;
  final List<String> changedFiles;

  const ProposedPatchSet({
    required this.id,
    required this.title,
    required this.edits,
    required this.createdAt,
    this.checkpointId,
    this.applyStatus,
    this.conflictMessage,
    this.changedFiles = const [],
  });

  bool get isEmpty => edits.isEmpty;
  int get fileCount => edits.length;

  ProposedPatchSet copyWith({
    String? checkpointId,
    PatchApplyStatus? applyStatus,
    String? conflictMessage,
    List<String>? changedFiles,
  }) {
    return ProposedPatchSet(
      id: id,
      title: title,
      edits: edits,
      createdAt: createdAt,
      checkpointId: checkpointId ?? this.checkpointId,
      applyStatus: applyStatus ?? this.applyStatus,
      conflictMessage: conflictMessage ?? this.conflictMessage,
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
