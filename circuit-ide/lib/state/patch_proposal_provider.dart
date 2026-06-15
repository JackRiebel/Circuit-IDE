import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/agent_run.dart';
import '../models/checkpoint.dart';
import '../models/reviewed_edit.dart';
import 'agent_run_provider.dart';
import 'agent_workspace_provider.dart';
import 'diff_preview_provider.dart';
import 'file_tree_provider.dart';
import 'work_item_provider.dart';

const _uuid = Uuid();

class PatchProposalState {
  final ProposedPatchSet? active;
  final List<ProposedPatchSet> history;
  final Map<String, Checkpoint> checkpoints;
  final bool isApplying;
  final String? message;

  const PatchProposalState({
    this.active,
    this.history = const [],
    this.checkpoints = const {},
    this.isApplying = false,
    this.message,
  });

  PatchProposalState copyWith({
    Object? active = _sentinel,
    List<ProposedPatchSet>? history,
    Map<String, Checkpoint>? checkpoints,
    bool? isApplying,
    Object? message = _sentinel,
  }) {
    return PatchProposalState(
      active: identical(active, _sentinel)
          ? this.active
          : active as ProposedPatchSet?,
      history: history ?? this.history,
      checkpoints: checkpoints ?? this.checkpoints,
      isApplying: isApplying ?? this.isApplying,
      message: identical(message, _sentinel)
          ? this.message
          : message as String?,
    );
  }
}

class PatchProposalRevisionRequest {
  final String patchSetId;
  final String prompt;

  const PatchProposalRevisionRequest({
    required this.patchSetId,
    required this.prompt,
  });
}

class PatchProposalController extends Notifier<PatchProposalState> {
  @override
  PatchProposalState build() => const PatchProposalState();

