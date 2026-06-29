import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/platform_utils.dart';
import '../agent/verification_command_filter.dart'
    as verification_command_filter;
import '../agent/security/secret_detector.dart';
import '../models/agent_run.dart';
import '../models/checkpoint.dart';
import '../models/reviewed_edit.dart';
import 'agent_run_provider.dart';
import 'agent_workspace_provider.dart';
import 'diff_preview_provider.dart';
import 'file_tree_provider.dart';
import 'studio_turn_provider.dart';
import 'work_item_provider.dart';

const _uuid = Uuid();
final _secretDetector = SecretDetector();

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

class PatchProposalStore {
  final String baseDir;

  PatchProposalStore({String? baseDir})
    : baseDir = baseDir ?? p.join(PlatformUtils.configDir, 'patch_proposals');

  String historyPath(String? rootPath) {
    return p.join(baseDir, '${WorkItemStore.projectKey(rootPath)}.json');
  }

  Future<PatchProposalState> load(String? rootPath) async {
    final file = File(historyPath(rootPath));
    if (!await file.exists()) return const PatchProposalState();
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return PatchProposalState(
      active: ProposedPatchSet.fromJson(
        json['active'] as Map<String, dynamic>?,
      ),
      history: (json['history'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProposedPatchSet.fromJson)
          .nonNulls
          .toList(),
      checkpoints: (json['checkpoints'] as Map<String, dynamic>? ?? {}).map(
        (id, value) =>
            MapEntry(id, Checkpoint.fromJson(value as Map<String, dynamic>)),
      ),
      message: json['message'] as String?,
    );
  }

  Future<void> save(String? rootPath, PatchProposalState state) async {
    final file = File(historyPath(rootPath));
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(_encode(state));
  }

  void saveSync(String? rootPath, PatchProposalState state) {
    final file = File(historyPath(rootPath));
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    file.writeAsStringSync(_encode(state));
  }

  String _encode(PatchProposalState state) {
    return const JsonEncoder.withIndent('  ').convert({
      'active': state.active?.toJson(),
      'history': state.history.map((patchSet) => patchSet.toJson()).toList(),
      'checkpoints': state.checkpoints.map(
        (id, checkpoint) => MapEntry(id, checkpoint.toJson()),
      ),
      'message': state.message,
    });
  }
}

final patchProposalStoreProvider = Provider<PatchProposalStore>(
  (ref) => PatchProposalStore(),
);

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
  PatchProposalState build() {
    Future.microtask(_loadForCurrentWorkspace);
    ref.listen(fileTreeProvider, (previous, next) {
      if (previous?.rootPath != next.rootPath) {
        state = const PatchProposalState();
        Future.microtask(_loadForCurrentWorkspace);
      }
    });
    return const PatchProposalState();
  }

