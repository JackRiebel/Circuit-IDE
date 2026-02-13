import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../enums/event_type.dart';
import '../models/checkpoint.dart';
import 'connection_provider.dart';
import 'file_tree_provider.dart';

class CheckpointState {
  final List<Checkpoint> checkpoints;
  final bool isReverting;
  final String? lastRevertMessage;

  const CheckpointState({
    this.checkpoints = const [],
    this.isReverting = false,
    this.lastRevertMessage,
  });

  CheckpointState copyWith({
    List<Checkpoint>? checkpoints,
    bool? isReverting,
    String? lastRevertMessage,
  }) {
    return CheckpointState(
      checkpoints: checkpoints ?? this.checkpoints,
      isReverting: isReverting ?? this.isReverting,
      lastRevertMessage: lastRevertMessage ?? this.lastRevertMessage,
    );
  }
}

class CheckpointNotifier extends Notifier<CheckpointState> {
  bool _listening = false;

  @override
  CheckpointState build() {
    _listenToEvents();
    return const CheckpointState();
  }

  void _listenToEvents() {
    if (_listening) return;
    _listening = true;

    final service = ref.read(agentServiceProvider);
    service.events.on(EventType.checkpointCreated, (event) {
      final checkpoint = event.data['checkpoint'] as Checkpoint;
      state = state.copyWith(
        checkpoints: [checkpoint, ...state.checkpoints],
      );
    });
  }

  Future<void> revertToCheckpoint(String checkpointId) async {
    final service = ref.read(agentServiceProvider);
    final manager = service.checkpointManager;
    if (manager == null) return;

    state = state.copyWith(isReverting: true);

    final result = await manager.revertCheckpoint(checkpointId);

    // Remove reverted checkpoint and all newer ones from our list
    final idx = state.checkpoints.indexWhere((c) => c.id == checkpointId);
    final updated = idx >= 0
        ? state.checkpoints.sublist(idx + 1)
        : state.checkpoints;

    state = state.copyWith(
      checkpoints: updated,
      isReverting: false,
      lastRevertMessage: result.success
          ? 'Reverted ${result.reverted.length} files'
          : 'Revert had errors: ${result.errors.join(", ")}',
    );

    // Refresh the file tree so changes are visible
    ref.read(fileTreeProvider.notifier).refresh();
  }

  void clearMessage() {
    state = state.copyWith(lastRevertMessage: null);
  }
}

final checkpointProvider =
    NotifierProvider<CheckpointNotifier, CheckpointState>(
  CheckpointNotifier.new,
);