  ProposedPatchSet propose({
    required String title,
    required List<ProposedFileEdit> edits,
    String? planMarkdown,
    List<String> plannedFiles = const [],
    String? workItemId,
    String? runId,
    String? agentTaskId,
    String? comparisonSummary,
  }) {
    final patchSet = ProposedPatchSet(
      id: _uuid.v4().substring(0, 8),
      title: title,
      workItemId: workItemId,
      runId: runId,
      agentTaskId: agentTaskId,
      comparisonSummary: comparisonSummary,
      edits: edits,
      planMarkdown: planMarkdown,
      plannedFiles: plannedFiles,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      active: patchSet,
      history: [patchSet, ...state.history].take(20).toList(),
      message: 'Patch ready for review.',
    );
    _showDiffPreview(patchSet);
    ref.read(workItemProvider.notifier).recordPatchSet(patchSet);
    if (agentTaskId != null) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .attachPatchSet(agentTaskId, patchSet);
    }
    ref
        .read(agentRunProvider.notifier)
        .addEvent(
          AgentRunKind.chat,
          AgentRunEventType.patchProposal,
          'Patch proposed: ${patchSet.title}',
          metadata: {'patchSetId': patchSet.id},
        );
    ref
        .read(agentRunProvider.notifier)
        .addSpan(
          AgentRunKind.chat,
          spanKind: AgentTraceSpanKind.patchProposal,
          name: 'Patch proposal',
          detail: '${patchSet.fileCount} files',
        );
    return patchSet;
  }

  Future<PatchApplyResult> applyActive() async {
    final patchSet = state.active;
    if (patchSet == null) {
      return const PatchApplyResult(
        status: PatchApplyStatus.failed,
        message: 'No patch proposal is active.',
      );
    }
    return apply(patchSet.id);
  }

  Future<PatchApplyResult> apply(String patchSetId) async {
    final patchSet = _find(patchSetId);
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (patchSet == null || rootPath == null) {
      return const PatchApplyResult(
        status: PatchApplyStatus.failed,
        message: 'No workspace or patch proposal available.',
      );
    }

    state = state.copyWith(isApplying: true, message: 'Applying patch...');
    final snapshots = <FileSnapshot>[];
    final changedFiles = <String>[];

    try {
      for (final edit in patchSet.edits) {
        final fullPath = _resolve(rootPath, edit.path);
        if (fullPath == null) {
          return _finishApply(
            patchSet,
            const PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage: 'Patch includes a path outside the workspace.',
            ),
          );
        }

        final file = File(fullPath);
        final existed = await file.exists();
        final beforeOnDisk = existed ? await file.readAsString() : null;
        if (edit.before != null && beforeOnDisk != edit.before) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage: 'File changed since proposal: ${edit.path}',
            ),
          );
        }

        snapshots.add(
          FileSnapshot(
            path: edit.path,
            originalContent: beforeOnDisk,
            wasCreated: !existed,
          ),
        );

        switch (edit.type) {
          case ProposedFileEditType.create:
          case ProposedFileEditType.modify:
            await file.parent.create(recursive: true);
            await file.writeAsString(edit.after ?? '');
            changedFiles.add(edit.path);
            break;
          case ProposedFileEditType.delete:
            if (await file.exists()) await file.delete();
            changedFiles.add(edit.path);
            break;
        }
      }

      final checkpoint = Checkpoint(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        description: 'Applied patch proposal: ${patchSet.title}',
        snapshots: snapshots,
      );
      return _finishApply(
        patchSet,
        PatchApplyResult(
          status: PatchApplyStatus.applied,
          changedFiles: changedFiles,
          checkpointId: checkpoint.id,
          message: 'Applied ${changedFiles.length} files.',
        ),
        checkpoint: checkpoint,
      );
    } catch (error) {
      return _finishApply(
        patchSet,
        PatchApplyResult(
          status: PatchApplyStatus.failed,
          message: error.toString(),
        ),
      );
    }
  }

  void approvePlanActive() {
    final patchSet = state.active;
    if (patchSet == null) return;
    final updated = patchSet.copyWith(
      approvalStatus: PatchApprovalStatus.approved,
      applyStatus: PatchApplyStatus.applied,
    );
    state = state.copyWith(
      active: null,
      history: _replace(updated),
      message: 'Plan approved.',
    );
    ref.read(workItemProvider.notifier).recordPatchSet(updated);
    _syncAgentTask(updated);
  }

  void rejectActive() {
    final patchSet = state.active;
    if (patchSet == null) return;
    final updated = patchSet.copyWith(
      approvalStatus: PatchApprovalStatus.rejected,
      applyStatus: PatchApplyStatus.rejected,
    );
    state = state.copyWith(
      active: null,
      history: _replace(updated),
      message: 'Patch rejected.',
    );
    ref.read(workItemProvider.notifier).recordPatchSet(updated);
    _syncAgentTask(updated);
  }

  void requestRevision(PatchProposalRevisionRequest request) {
    final patchSet = _find(request.patchSetId);
    if (patchSet == null) return;
    final updated = patchSet.copyWith(
      approvalStatus: PatchApprovalStatus.revisionRequested,
      revisionPrompt: request.prompt,
    );
    state = state.copyWith(
      active: updated,
      history: _replace(updated),
      message: 'Revision requested.',
    );
    ref.read(workItemProvider.notifier).recordPatchSet(updated);
    _syncAgentTask(updated);
  }

  Future<PatchApplyResult> restoreCheckpoint(String checkpointId) async {
    final checkpoint = state.checkpoints[checkpointId];
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (checkpoint == null || rootPath == null) {
      return const PatchApplyResult(
        status: PatchApplyStatus.failed,
        message: 'Checkpoint not found.',
      );
    }
    final restored = <String>[];
    try {
      for (final snapshot in checkpoint.snapshots) {
        final fullPath = _resolve(rootPath, snapshot.path);
        if (fullPath == null) continue;
        final file = File(fullPath);
        if (snapshot.wasCreated) {
          if (await file.exists()) await file.delete();
        } else if (snapshot.originalContent != null) {
          await file.parent.create(recursive: true);
          await file.writeAsString(snapshot.originalContent!);
        }
        restored.add(snapshot.path);
      }
      await ref.read(fileTreeProvider.notifier).refresh();
      return PatchApplyResult(
        status: PatchApplyStatus.applied,
        changedFiles: restored,
        checkpointId: checkpointId,
        message: 'Restored ${restored.length} files.',
      );
    } catch (error) {
      return PatchApplyResult(
        status: PatchApplyStatus.failed,
        checkpointId: checkpointId,
        message: error.toString(),
      );
    }
  }

  ProposedPatchSet? _find(String id) {
    if (state.active?.id == id) return state.active;
    return state.history.where((patchSet) => patchSet.id == id).firstOrNull;
  }

  Future<PatchApplyResult> _finishApply(
    ProposedPatchSet patchSet,
    PatchApplyResult result, {
    Checkpoint? checkpoint,
  }) async {
    final updated = patchSet.copyWith(
      approvalStatus: result.applied
          ? PatchApprovalStatus.approved
          : patchSet.approvalStatus,
      applyStatus: result.status,
      checkpointId: result.checkpointId,
      conflictMessage: result.conflictMessage,
      changedFiles: result.changedFiles,
    );
    state = state.copyWith(
      active: result.applied ? null : updated,
      history: _replace(updated),
      checkpoints: checkpoint == null
          ? state.checkpoints
          : {...state.checkpoints, checkpoint.id: checkpoint},
      isApplying: false,
      message: result.message ?? result.conflictMessage ?? result.status.name,
    );
    await ref.read(fileTreeProvider.notifier).refresh();
    ref.read(workItemProvider.notifier).recordPatchSet(updated);
    _syncAgentTask(updated);
    if (result.applied && updated.agentTaskId != null) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .completeTask(
            updated.agentTaskId!,
            result: 'Applied patch ${updated.title}.',
          );
    }
    ref
        .read(agentRunProvider.notifier)
        .addEvent(
          AgentRunKind.chat,
          AgentRunEventType.patchApply,
          result.applied ? 'Patch applied' : 'Patch not applied',
          metadata: {
            'patchSetId': patchSet.id,
            'status': result.status.name,
            if (result.checkpointId != null)
              'checkpointId': result.checkpointId!,
          },
        );
    ref
        .read(agentRunProvider.notifier)
        .addSpan(
          AgentRunKind.chat,
          spanKind: AgentTraceSpanKind.patchApply,
          name: 'Patch apply',
          detail: result.message ?? result.conflictMessage,
        );
    if (result.applied) {
      ref
          .read(agentRunProvider.notifier)
          .addRunArtifacts(
            AgentRunKind.chat,
            changedFiles: result.changedFiles,
            checkpointId: result.checkpointId,
          );
    }
    return result;
  }

  void _showDiffPreview(ProposedPatchSet patchSet) {
    ref.read(diffPreviewProvider.notifier).showDiffs([
      for (final edit in patchSet.edits)
        DiffChange(
          filePath: edit.path,
          originalContent: edit.before ?? '',
          newContent: edit.after ?? '',
          description: edit.type.name,
          wasCreated: edit.type == ProposedFileEditType.create,
        ),
    ]);
  }

  List<ProposedPatchSet> _replace(ProposedPatchSet updated) {
    final replaced = [
      updated,
      ...state.history.where((patchSet) => patchSet.id != updated.id),
    ];
    return replaced.take(20).toList();
  }

  void _syncAgentTask(ProposedPatchSet patchSet) {
    final taskId = patchSet.agentTaskId;
    if (taskId == null) return;
    ref.read(agentWorkspaceProvider.notifier).attachPatchSet(taskId, patchSet);
  }

  String? _resolve(String rootPath, String targetPath) {
    final normalized = p.normalize(
      p.isAbsolute(targetPath) ? targetPath : p.join(rootPath, targetPath),
    );
    if (normalized != rootPath && !p.isWithin(rootPath, normalized)) {
      return null;
    }
    return normalized;
  }
}

final patchProposalProvider =
    NotifierProvider<PatchProposalController, PatchProposalState>(
      PatchProposalController.new,
    );

const _sentinel = Object();