  Future<void> _loadForCurrentWorkspace() async {
    if (!ref.mounted) return;
    final rootPath = ref.read(fileTreeProvider).rootPath;
    try {
      final loaded = await ref.read(patchProposalStoreProvider).load(rootPath);
      if (!ref.mounted) return;
      if (ref.read(fileTreeProvider).rootPath != rootPath) return;
      final hasCurrentProposalState =
          state.active != null ||
          state.history.isNotEmpty ||
          state.checkpoints.isNotEmpty;
      if (hasCurrentProposalState) return;
      state = loaded.copyWith(isApplying: false);
      final active = loaded.active;
      if (active != null && active.edits.isNotEmpty) {
        _showDiffPreview(active);
      }
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isApplying: false,
        message: 'Could not load patch proposals: $error',
      );
    }
  }

  ProposedPatchSet propose({
    required String title,
    required List<ProposedFileEdit> edits,
    String? planMarkdown,
    List<String> plannedFiles = const [],
    List<PlannedFileTarget> plannedTargets = const [],
    String? workItemId,
    String? runId,
    String? agentTaskId,
    String? comparisonSummary,
    bool verificationRequested = false,
  }) {
    final previousActive = state.active;
    final rootPath = ref.read(fileTreeProvider).rootPath;
    final normalizedEdits = rootPath == null
        ? edits
        : [
            for (final edit in edits)
              ProposedFileEdit(
                path: _normalizePatchPathForDisplay(rootPath, edit.path),
                type: edit.type,
                before: edit.before,
                after: edit.after,
                unifiedDiff: edit.unifiedDiff,
                applyStatus: edit.applyStatus,
                conflictMessage: edit.conflictMessage,
              ),
          ];
    final normalizedPlannedFiles = rootPath == null
        ? plannedFiles
        : [
            for (final path in plannedFiles)
              _normalizePatchPathForDisplay(rootPath, path),
          ];
    final effectivePlannedTargets = plannedTargets.isNotEmpty
        ? plannedTargets
        : [
            for (final file in normalizedPlannedFiles)
              PlannedFileTarget.fromDisplayString(file),
          ];
    final normalizedPlannedTargets = rootPath == null
        ? effectivePlannedTargets
        : [
            for (final target in effectivePlannedTargets)
              PlannedFileTarget(
                path: _normalizePatchPathForDisplay(rootPath, target.path),
                intent: target.intent,
                operation: target.operation,
              ),
          ];
    final displayPlannedFiles = normalizedPlannedFiles.isNotEmpty
        ? normalizedPlannedFiles
        : [for (final target in normalizedPlannedTargets) target.displayString];
    final patchSet = ProposedPatchSet(
      id: _uuid.v4().substring(0, 8),
      title: title,
      workItemId: workItemId,
      runId: runId,
      agentTaskId: agentTaskId,
      comparisonSummary: comparisonSummary,
      verificationRequested: verificationRequested,
      edits: normalizedEdits,
      planMarkdown: planMarkdown,
      plannedFiles: displayPlannedFiles,
      plannedTargets: normalizedPlannedTargets,
      createdAt: DateTime.now(),
    );
    final superseded = previousActive?.copyWith(supersededBy: patchSet.id);
    state = state.copyWith(
      active: patchSet,
      history: [
        patchSet,
        ?superseded,
        ...state.history.where(
          (candidate) => candidate.id != previousActive?.id,
        ),
      ],
      message: 'Patch ready for review.',
    );
    _persistSync();
    if (superseded != null) {
      ref.read(workItemProvider.notifier).recordPatchSet(superseded);
      _syncAgentTask(superseded);
    }
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
    if (patchSet.edits.isEmpty) {
      return _finishApply(
        patchSet,
        PatchApplyResult(
          status: PatchApplyStatus.conflict,
          conflictMessage: patchSet.isPlanOnly
              ? 'Plan-only proposals cannot be applied directly. Use Implement this plan to create a concrete patch first.'
              : 'Patch proposal contains no concrete file edits to apply.',
        ),
      );
    }

    state = state.copyWith(isApplying: true, message: 'Applying patch...');
    final snapshots = <FileSnapshot>[];
    final changedFiles = <String>[];
    final prepared = <_PreparedPatchEdit>[];
    final seenTargets = <String>{};

    try {
      for (final edit in patchSet.edits) {
        final sanitizedPath = _sanitizePatchPathInput(edit.path);
        if (_hasUnsafePatchPathCharacters(sanitizedPath)) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage:
                  'Patch path contains unsupported control characters: ${edit.path}',
            ),
          );
        }
        if (_looksSecretPatchPath(edit.path)) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage:
                  'Secret or environment file paths cannot be patched: ${edit.path}',
            ),
          );
        }
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
        if (!seenTargets.add(fullPath)) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage:
                  'Patch includes multiple edits for the same file: ${edit.path}',
            ),
          );
        }
        if (_pathTraversesSymlink(rootPath, fullPath)) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage:
                  'Patch path traverses a symlink and could escape the workspace: ${edit.path}',
            ),
          );
        }

        final file = File(fullPath);
        final obstructingAncestor = await _firstNonDirectoryAncestor(
          rootPath,
          file.parent.path,
        );
        if (obstructingAncestor != null) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage:
                  'Patch parent path is not a directory: ${p.relative(obstructingAncestor, from: rootPath)}',
            ),
          );
        }
        if (await FileSystemEntity.isDirectory(fullPath)) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage: 'Patch target is a directory: ${edit.path}',
            ),
          );
        }
        final parentEntity = await FileSystemEntity.type(file.parent.path);
        if (parentEntity != FileSystemEntityType.notFound &&
            parentEntity != FileSystemEntityType.directory) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage:
                  'Patch parent path is not a directory: ${edit.path}',
            ),
          );
        }
        final existed = await file.exists();
        if (edit.type == ProposedFileEditType.create && existed) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage: 'File already exists: ${edit.path}',
            ),
          );
        }
        if (edit.type == ProposedFileEditType.modify && !existed) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage: 'File missing for modify: ${edit.path}',
            ),
          );
        }
        if (edit.type == ProposedFileEditType.delete && !existed) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage: 'File missing for delete: ${edit.path}',
            ),
          );
        }
        final beforeOnDisk = existed
            ? await _readPatchTargetText(file, edit.path)
            : null;
        if (beforeOnDisk is PatchApplyResult) {
          return _finishApply(patchSet, beforeOnDisk);
        }
        final proposedContent = edit.after;
        if ((edit.type == ProposedFileEditType.create ||
                edit.type == ProposedFileEditType.modify) &&
            proposedContent == null) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage:
                  'Patch is missing full target content for ${edit.path}. Ask Circuit to revise the patch with complete file contents before applying.',
            ),
          );
        }
        if ((edit.type == ProposedFileEditType.create ||
                edit.type == ProposedFileEditType.modify) &&
            proposedContent != null) {
          if (proposedContent.trim().isEmpty &&
              !_allowsEmptyPatchContent(edit.path)) {
            return _finishApply(
              patchSet,
              PatchApplyResult(
                status: PatchApplyStatus.conflict,
                conflictMessage:
                    'Patch leaves ${edit.path} empty. Ask Circuit to revise the patch with complete file contents before applying.',
              ),
            );
          }
          final secrets = _secretDetector.scan(proposedContent);
          if (secrets.isNotEmpty) {
            final first = secrets.first;
            return _finishApply(
              patchSet,
              PatchApplyResult(
                status: PatchApplyStatus.conflict,
                conflictMessage:
                    'Patch includes possible ${first.severity} ${first.type} in ${edit.path} on line ${first.line}.',
              ),
            );
          }
        }
        if ((edit.type == ProposedFileEditType.modify ||
                edit.type == ProposedFileEditType.delete) &&
            edit.before == null) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage:
                  'Patch is missing expected prior content for ${edit.path}. Ask Circuit to revise the patch before applying.',
            ),
          );
        }
        if (edit.before != null && beforeOnDisk != edit.before) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage: 'File changed since proposal: ${edit.path}',
            ),
          );
        }
        if (edit.type == ProposedFileEditType.modify &&
            proposedContent != null &&
            edit.before == proposedContent) {
          return _finishApply(
            patchSet,
            PatchApplyResult(
              status: PatchApplyStatus.conflict,
              conflictMessage:
                  'Patch does not change file content: ${edit.path}',
            ),
          );
        }

        prepared.add(_PreparedPatchEdit(edit: edit, fullPath: fullPath));
        snapshots.add(
          FileSnapshot(
            path: edit.path,
            originalContent: beforeOnDisk as String?,
            wasCreated: !existed,
            createdParentDirs: existed
                ? const []
                : _missingParentDirectories(rootPath, fullPath),
          ),
        );
      }

      for (final item in prepared) {
        final edit = item.edit;
        final file = File(item.fullPath);
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
      final verificationSuggestions = _verificationSuggestionsForPatch(
        rootPath,
        patchSet,
      );
      return _finishApply(
        patchSet,
        PatchApplyResult(
          status: PatchApplyStatus.applied,
          changedFiles: changedFiles,
          checkpointId: checkpoint.id,
          message: 'Applied ${changedFiles.length} files.',
          diffSummary: _diffSummary(patchSet),
          verificationSuggestions: verificationSuggestions,
          verificationRequested: patchSet.verificationRequested,
        ),
        checkpoint: checkpoint,
      );
    } catch (error) {
      await _restoreSnapshots(rootPath, snapshots);
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
    markPlanAccepted(patchSet.id);
  }

  void markPlanAccepted(String patchSetId) {
    final patchSet = _find(patchSetId);
    if (patchSet == null) return;
    final updated = patchSet.copyWith(
      approvalStatus: PatchApprovalStatus.approved,
      applyStatus: null,
    );
    state = state.copyWith(
      active: state.active?.id == patchSetId ? null : state.active,
      history: _replace(updated),
      message: 'Plan approved.',
    );
    _persistSync();
    ref.read(workItemProvider.notifier).recordPatchSet(updated);
    _syncAgentTask(updated);
  }

  void markVerificationStarted(String patchSetId, String requestId) {
    final patchSet = _find(patchSetId);
    if (patchSet == null) return;
    final updated = patchSet.copyWith(verificationRequestId: requestId);
    state = state.copyWith(
      active: state.active?.id == patchSetId ? updated : state.active,
      history: _replace(updated),
      message: 'Verification started.',
    );
    _persistSync();
    ref.read(workItemProvider.notifier).recordPatchSet(updated);
    _syncAgentTask(updated);
  }

  void preserveProposal(ProposedPatchSet patchSet) {
    final alreadyActive = state.active?.id == patchSet.id;
    final alreadyHistorical = state.history.any(
      (candidate) => candidate.id == patchSet.id,
    );
    if (alreadyActive && alreadyHistorical) return;
    state = state.copyWith(
      active: alreadyActive ? state.active : patchSet,
      history: [if (!alreadyHistorical) patchSet, ...state.history],
      message: state.message ?? 'Patch ready for review.',
    );
    _persistSync();
    _showDiffPreview(patchSet);
    ref.read(workItemProvider.notifier).recordPatchSet(patchSet);
    _syncAgentTask(patchSet);
  }

  void rejectActive() {
    if (state.isApplying) return;
    final patchSet = state.active;
    if (patchSet == null) return;
    if (patchSet.applyStatus == PatchApplyStatus.applied) return;
    reject(patchSet.id);
  }

  void discardActiveForRequest(String requestId, {String? message}) {
    if (state.isApplying) return;
    final patchSet = state.active;
    if (patchSet == null || patchSet.runId != requestId) return;
    if (patchSet.applyStatus == PatchApplyStatus.applied) return;
    state = state.copyWith(
      active: null,
      history: [
        for (final candidate in state.history)
          if (candidate.id != patchSet.id) candidate,
      ],
      message: message ?? 'Patch proposal discarded.',
    );
    _persistSync();
  }

  void reject(String patchSetId) {
    final patchSet = _find(patchSetId);
    if (patchSet == null) return;
    final updated = patchSet.copyWith(
      approvalStatus: PatchApprovalStatus.rejected,
      applyStatus: PatchApplyStatus.rejected,
    );
    state = state.copyWith(
      active: state.active?.id == patchSetId ? null : state.active,
      history: _replace(updated),
      message: 'Patch rejected.',
    );
    _persistSync();
    ref.read(workItemProvider.notifier).recordPatchSet(updated);
    _syncAgentTask(updated);
    _recordPatchTransaction(
      updated,
      PatchApplyResult(
        status: PatchApplyStatus.rejected,
        message: 'Patch rejected.',
        changedFiles: updated.changedFiles,
        checkpointId: updated.checkpointId,
        diffSummary: updated.diffSummary,
        verificationSuggestions: updated.verificationSuggestions,
        verificationRequested: updated.verificationRequested,
      ),
    );
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
    _persistSync();
    ref.read(workItemProvider.notifier).recordPatchSet(updated);
    _syncAgentTask(updated);
    _recordPatchTransaction(
      updated,
      PatchApplyResult(
        status: PatchApplyStatus.revisionRequested,
        message: 'Patch revision requested.',
        conflictMessage: request.prompt,
        changedFiles: updated.changedFiles,
        checkpointId: updated.checkpointId,
        diffSummary: updated.diffSummary,
        verificationSuggestions: updated.verificationSuggestions,
        verificationRequested: updated.verificationRequested,
      ),
      titleOverride: 'Patch revision requested',
    );
  }

  void dismissConflict(String patchSetId) {
    final patchSet = _find(patchSetId);
    if (patchSet == null || patchSet.applyStatus != PatchApplyStatus.conflict) {
      return;
    }
    final updated = patchSet.copyWith(applyStatus: null, conflictMessage: null);
    state = state.copyWith(
      active: state.active?.id == patchSetId ? updated : state.active,
      history: _replace(updated),
      message: 'Patch conflict dismissed.',
    );
    _persistSync();
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
    final preflightFailure = await _preflightCheckpointRestore(
      rootPath,
      checkpoint,
    );
    if (preflightFailure != null) return preflightFailure;
    final restored = <String>[];
    try {
      for (final snapshot in checkpoint.snapshots) {
        final fullPath = _resolve(rootPath, snapshot.path);
        if (fullPath == null) continue;
        if (_pathTraversesSymlink(rootPath, fullPath)) {
          return PatchApplyResult(
            status: PatchApplyStatus.failed,
            checkpointId: checkpointId,
            message:
                'Checkpoint restore refused because ${snapshot.path} traverses a symlink.',
          );
        }
        final file = File(fullPath);
        if (snapshot.wasCreated) {
          if (await file.exists()) await file.delete();
          await _removeCreatedParentDirs(rootPath, snapshot.createdParentDirs);
        } else if (snapshot.originalContent != null) {
          await file.parent.create(recursive: true);
          await file.writeAsString(snapshot.originalContent!);
        }
        restored.add(snapshot.path);
      }
      await ref.read(fileTreeProvider.notifier).refresh();
      final patchSet = _findByCheckpoint(checkpointId);
      if (patchSet != null) {
        final updated = patchSet.copyWith(
          applyStatus: PatchApplyStatus.restored,
          changedFiles: restored,
          conflictMessage: null,
        );
        state = state.copyWith(
          active: state.active?.id == updated.id ? updated : state.active,
          history: _replace(updated),
          message: 'Restored ${restored.length} files.',
        );
        await _persist();
        ref.read(workItemProvider.notifier).recordPatchSet(updated);
        _syncAgentTask(updated);
        _recordPatchTransaction(
          updated,
          PatchApplyResult(
            status: PatchApplyStatus.restored,
            changedFiles: restored,
            checkpointId: checkpointId,
            message: 'Restored ${restored.length} files.',
          ),
        );
      }
      ref
          .read(agentRunProvider.notifier)
          .addEvent(
            AgentRunKind.chat,
            AgentRunEventType.patchApply,
            'Patch checkpoint restored',
            metadata: {
              'checkpointId': checkpointId,
              'restoredFiles': restored.length.toString(),
            },
          );
      return PatchApplyResult(
        status: PatchApplyStatus.restored,
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

  Future<PatchApplyResult?> _preflightCheckpointRestore(
    String rootPath,
    Checkpoint checkpoint,
  ) async {
    for (final snapshot in checkpoint.snapshots) {
      final fullPath = _resolve(rootPath, snapshot.path);
      if (fullPath == null) {
        return PatchApplyResult(
          status: PatchApplyStatus.failed,
          checkpointId: checkpoint.id,
          message:
              'Checkpoint restore refused because ${snapshot.path} is outside the workspace.',
        );
      }
      if (_pathTraversesSymlink(rootPath, fullPath)) {
        return PatchApplyResult(
          status: PatchApplyStatus.failed,
          checkpointId: checkpoint.id,
          message:
              'Checkpoint restore refused because ${snapshot.path} traverses a symlink.',
        );
      }
      if (await FileSystemEntity.isDirectory(fullPath)) {
        return PatchApplyResult(
          status: PatchApplyStatus.failed,
          checkpointId: checkpoint.id,
          message:
              'Checkpoint restore refused because ${snapshot.path} is now a directory.',
        );
      }
      if (!snapshot.wasCreated && snapshot.originalContent != null) {
        final file = File(fullPath);
        final obstructingAncestor = await _firstNonDirectoryAncestor(
          rootPath,
          file.parent.path,
        );
        if (obstructingAncestor != null) {
          return PatchApplyResult(
            status: PatchApplyStatus.failed,
            checkpointId: checkpoint.id,
            message:
                'Checkpoint restore refused because ${p.relative(obstructingAncestor, from: rootPath)} is not a directory.',
          );
        }
        final parentType = await FileSystemEntity.type(file.parent.path);
        if (parentType != FileSystemEntityType.notFound &&
            parentType != FileSystemEntityType.directory) {
          return PatchApplyResult(
            status: PatchApplyStatus.failed,
            checkpointId: checkpoint.id,
            message:
                'Checkpoint restore refused because ${snapshot.path} has a non-directory parent.',
          );
        }
      }
    }
    return null;
  }

  ProposedPatchSet? _find(String id) {
    if (state.active?.id == id) return state.active;
    return state.history.where((patchSet) => patchSet.id == id).firstOrNull;
  }

  ProposedPatchSet? _findByCheckpoint(String checkpointId) {
    if (state.active?.checkpointId == checkpointId) return state.active;
    return state.history
        .where((patchSet) => patchSet.checkpointId == checkpointId)
        .firstOrNull;
  }

  Future<Object?> _readPatchTargetText(File file, String displayPath) async {
    try {
      return await file.readAsString();
    } on FormatException {
      return PatchApplyResult(
        status: PatchApplyStatus.conflict,
        conflictMessage:
            'Patch target is not readable as UTF-8 text: $displayPath. Ask Circuit to revise the patch or skip this binary file.',
      );
    } on FileSystemException catch (error) {
      if (error.message.toLowerCase().contains('decode')) {
        return PatchApplyResult(
          status: PatchApplyStatus.conflict,
          conflictMessage:
              'Patch target is not readable as UTF-8 text: $displayPath. Ask Circuit to revise the patch or skip this binary file.',
        );
      }
      return PatchApplyResult(
        status: PatchApplyStatus.conflict,
        conflictMessage:
            'Patch target could not be read before applying: $displayPath (${error.message}).',
      );
    }
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
      diffSummary: result.diffSummary,
      verificationSuggestions: result.verificationSuggestions,
      verificationRequested:
          result.verificationRequested || patchSet.verificationRequested,
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
    await _persist();
    if (!ref.mounted) return result;
    await ref.read(fileTreeProvider.notifier).refresh();
    if (!ref.mounted) return result;
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
    _recordPatchTransaction(updated, result);
    return result;
  }

  void _recordPatchTransaction(
    ProposedPatchSet patchSet,
    PatchApplyResult result, {
    String? titleOverride,
  }) {
    final requestId = patchSet.runId;
    if (requestId == null || requestId.trim().isEmpty) return;
    ref
        .read(studioTurnProvider.notifier)
        .recordPatchTransaction(
          requestId,
          patchSetId: patchSet.id,
          title: titleOverride ?? _patchTransactionTitle(result.status),
          detail: _patchTransactionDetail(patchSet, result),
          paths: _patchTransactionPaths(patchSet, result),
          applyStatus: result.status,
        );
  }

  List<String> _patchTransactionPaths(
    ProposedPatchSet patchSet,
    PatchApplyResult result,
  ) {
    if (result.changedFiles.isNotEmpty) return result.changedFiles;
    final conflict = result.conflictMessage ?? result.message ?? '';
    final explicitPath = _pathFromPatchMessage(conflict);
    if (explicitPath != null) return [explicitPath];
    return patchSet.edits.map((edit) => edit.path).toList(growable: false);
  }

  String? _pathFromPatchMessage(String message) {
    final trimmed = message.trim();
    final patterns = [
      RegExp(r':\s*([^\n]+)$'),
      RegExp(
        r'\bfor\s+([^\n]+?)(?:\. Ask\b|\. Revise\b| before\b| on line\b|$)',
        caseSensitive: false,
      ),
      RegExp(r'\bin\s+([^\n]+?)\s+on line\b', caseSensitive: false),
      RegExp(r'\bPatch leaves\s+([^\n]+?)\s+empty\b', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(trimmed);
      final path = _cleanExtractedPatchPath(match?.group(1));
      if (path != null) return path;
    }
    return null;
  }

  String? _cleanExtractedPatchPath(String? value) {
    final initial = value?.trim();
    if (initial == null || initial.isEmpty) return null;
    var path = initial
        .replaceAll(RegExp(r'''^[`"']+|[`"']+$'''), '')
        .replaceAll(RegExp(r'\s*\([^)]*\)$'), '')
        .trim();
    while (path.isNotEmpty && ',.;:'.contains(path[path.length - 1])) {
      path = path.substring(0, path.length - 1).trim();
    }
    if (path.isEmpty) return null;
    if (path.contains(' ') && !path.contains('/')) return null;
    return path;
  }

  String _patchTransactionTitle(PatchApplyStatus status) => switch (status) {
    PatchApplyStatus.applied => 'Applied changes',
    PatchApplyStatus.restored => 'Restored checkpoint',
    PatchApplyStatus.conflict => 'Patch conflict',
    PatchApplyStatus.failed => 'Patch apply failed',
    PatchApplyStatus.rejected => 'Patch rejected',
    PatchApplyStatus.revisionRequested => 'Patch revision requested',
  };

  String _patchTransactionDetail(
    ProposedPatchSet patchSet,
    PatchApplyResult result,
  ) {
    if (result.applied) {
      final lines = <String>[
        result.message ?? 'Applied ${result.changedFiles.length} files.',
        if (result.changedFiles.isNotEmpty)
          'Here’s what changed: ${result.changedFiles.join(', ')}',
        if (result.checkpointId != null) 'Checkpoint: ${result.checkpointId}',
        if ((result.diffSummary ?? '').trim().isNotEmpty)
          result.diffSummary!.trim(),
        if (result.verificationSuggestions.isNotEmpty)
          'Suggested checks: ${result.verificationSuggestions.join(' · ')}',
        if (result.verificationSuggestions.isNotEmpty)
          'Recommended next step: run the suggested checks to verify the applied changes.',
        if (result.verificationSuggestions.isEmpty &&
            !result.verificationRequested)
          'Recommended next step: review the changed files, then continue with the next batch or ask for revisions.',
        if (result.verificationRequested)
          'Verification was requested for this patch.',
      ];
      return lines.where((line) => line.trim().isNotEmpty).join('\n');
    }
    final lines = <String>[
      result.message ??
          result.conflictMessage ??
          '${_patchTransactionTitle(result.status)}.',
      if (result.changedFiles.isNotEmpty)
        'Files: ${result.changedFiles.join(', ')}',
      if (result.checkpointId != null) 'Checkpoint: ${result.checkpointId}',
      if ((result.diffSummary ?? '').trim().isNotEmpty)
        result.diffSummary!.trim(),
      if (result.verificationSuggestions.isNotEmpty)
        'Suggested checks: ${result.verificationSuggestions.join(' · ')}',
      if (result.verificationSuggestions.isNotEmpty)
        'Recommended next step: run the suggested checks to verify this patch state.',
      if (result.verificationRequested)
        'Verification was requested for this patch.',
      if (result.conflictMessage != null &&
          result.conflictMessage != result.message)
        result.conflictMessage!,
      if (patchSet.title.trim().isNotEmpty) 'Patch: ${patchSet.title}',
    ];
    return lines.where((line) => line.trim().isNotEmpty).join('\n');
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
    return replaced;
  }

  Future<void> _persist() async {
    if (!ref.mounted) return;
    final rootPath = ref.read(fileTreeProvider).rootPath;
    final snapshot = state;
    try {
      await ref.read(patchProposalStoreProvider).save(rootPath, snapshot);
    } catch (_) {
      // Persistence should not block the active review/apply path. The visible
      // transaction result is still recorded on the Studio turn.
    }
  }

  void _persistSync() {
    if (!ref.mounted) return;
    final rootPath = ref.read(fileTreeProvider).rootPath;
    final snapshot = state;
    try {
      ref.read(patchProposalStoreProvider).saveSync(rootPath, snapshot);
    } catch (_) {
      unawaited(_persist());
    }
  }

  void _syncAgentTask(ProposedPatchSet patchSet) {
    final taskId = patchSet.agentTaskId;
    if (taskId == null) return;
    ref.read(agentWorkspaceProvider.notifier).attachPatchSet(taskId, patchSet);
  }

  String? _resolve(String rootPath, String targetPath) {
    final sanitized = _sanitizePatchPathInput(targetPath);
    if (sanitized.trim().isEmpty) return null;
    if (_hasUnsafePatchPathCharacters(sanitized)) return null;
    if (_looksLikeWindowsAbsolutePath(sanitized)) return null;
    final normalized = p.normalize(
      p.isAbsolute(sanitized) ? sanitized : p.join(rootPath, sanitized),
    );
    if (normalized == rootPath || !p.isWithin(rootPath, normalized)) {
      return null;
    }
    return normalized;
  }

  String _normalizePatchPathForDisplay(String rootPath, String targetPath) {
    final trimmed = _sanitizePatchPathInput(targetPath).trim();
    if (trimmed.isEmpty) return targetPath;
    if (_looksLikeWindowsAbsolutePath(trimmed)) return trimmed;
    final root = p.normalize(rootPath);
    final normalized = p.normalize(
      p.isAbsolute(trimmed) ? trimmed : p.join(root, trimmed),
    );
    if (normalized != root && p.isWithin(root, normalized)) {
      return p.relative(normalized, from: root);
    }
    return p.normalize(trimmed);
  }

  String _sanitizePatchPathInput(String targetPath) {
    return targetPath.trim().replaceAll('\\', '/');
  }

  bool _hasUnsafePatchPathCharacters(String sanitizedPath) {
    return sanitizedPath.codeUnits.any((unit) => unit < 32 || unit == 127);
  }

  bool _looksLikeWindowsAbsolutePath(String sanitizedPath) {
    return RegExp(r'^[A-Za-z]:/').hasMatch(sanitizedPath) ||
        sanitizedPath.startsWith('//');
  }

  bool _looksSecretPatchPath(String targetPath) {
    final normalized = _sanitizePatchPathInput(targetPath).toLowerCase();
    return normalized == '.env' ||
        normalized.startsWith('.env.') ||
        normalized.contains('/.env') ||
        normalized.contains('secret') ||
        normalized.contains('credentials') ||
        normalized == '.npmrc' ||
        normalized.endsWith('/.npmrc') ||
        normalized == '.netrc' ||
        normalized.endsWith('/.netrc') ||
        normalized == 'id_rsa' ||
        normalized.endsWith('/id_rsa') ||
        normalized == 'id_ed25519' ||
        normalized.endsWith('/id_ed25519') ||
        normalized == '.aws' ||
        normalized.startsWith('.aws/') ||
        normalized.contains('/.aws/');
  }

  bool _pathTraversesSymlink(String rootPath, String fullPath) {
    final root = p.normalize(rootPath);
    final relative = p.relative(fullPath, from: root);
    if (relative == '.') return false;

    var current = root;
    for (final segment in p.split(relative)) {
      if (segment.isEmpty || segment == '.') continue;
      current = p.join(current, segment);
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        return true;
      }
    }
    return false;
  }

  Future<String?> _firstNonDirectoryAncestor(
    String rootPath,
    String parentPath,
  ) async {
    final root = p.normalize(rootPath);
    final parent = p.normalize(parentPath);
    if (parent == root || !p.isWithin(root, parent)) return null;

    var current = root;
    for (final segment in p.split(p.relative(parent, from: root))) {
      if (segment.isEmpty || segment == '.') continue;
      current = p.join(current, segment);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.directory) return current;
    }
    return null;
  }

  Future<void> _restoreSnapshots(
    String rootPath,
    List<FileSnapshot> snapshots,
  ) async {
    for (final snapshot in snapshots.reversed) {
      final fullPath = _resolve(rootPath, snapshot.path);
      if (fullPath == null) continue;
      if (_pathTraversesSymlink(rootPath, fullPath)) continue;
      final file = File(fullPath);
      if (snapshot.wasCreated) {
        if (await file.exists()) await file.delete();
        await _removeCreatedParentDirs(rootPath, snapshot.createdParentDirs);
      } else if (snapshot.originalContent != null) {
        await file.parent.create(recursive: true);
        await file.writeAsString(snapshot.originalContent!);
      }
    }
  }

  String _diffSummary(ProposedPatchSet patchSet) {
    if (patchSet.edits.isEmpty) return 'No file edits were included.';
    return patchSet.edits
        .map((edit) {
          final beforeLines = edit.before?.split('\n').length ?? 0;
          final afterLines = edit.after?.split('\n').length ?? 0;
          final verb = switch (edit.type) {
            ProposedFileEditType.create => 'Created',
            ProposedFileEditType.modify => 'Modified',
            ProposedFileEditType.delete => 'Deleted',
          };
          final delta = afterLines - beforeLines;
          final suffix = delta == 0
              ? ''
              : delta > 0
              ? ' (+$delta lines)'
              : ' ($delta lines)';
          return '- $verb ${edit.path}$suffix';
        })
        .join('\n');
  }

  bool _allowsEmptyPatchContent(String path) {
    final basename = p.basename(path).toLowerCase();
    return basename == '.gitkeep' ||
        basename == '.keep' ||
        basename == 'placeholder';
  }

  List<String> _verificationSuggestions(String rootPath) {
    final suggestions = <String>[];
    final packageJson = File(p.join(rootPath, 'package.json'));
    if (packageJson.existsSync()) {
      try {
        final json = jsonDecode(packageJson.readAsStringSync());
        if (json is Map<String, dynamic>) {
          final scripts = json['scripts'];
          if (scripts is Map) {
            if (verification_command_filter.isSafePackageScriptBody(
              scripts['test'],
            )) {
              suggestions.add('npm test');
            }
            if (verification_command_filter.isSafePackageScriptBody(
              scripts['lint'],
            )) {
              suggestions.add('npm run lint');
            }
            if (verification_command_filter.isSafePackageScriptBody(
              scripts['build'],
            )) {
              suggestions.add('npm run build');
            }
          }
        }
      } catch (_) {}
    }
    if (File(p.join(rootPath, 'pubspec.yaml')).existsSync()) {
      suggestions.addAll(['flutter analyze', 'flutter test']);
    }
    if (File(p.join(rootPath, 'pyproject.toml')).existsSync() ||
        File(p.join(rootPath, 'pytest.ini')).existsSync()) {
      suggestions.add('python -m pytest');
    }
    if (File(p.join(rootPath, 'Cargo.toml')).existsSync()) {
      suggestions.add('cargo test');
    }
    if (File(p.join(rootPath, 'go.mod')).existsSync()) {
      suggestions.add('go test ./...');
    }
    final makefile = File(p.join(rootPath, 'Makefile'));
    if (makefile.existsSync()) {
      final text = makefile.readAsStringSync();
      final targets = RegExp(
        r'^([A-Za-z0-9_.-]+):',
        multiLine: true,
      ).allMatches(text).map((match) => match.group(1) ?? '').toSet();
      if (targets.contains('test')) suggestions.add('make test');
      if (targets.contains('lint')) suggestions.add('make lint');
      if (targets.contains('build')) suggestions.add('make build');
    }
    return suggestions.toSet().take(5).toList();
  }

  List<String> _verificationSuggestionsForPatch(
    String rootPath,
    ProposedPatchSet patchSet,
  ) {
    final detected = _verificationSuggestions(rootPath);
    if (detected.isNotEmpty) return detected;
    if (patchSet.verificationSuggestions.isNotEmpty) {
      return patchSet.verificationSuggestions
          .where(verification_command_filter.isRunnableVerificationCommand)
          .toSet()
          .take(5)
          .toList();
    }
    if (patchSet.verificationRequested) {
      return const ['Run the relevant project checks for the changed files.'];
    }
    return const [];
  }

  List<String> _missingParentDirectories(String rootPath, String fullPath) {
    final root = p.normalize(rootPath);
    final parent = p.normalize(p.dirname(fullPath));
    if (parent == root || !p.isWithin(root, parent)) return const [];
    final missing = <String>[];
    var current = parent;
    while (current != root && p.isWithin(root, current)) {
      if (!Directory(current).existsSync()) {
        missing.add(p.relative(current, from: root));
      }
      current = p.dirname(current);
    }
    return missing;
  }

  Future<void> _removeCreatedParentDirs(
    String rootPath,
    List<String> createdParentDirs,
  ) async {
    for (final relativeDir in createdParentDirs) {
      final fullPath = _resolve(rootPath, relativeDir);
      if (fullPath == null) continue;
      if (_pathTraversesSymlink(rootPath, fullPath)) continue;
      final dir = Directory(fullPath);
      if (!await dir.exists()) continue;
      try {
        if (await dir.list().isEmpty) await dir.delete();
      } catch (_) {
        // Best effort cleanup: leave non-empty or inaccessible directories.
      }
    }
  }
}

final patchProposalProvider =
    NotifierProvider<PatchProposalController, PatchProposalState>(
      PatchProposalController.new,
    );

class _PreparedPatchEdit {
  final ProposedFileEdit edit;
  final String fullPath;

  const _PreparedPatchEdit({required this.edit, required this.fullPath});
}

const _sentinel = Object();
