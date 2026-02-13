import 'dart:convert';

class FileSnapshot {
  final String path;
  final String? originalContent; // null means file didn't exist before
  final bool wasCreated; // true if this file was newly created by the AI

  const FileSnapshot({
    required this.path,
    required this.originalContent,
    this.wasCreated = false,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'originalContent': originalContent,
        'wasCreated': wasCreated,
      };

  factory FileSnapshot.fromJson(Map<String, dynamic> json) => FileSnapshot(
        path: json['path'] as String,
        originalContent: json['originalContent'] as String?,
        wasCreated: json['wasCreated'] as bool? ?? false,
      );
}

class Checkpoint {
  final String id;
  final DateTime timestamp;
  final String description;
  final List<FileSnapshot> snapshots;

  const Checkpoint({
    required this.id,
    required this.timestamp,
    required this.description,
    required this.snapshots,
  });

  int get fileCount => snapshots.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'description': description,
        'snapshots': snapshots.map((s) => s.toJson()).toList(),
      };

  factory Checkpoint.fromJson(Map<String, dynamic> json) => Checkpoint(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        description: json['description'] as String,
        snapshots: (json['snapshots'] as List)
            .map((s) => FileSnapshot.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
