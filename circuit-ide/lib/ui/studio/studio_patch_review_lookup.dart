import '../../models/reviewed_edit.dart';
import '../../models/studio_thread.dart';
import '../../state/patch_proposal_provider.dart';

ProposedPatchSet? studioPatchForDrawer(
  PatchProposalState patchState,
  String? requestedPatchId, {
  StudioThread? thread,
  String? taskId,
  String? selectedPath,
}) {
  final requestedId = requestedPatchId?.trim();
  if (requestedId != null && requestedId.isNotEmpty) {
    if (patchState.active?.id == requestedId) return patchState.active;
    for (final patch in patchState.history) {
      if (patch.id == requestedId) return patch;
    }
  }
  final threadPatch = _latestPatchForThread(
    patchState,
    thread: thread,
    taskId: taskId,
    selectedPath: selectedPath,
  );
  return threadPatch ?? patchState.active;
}

ProposedPatchSet? _latestPatchForThread(
  PatchProposalState patchState, {
  required StudioThread? thread,
  required String? taskId,
  required String? selectedPath,
}) {
  if (thread == null && (taskId == null || taskId.trim().isEmpty)) {
    return null;
  }
  final candidates = <ProposedPatchSet>[];
  void addPatch(ProposedPatchSet? patch) {
    if (patch == null) return;
    if (!_patchBelongsToThread(patch, thread: thread, taskId: taskId)) return;
    candidates.add(patch);
  }

  addPatch(patchState.active);
  for (final patch in patchState.history) {
    addPatch(patch);
  }
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final priorityCompare =
        _drawerPatchPriority(
          b,
          patchState: patchState,
          selectedPath: selectedPath,
        ).compareTo(
          _drawerPatchPriority(
            a,
            patchState: patchState,
            selectedPath: selectedPath,
          ),
        );
    if (priorityCompare != 0) return priorityCompare;
    return b.createdAt.compareTo(a.createdAt);
  });
  return candidates.first;
}

bool _patchBelongsToThread(
  ProposedPatchSet patch, {
  required StudioThread? thread,
  required String? taskId,
}) {
  final normalizedTaskId = taskId?.trim();
  if (normalizedTaskId != null &&
      normalizedTaskId.isNotEmpty &&
      patch.agentTaskId == normalizedTaskId) {
    return true;
  }
  if (thread == null) return false;
  if (thread.taskId != null &&
      thread.taskId!.trim().isNotEmpty &&
      patch.agentTaskId == thread.taskId) {
    return true;
  }
  final runId = patch.runId?.trim();
  if (runId != null && runId.isNotEmpty) {
    final requestIds = thread.turns.map((turn) => turn.requestId).toSet();
    if (requestIds.contains(runId)) return true;
  }
  final patchIds = <String>{
    for (final turn in thread.turns)
      if (turn.acceptedPlanContext?.patchSetId.trim().isNotEmpty == true)
        turn.acceptedPlanContext!.patchSetId,
    for (final turn in thread.turns)
      for (final event in turn.events)
        if (event.patchSetId?.trim().isNotEmpty == true) event.patchSetId!,
  };
  return patchIds.contains(patch.id);
}

int _drawerPatchPriority(
  ProposedPatchSet patch, {
  required PatchProposalState patchState,
  required String? selectedPath,
}) {
  var priority = 0;
  final requestedPath = selectedPath?.trim();
  if (requestedPath != null &&
      requestedPath.isNotEmpty &&
      patch.edits.any((edit) => edit.path == requestedPath)) {
    priority += 100;
  }
  if (patchState.active?.id == patch.id) priority += 80;
  priority += switch (patch.applyStatus) {
    PatchApplyStatus.conflict => 70,
    PatchApplyStatus.revisionRequested => 65,
    null => 60,
    PatchApplyStatus.applied => 55,
    PatchApplyStatus.failed => 45,
    PatchApplyStatus.restored => 35,
    PatchApplyStatus.rejected => 10,
  };
  if (!patch.isPlanOnly && patch.edits.isNotEmpty) priority += 8;
  return priority;
}
