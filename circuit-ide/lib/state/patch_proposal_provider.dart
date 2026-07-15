import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../agent/security/agent_tool_permission_policy.dart';
import '../agent/verification_command_filter.dart'
    as verification_command_filter;
import '../agent/security/secret_detector.dart';
import '../models/agent_tool_permission.dart';
import '../models/checkpoint.dart';
import '../models/reviewed_edit.dart';
import '../models/tool_call_info.dart';
import '../models/turn_intent.dart';
import 'agent_workspace_provider.dart';
import 'diff_preview_provider.dart';
import 'file_tree_provider.dart';
import 'project_profile_provider.dart';
import 'patch_proposal_storage.dart';
import 'studio_turn_provider.dart';
import 'work_item_provider.dart';

export 'patch_proposal_storage.dart';

part 'patch_proposal_execution.dart';

const _uuid = Uuid();
final _secretDetector = SecretDetector();

/// Test-only seam for simulating an abrupt process termination after a
/// workspace mutation. Production stores never set this callback.
class PatchProposalRevisionRequest {
  final String patchSetId;
  final String prompt;

  const PatchProposalRevisionRequest({
    required this.patchSetId,
    required this.prompt,
  });
}

class PatchProposalController extends Notifier<PatchProposalState>
    with PatchProposalExecution {
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
      final store = ref.read(patchProposalStoreProvider);
      final recovery = rootPath == null
          ? null
          : await store.recoverPendingApply(rootPath);
      var loaded = await store.load(rootPath);
      if (recovery != null) {
        loaded = _stateAfterInterruptedApplyRecovery(loaded, recovery);
        await store.save(rootPath, loaded);
      }
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

  PatchProposalState _stateAfterInterruptedApplyRecovery(
    PatchProposalState loaded,
    PatchApplyRecovery recovery,
  ) {
    if (recovery.operation == PatchApplyOperation.checkpointRestore) {
      return loaded.copyWith(
        checkpoints: {...loaded.checkpoints}..remove(recovery.checkpointId),
        isApplying: false,
        message:
            'Recovered an interrupted checkpoint restore and restored the workspace to its pre-restore state.',
      );
    }
    const message =
        'Recovered an interrupted patch application and restored the workspace.';
    ProposedPatchSet? recoveredPatch;

    ProposedPatchSet repair(ProposedPatchSet patch) {
      if (patch.id != recovery.patchSetId) return patch;
      final repaired = patch.copyWith(
        applyStatus: PatchApplyStatus.failed,
        conflictMessage: message,
        changedFiles: const [],
        clearCheckpoint: true,
      );
      recoveredPatch = repaired;
      return repaired;
    }

    final active = loaded.active == null ? null : repair(loaded.active!);
    final history = [for (final patch in loaded.history) repair(patch)];
    final checkpoints = {...loaded.checkpoints}..remove(recovery.checkpointId);
    return loaded.copyWith(
      active: recoveredPatch ?? active,
      history: history,
      checkpoints: checkpoints,
      isApplying: false,
      message: message,
    );
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
    List<String> verificationSuggestions = const [],
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
      verificationSuggestions: verificationSuggestions,
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
    return patchSet;
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

  bool skipConflictedFile(String patchSetId, String path) {
    final patchSet = _find(patchSetId);
    final normalized = path.trim().replaceAll('\\', '/');
    if (patchSet == null || normalized.isEmpty) return false;
    final remaining = patchSet.edits
        .where((edit) => edit.path.replaceAll('\\', '/') != normalized)
        .toList(growable: false);
    if (remaining.length == patchSet.edits.length || remaining.isEmpty) {
      return false;
    }
    final updated = patchSet.copyWith(
      edits: remaining,
      applyStatus: null,
      conflictMessage: null,
      revisionPrompt:
          'Skipped conflicted file $normalized. Remaining non-overlapping edits stay ready for review.',
      changedFiles: [
        ...patchSet.changedFiles.where((file) => file != normalized),
      ],
    );
    state = state.copyWith(
      active: state.active?.id == patchSetId ? updated : state.active,
      history: _replace(updated),
      message:
          'Skipped conflicted file $normalized. Review the remaining edits.',
    );
    _persistSync();
    ref.read(workItemProvider.notifier).recordPatchSet(updated);
    _syncAgentTask(updated);
    _recordPatchTransaction(
      updated,
      PatchApplyResult(
        status: PatchApplyStatus.revisionRequested,
        message: 'Skipped conflicted file $normalized.',
        conflictMessage: 'Skipped conflicted file $normalized.',
        changedFiles: updated.changedFiles,
        checkpointId: updated.checkpointId,
        diffSummary: updated.diffSummary,
        verificationSuggestions: updated.verificationSuggestions,
        verificationRequested: updated.verificationRequested,
      ),
      titleOverride: 'Conflicted file skipped',
    );
    return true;
  }

  /// Returns a non-mutating restore preview for a user-facing confirmation.
  ///
  /// A file is only considered safe when it is still in the exact state the
  /// patch left behind, or it has already been restored. Any other content is
  /// treated as a later user change and requires an explicit overwrite grant.
  @override
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
    _recordPatchTransaction(updated, result);
    return result;
  }

  @override
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

  @override
  List<ProposedPatchSet> _replace(ProposedPatchSet updated) {
    final replaced = [
      updated,
      ...state.history.where((patchSet) => patchSet.id != updated.id),
    ];
    return replaced;
  }

  @override
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

  @override
  void _syncAgentTask(ProposedPatchSet patchSet) {
    final taskId = patchSet.agentTaskId;
    if (taskId == null) return;
    ref.read(agentWorkspaceProvider.notifier).attachPatchSet(taskId, patchSet);
  }

  @override
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

  @override
  String _sanitizePatchPathInput(String targetPath) {
    return targetPath.trim().replaceAll('\\', '/');
  }

  @override
  bool _hasUnsafePatchPathCharacters(String sanitizedPath) {
    return sanitizedPath.codeUnits.any((unit) => unit < 32 || unit == 127);
  }

  bool _looksLikeWindowsAbsolutePath(String sanitizedPath) {
    return RegExp(r'^[A-Za-z]:/').hasMatch(sanitizedPath) ||
        sanitizedPath.startsWith('//');
  }

  @override
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

  @override
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

  @override
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

  @override
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
        await writePatchFileAtomically(file, snapshot.originalContent!);
      }
    }
  }

  @override
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

  @override
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

  @override
  List<String> _verificationSuggestionsForPatch(
    String rootPath,
    ProposedPatchSet patchSet,
  ) {
    final profileChecks = ref
        .read(projectProfileProvider)
        .commands
        .where((command) => command.enabled)
        .map((command) => command.command)
        .where(verification_command_filter.isRunnableVerificationCommand)
        .toSet()
        .take(5)
        .toList(growable: false);
    if (profileChecks.isNotEmpty) return profileChecks;
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

  @override
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

  @override
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
