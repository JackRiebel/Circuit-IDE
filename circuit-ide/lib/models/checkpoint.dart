import 'dart:convert';

class FileSnapshot {
  final String path;
  final String? originalContent; // null means file didn't exist before
  final bool wasCreated; // true if this file was newly created by the AI
  final List<String> createdParentDirs;

  const FileSnapshot({
    required this.path,
    required this.originalContent,
    this.wasCreated = false,
    this.createdParentDirs = const [],
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'originalContent': originalContent,
    'wasCreated': wasCreated,
    'createdParentDirs': createdParentDirs,
  };

  factory FileSnapshot.fromJson(Map<String, dynamic> json) => FileSnapshot(
    path: json['path'] as String,
    originalContent: json['originalContent'] as String?,
    wasCreated: json['wasCreated'] as bool? ?? false,
    createdParentDirs:
        (json['createdParentDirs'] as List<dynamic>?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const [],
  );
}

class Checkpoint {
  final String id;
  final DateTime timestamp;
  final String description;
  final List<FileSnapshot> snapshots;

  /// The reviewed patch that created this checkpoint, when available.
  final String? patchSetId;

  /// The owning task is deliberately stored as an opaque identifier. The
  /// checkpoint history can therefore survive task title changes and still
  /// render a useful link back to its source task.
  final String? workItemId;

  /// A restore creates a second checkpoint containing the state immediately
  /// before that restore. This provides an explicit, durable way back.
  final String? restoresCheckpointId;

  const Checkpoint({
    required this.id,
    required this.timestamp,
    required this.description,
    required this.snapshots,
    this.patchSetId,
    this.workItemId,
    this.restoresCheckpointId,
  });

  int get fileCount => snapshots.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'description': description,
    'snapshots': snapshots.map((s) => s.toJson()).toList(),
    'patchSetId': patchSetId,
    'workItemId': workItemId,
    'restoresCheckpointId': restoresCheckpointId,
  };

  factory Checkpoint.fromJson(Map<String, dynamic> json) => Checkpoint(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    description: json['description'] as String,
    snapshots: (json['snapshots'] as List)
        .map((s) => FileSnapshot.fromJson(s as Map<String, dynamic>))
        .toList(),
    patchSetId: json['patchSetId'] as String?,
    workItemId: json['workItemId'] as String?,
    restoresCheckpointId: json['restoresCheckpointId'] as String?,
  );

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
