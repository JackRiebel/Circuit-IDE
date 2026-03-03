import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum GhostStatus { queued, running, completed, failed, undone }

class GhostTask {
  final String id;
  final String description;
  final GhostStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? checkpointId;
  final List<GhostFileDiff> diffs;
  final String? summary;
  final String? error;

  GhostTask({
    String? id,
    required this.description,
    this.status = GhostStatus.queued,
    DateTime? startedAt,
    this.completedAt,
    this.checkpointId,
    this.diffs = const [],
    this.summary,
    this.error,
  })  : id = id ?? _uuid.v4().substring(0, 8),
        startedAt = startedAt ?? DateTime.now();

  GhostTask copyWith({
    GhostStatus? status,
    DateTime? completedAt,
    String? checkpointId,
    List<GhostFileDiff>? diffs,
    String? summary,
    String? error,
  }) {
    return GhostTask(
      id: id,
      description: description,
      status: status ?? this.status,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      checkpointId: checkpointId ?? this.checkpointId,
      diffs: diffs ?? this.diffs,
      summary: summary ?? this.summary,
      error: error ?? this.error,
    );
  }
}

class GhostFileDiff {
  final String filePath;
  final String beforeContent;
  final String afterContent;
  final int additions;
  final int deletions;
  final bool isNew;
  final bool isDeleted;

  const GhostFileDiff({
    required this.filePath,
    required this.beforeContent,
    required this.afterContent,
    this.additions = 0,
    this.deletions = 0,
    this.isNew = false,
    this.isDeleted = false,
  });
}
