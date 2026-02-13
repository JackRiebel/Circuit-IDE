import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../core/utils/logger.dart';
import '../../models/checkpoint.dart';

const _uuid = Uuid();

class CheckpointManager {
  final String workingDir;
  final List<Checkpoint> _checkpoints = [];
  static const int maxCheckpoints = 50;

  /// Files already snapshotted in the current turn (avoids double-snapshotting
  /// the same file if the AI edits it multiple times in one response).
  final Set<String> _currentTurnSnapshotted = {};

  CheckpointManager({required this.workingDir});

  List<Checkpoint> get checkpoints => List.unmodifiable(_checkpoints);

  /// Call this at the start of each agent response to reset per-turn tracking.
  void beginTurn() {
    _currentTurnSnapshotted.clear();
  }

  /// Snapshot a file before it gets modified. Returns the snapshot, or null
  /// if the file was already snapshotted this turn.
  Future<FileSnapshot?> snapshotFile(String relativePath) async {
    final fullPath = _resolvePath(relativePath);
    if (_currentTurnSnapshotted.contains(fullPath)) return null;
    _currentTurnSnapshotted.add(fullPath);

    try {
      final file = File(fullPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        return FileSnapshot(
          path: relativePath,
          originalContent: content,
          wasCreated: false,
        );
      } else {
        // File doesn't exist yet — will be created
        return FileSnapshot(
          path: relativePath,
          originalContent: null,
          wasCreated: true,
        );
      }
    } catch (e) {
      Logger.warning('Could not snapshot $relativePath: $e', 'Checkpoint');
      return null;
    }
  }

  /// Finalize the current turn's snapshots into a checkpoint.
  Checkpoint? commitTurn(List<FileSnapshot> snapshots, String description) {
    if (snapshots.isEmpty) return null;

    final checkpoint = Checkpoint(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      description: description,
      snapshots: snapshots,
    );

    _checkpoints.insert(0, checkpoint); // newest first

    // Trim old checkpoints
    while (_checkpoints.length > maxCheckpoints) {
      _checkpoints.removeLast();
    }

    Logger.info(
      'Checkpoint created: ${checkpoint.fileCount} files — $description',
      'Checkpoint',
    );
    return checkpoint;
  }

  /// Revert all files in a checkpoint to their original state.
  Future<RevertResult> revertCheckpoint(String checkpointId) async {
    final index = _checkpoints.indexWhere((c) => c.id == checkpointId);
    if (index < 0) {
      return const RevertResult(success: false, error: 'Checkpoint not found');
    }

    final checkpoint = _checkpoints[index];
    final reverted = <String>[];
    final errors = <String>[];

    for (final snapshot in checkpoint.snapshots) {
      try {
        final fullPath = _resolvePath(snapshot.path);
        final file = File(fullPath);

        if (snapshot.wasCreated) {
          // File was created by AI — delete it
          if (await file.exists()) {
            await file.delete();
            reverted.add('Deleted ${snapshot.path}');
          }
        } else {
          // Restore original content
          if (snapshot.originalContent != null) {
            await file.writeAsString(snapshot.originalContent!);
            reverted.add('Restored ${snapshot.path}');
          }
        }
      } catch (e) {
        errors.add('Failed to revert ${snapshot.path}: $e');
      }
    }

    // Remove this checkpoint and all newer ones that are now invalid
    _checkpoints.removeRange(0, index + 1);

    return RevertResult(
      success: errors.isEmpty,
      reverted: reverted,
      errors: errors,
    );
  }

  /// Clear all checkpoints.
  void clear() {
    _checkpoints.clear();
    _currentTurnSnapshotted.clear();
  }

  String _resolvePath(String relativePath) {
    if (relativePath.startsWith('/')) return relativePath;
    return '$workingDir/$relativePath';
  }
}

class RevertResult {
  final bool success;
  final List<String> reverted;
  final List<String> errors;
  final String? error;

  const RevertResult({
    required this.success,
    this.reverted = const [],
    this.errors = const [],
    this.error,
  });
}
