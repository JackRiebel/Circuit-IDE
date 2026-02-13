import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../enums/event_type.dart';
import '../models/checkpoint.dart';
import 'connection_provider.dart';
import 'file_tree_provider.dart';

class DiffChange {
  final String filePath;
  final String originalContent;
  final String newContent;
  final String description;
  final bool isAccepted;
  final bool wasCreated; // file was newly created

  const DiffChange({
    required this.filePath,
    required this.originalContent,
    required this.newContent,
    this.description = '',
    this.isAccepted = false,
    this.wasCreated = false,
  });

  DiffChange copyWith({bool? isAccepted, String? newContent}) {
    return DiffChange(
      filePath: filePath,
      originalContent: originalContent,
      newContent: newContent ?? this.newContent,
      description: description,
      isAccepted: isAccepted ?? this.isAccepted,
      wasCreated: wasCreated,
    );
  }

  /// Compute simple line diff stats.
  ({int additions, int deletions}) get stats {
    final oldLines = originalContent.split('\n');
    final newLines = newContent.split('\n');
    int additions = 0;
    int deletions = 0;

    // Simple line-level diff (not a full Myers diff, but good enough for stats)
    final oldSet = oldLines.toSet();
    final newSet = newLines.toSet();

    for (final line in newLines) {
      if (!oldSet.contains(line)) additions++;
    }
    for (final line in oldLines) {
      if (!newSet.contains(line)) deletions++;
    }

    return (additions: additions, deletions: deletions);
  }
}

class DiffPreviewState {
  final List<DiffChange> changes;
  final bool isVisible;
  final int activeChangeIndex;

  const DiffPreviewState({
    this.changes = const [],
    this.isVisible = false,
    this.activeChangeIndex = 0,
  });

  DiffPreviewState copyWith({
    List<DiffChange>? changes,
    bool? isVisible,
    int? activeChangeIndex,
  }) {
    return DiffPreviewState(
      changes: changes ?? this.changes,
      isVisible: isVisible ?? this.isVisible,
      activeChangeIndex: activeChangeIndex ?? this.activeChangeIndex,
    );
  }
}

class DiffPreviewNotifier extends Notifier<DiffPreviewState> {
  bool _listening = false;

  @override
  DiffPreviewState build() {
    _listenToEvents();
    return const DiffPreviewState();
  }

  void _listenToEvents() {
    if (_listening) return;
    _listening = true;

    final service = ref.read(agentServiceProvider);

    // When a checkpoint is created, auto-show the diff preview
    service.events.on(EventType.checkpointCreated, (event) async {
      final checkpoint = event.data['checkpoint'] as Checkpoint;
      final workingDir = ref.read(fileTreeProvider).rootPath;
      if (workingDir == null) return;

      final changes = <DiffChange>[];
      for (final snapshot in checkpoint.snapshots) {
        // Read the current (new) content from disk
        final fullPath = snapshot.path.startsWith('/')
            ? snapshot.path
            : '$workingDir/${snapshot.path}';

        String newContent = '';
        try {
          final file = File(fullPath);
          if (await file.exists()) {
            newContent = await file.readAsString();
          }
        } catch (_) {}

        changes.add(DiffChange(
          filePath: snapshot.path,
          originalContent: snapshot.originalContent ?? '',
          newContent: newContent,
          description: snapshot.wasCreated ? 'New file' : 'Modified',
          wasCreated: snapshot.wasCreated,
        ));
      }

      if (changes.isNotEmpty) {
        showDiffs(changes);
      }
    });
  }

  void showDiffs(List<DiffChange> changes) {
    state = DiffPreviewState(
      changes: changes,
      isVisible: true,
      activeChangeIndex: 0,
    );
  }

  void acceptChange(int index) {
    final updated = List<DiffChange>.from(state.changes);
    updated[index] = updated[index].copyWith(isAccepted: true);
    state = state.copyWith(changes: updated);

    // Auto-close if all accepted
    if (updated.every((c) => c.isAccepted)) {
      Future.delayed(const Duration(milliseconds: 500), close);
    }
  }

  /// Reject a change: revert the file to its original content.
  Future<void> rejectChange(int index) async {
    final change = state.changes[index];
    final workingDir = ref.read(fileTreeProvider).rootPath;
    if (workingDir == null) return;

    try {
      final fullPath = change.filePath.startsWith('/')
          ? change.filePath
          : '$workingDir/${change.filePath}';

      if (change.wasCreated) {
        // Delete the newly created file
        final file = File(fullPath);
        if (await file.exists()) await file.delete();
      } else {
        // Restore original content
        await File(fullPath).writeAsString(change.originalContent);
      }
    } catch (_) {}

    final updated = List<DiffChange>.from(state.changes);
    updated.removeAt(index);
    state = state.copyWith(
      changes: updated,
      isVisible: updated.isNotEmpty,
    );

    ref.read(fileTreeProvider.notifier).refresh();
  }

  void acceptAll() {
    final updated = state.changes
        .map((c) => c.copyWith(isAccepted: true))
        .toList();
    state = state.copyWith(changes: updated);
    Future.delayed(const Duration(milliseconds: 500), close);
  }

  void close() {
    state = const DiffPreviewState();
  }

  void setActiveChange(int index) {
    state = state.copyWith(activeChangeIndex: index);
  }
}

final diffPreviewProvider =
    NotifierProvider<DiffPreviewNotifier, DiffPreviewState>(
  DiffPreviewNotifier.new,
);
