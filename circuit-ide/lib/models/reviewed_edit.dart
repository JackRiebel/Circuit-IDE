enum ProposedFileEditType { create, modify, delete }

enum PatchApplyStatus { applied, rejected, conflict, failed }

enum ToolApprovalPolicy { reviewWrites, autoApproveReadOnly, autoApproveAll }

class ProposedFileEdit {
  final String path;
  final ProposedFileEditType type;
  final String? before;
  final String? after;
  final String? unifiedDiff;

  const ProposedFileEdit({
    required this.path,
    required this.type,
    this.before,
    this.after,
    this.unifiedDiff,
  });

  bool get requiresApproval =>
      type != ProposedFileEditType.modify || before != after;
}

class ProposedPatchSet {
  final String id;
  final String title;
  final List<ProposedFileEdit> edits;
  final DateTime createdAt;

  const ProposedPatchSet({
    required this.id,
    required this.title,
    required this.edits,
    required this.createdAt,
  });

  bool get isEmpty => edits.isEmpty;
  int get fileCount => edits.length;
}

class PatchApplyResult {
  final PatchApplyStatus status;
  final List<String> changedFiles;
  final String? message;

  const PatchApplyResult({
    required this.status,
    this.changedFiles = const [],
    this.message,
  });

  bool get applied => status == PatchApplyStatus.applied;
}
