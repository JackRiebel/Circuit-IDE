part of 'patch_proposal_provider.dart';

mixin PatchProposalExecution on Notifier<PatchProposalState> {
  Future<PatchApplyResult> _finishApply(
    ProposedPatchSet patchSet,
    PatchApplyResult result, {
    Checkpoint? checkpoint,
  });

  String _sanitizePatchPathInput(String targetPath);
  bool _hasUnsafePatchPathCharacters(String sanitizedPath);
  bool _looksSecretPatchPath(String targetPath);
  String? _resolve(String rootPath, String targetPath);
  bool _pathTraversesSymlink(String rootPath, String fullPath);
  Future<String?> _firstNonDirectoryAncestor(
    String rootPath,
    String parentPath,
  );
  bool _allowsEmptyPatchContent(String path);
  List<String> _missingParentDirectories(String rootPath, String fullPath);
  List<String> _verificationSuggestionsForPatch(
    String rootPath,
    ProposedPatchSet patchSet,
  );
  String _diffSummary(ProposedPatchSet patchSet);
  Future<void> _restoreSnapshots(String rootPath, List<FileSnapshot> snapshots);
  Future<void> _removeCreatedParentDirs(
    String rootPath,
    List<String> createdParentDirs,
  );
  List<ProposedPatchSet> _replace(ProposedPatchSet updated);
  Future<void> _persist();
  void _syncAgentTask(ProposedPatchSet patchSet);
  void _recordPatchTransaction(
    ProposedPatchSet patchSet,
    PatchApplyResult result,
  );

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
    final patchStore = ref.read(patchProposalStoreProvider);
    var journalWritten = false;

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

      // Applying a reviewed patch is an app-owned transaction, but it still
      // goes through the one executable tool policy before any workspace write.
      // Preserve the controller's detailed validation errors above, then gate
      // the fully validated transaction through the shared policy boundary.
      final policy = AgentToolPermissionPolicy(
        workingDir: rootPath,
        request: const ToolPermissionRequest(
          intent: TurnIntent.code,
          phase: ToolPermissionPhase.apply,
          allowPatchTransaction: true,
        ),
      );
      final decision = policy.evaluate(
        ToolCallInfo(
          id: 'patch-apply-${patchSet.id}',
          name: 'apply_patch_set',
          arguments: {
            'files': [
              for (final item in prepared) {'path': item.edit.path},
            ],
          },
        ),
      );
      if (!decision.allowed) {
        return _finishApply(
          patchSet,
          PatchApplyResult(
            status: PatchApplyStatus.conflict,
            conflictMessage: 'Patch application blocked: ${decision.message}',
          ),
        );
      }

      final checkpoint = Checkpoint(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        description: 'Applied patch proposal: ${patchSet.title}',
        snapshots: snapshots,
        patchSetId: patchSet.id,
        workItemId: patchSet.workItemId,
      );
      // This durable, flushed journal is the first side effect in the apply
      // transaction. Every later mutation can be reverted after a forced quit.
      await patchStore.writeApplyJournal(
        PatchApplyJournal(
          transactionId: _uuid.v4(),
          workspaceRoot: rootPath,
          patchSetId: patchSet.id,
          checkpointId: checkpoint.id,
          preparedAt: DateTime.now(),
          snapshots: snapshots,
        ),
      );
      journalWritten = true;

      var completedMutations = 0;
      for (final item in prepared) {
        final edit = item.edit;
        final file = File(item.fullPath);
        switch (edit.type) {
          case ProposedFileEditType.create:
          case ProposedFileEditType.modify:
            await writePatchFileAtomically(file, edit.after ?? '');
            changedFiles.add(edit.path);
            break;
          case ProposedFileEditType.delete:
            if (await file.exists()) await file.delete();
            changedFiles.add(edit.path);
            break;
        }
        completedMutations++;
        await patchStore.notifyMutationApplied(completedMutations);
      }

      final verificationSuggestions = _verificationSuggestionsForPatch(
        rootPath,
        patchSet,
      );
      final result = await _finishApply(
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
      await patchStore.clearApplyJournal(rootPath);
      return result;
    } catch (error) {
      if (error is PatchApplySimulatedCrash) {
        return _finishApply(
          patchSet,
          const PatchApplyResult(
            status: PatchApplyStatus.failed,
            message:
                'Patch application was interrupted for crash-recovery testing. The pending journal will restore the workspace on restart.',
          ),
        );
      }
      var message = error.toString();
      if (journalWritten) {
        try {
          await patchStore.recoverPendingApply(rootPath);
        } catch (recoveryError) {
          message =
              '$message; automatic recovery is still pending: $recoveryError';
        }
      } else {
        await _restoreSnapshots(rootPath, snapshots);
      }
      return _finishApply(
        patchSet,
        PatchApplyResult(status: PatchApplyStatus.failed, message: message),
      );
    }
  }

  Future<CheckpointRestorePreview?> previewCheckpointRestore(
    String checkpointId,
  ) async {
    final checkpoint = state.checkpoints[checkpointId];
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (checkpoint == null || rootPath == null) return null;
    try {
      return _buildCheckpointRestorePreview(rootPath, checkpoint);
    } catch (_) {
      return null;
    }
  }

  /// Restores a checkpoint through the same durable transaction journal used
  /// for patch application. Callers must deliberately opt into overwriting
  /// files changed after the patch by setting [allowOverwrite] after showing a
  /// [previewCheckpointRestore] result to the user.
  Future<PatchApplyResult> restoreCheckpoint(
    String checkpointId, {
    bool allowOverwrite = false,
  }) async {
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
    final preview = await _buildCheckpointRestorePreview(rootPath, checkpoint);
    if (preview.hasLaterUserChanges && !allowOverwrite) {
      final changed = preview.files
          .where((file) => file.requiresOverwrite)
          .map((file) => file.path)
          .join(', ');
      return PatchApplyResult(
        status: PatchApplyStatus.conflict,
        checkpointId: checkpointId,
        changedFiles: preview.files.map((file) => file.path).toList(),
        conflictMessage:
            'Checkpoint restore paused because these files changed after the patch: $changed. Review the restore preview and explicitly confirm overwriting them.',
        message: 'Checkpoint restore needs confirmation.',
      );
    }

    final rollbackSnapshots = <FileSnapshot>[];
    try {
      for (final snapshot in checkpoint.snapshots) {
        rollbackSnapshots.add(
          await _captureCheckpointRestoreSnapshot(rootPath, snapshot),
        );
      }
    } catch (error) {
      return PatchApplyResult(
        status: PatchApplyStatus.failed,
        checkpointId: checkpointId,
        message: 'Could not capture a reversible restore checkpoint: $error',
      );
    }

    final patchSet = _patchForCheckpoint(checkpoint);
    final rollbackCheckpoint = Checkpoint(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      description: 'Before restoring checkpoint: ${checkpoint.description}',
      snapshots: rollbackSnapshots,
      patchSetId: patchSet?.id ?? checkpoint.patchSetId,
      workItemId: patchSet?.workItemId ?? checkpoint.workItemId,
      restoresCheckpointId: checkpoint.id,
    );
    final restored = <String>[];
    final patchStore = ref.read(patchProposalStoreProvider);
    var journalWritten = false;
    state = state.copyWith(
      isApplying: true,
      message: 'Restoring checkpoint preview…',
    );
    try {
      for (final snapshot in checkpoint.snapshots) {
        final fullPath = _resolve(rootPath, snapshot.path);
        if (fullPath == null) throw StateError('Unsafe checkpoint path.');
      }
      await patchStore.writeApplyJournal(
        PatchApplyJournal(
          transactionId: _uuid.v4(),
          workspaceRoot: rootPath,
          patchSetId: patchSet?.id ?? 'checkpoint-restore',
          checkpointId: rollbackCheckpoint.id,
          preparedAt: DateTime.now(),
          snapshots: rollbackSnapshots,
          operation: PatchApplyOperation.checkpointRestore,
        ),
      );
      journalWritten = true;

      var completedMutations = 0;
      for (final snapshot in checkpoint.snapshots) {
        final fullPath = _resolve(rootPath, snapshot.path)!;
        final file = File(fullPath);
        if (snapshot.wasCreated) {
          if (await file.exists()) await file.delete();
        } else if (snapshot.originalContent != null) {
          await writePatchFileAtomically(file, snapshot.originalContent!);
        }
        restored.add(snapshot.path);
        completedMutations++;
        await patchStore.notifyMutationApplied(completedMutations);
      }
      for (final snapshot in checkpoint.snapshots.reversed) {
        if (!snapshot.wasCreated) continue;
        await _removeCreatedParentDirs(rootPath, snapshot.createdParentDirs);
      }
      await ref.read(fileTreeProvider.notifier).refresh();
      if (patchSet != null) {
        final updated = patchSet.copyWith(
          applyStatus: PatchApplyStatus.restored,
          changedFiles: restored,
          conflictMessage: null,
        );
        state = state.copyWith(
          active: state.active?.id == updated.id ? updated : state.active,
          history: _replace(updated),
          checkpoints: {
            ...state.checkpoints,
            rollbackCheckpoint.id: rollbackCheckpoint,
          },
          isApplying: false,
          message:
              'Restored ${restored.length} files. A reversible restore checkpoint was saved.',
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
            message:
                'Restored ${restored.length} files. A reversible restore checkpoint was saved.',
          ),
        );
      } else {
        state = state.copyWith(
          checkpoints: {
            ...state.checkpoints,
            rollbackCheckpoint.id: rollbackCheckpoint,
          },
          isApplying: false,
          message:
              'Restored ${restored.length} files. A reversible restore checkpoint was saved.',
        );
        await _persist();
      }
      await patchStore.clearApplyJournal(rootPath);
      return PatchApplyResult(
        status: PatchApplyStatus.restored,
        changedFiles: restored,
        checkpointId: checkpointId,
        message:
            'Restored ${restored.length} files. A reversible restore checkpoint was saved.',
      );
    } catch (error) {
      if (error is PatchApplySimulatedCrash) {
        state = state.copyWith(
          isApplying: false,
          message:
              'Checkpoint restore was interrupted for crash-recovery testing. The workspace will be restored to its pre-restore state on restart.',
        );
        return const PatchApplyResult(
          status: PatchApplyStatus.failed,
          message:
              'Checkpoint restore was interrupted. Recovery is pending on restart.',
        );
      }
      var message = error.toString();
      if (journalWritten) {
        try {
          await patchStore.recoverPendingApply(rootPath);
          message =
              '$message; restored the workspace to its pre-restore state.';
        } catch (recoveryError) {
          message =
              '$message; automatic recovery is still pending: $recoveryError';
        }
      }
      state = state.copyWith(isApplying: false, message: message);
      return PatchApplyResult(
        status: PatchApplyStatus.failed,
        checkpointId: checkpointId,
        message: message,
      );
    }
  }

  Future<CheckpointRestorePreview> _buildCheckpointRestorePreview(
    String rootPath,
    Checkpoint checkpoint,
  ) async {
    final patchSet = _patchForCheckpoint(checkpoint);
    final files = <CheckpointRestoreFilePreview>[];
    for (final snapshot in checkpoint.snapshots) {
      final current = await _readCheckpointTargetContent(rootPath, snapshot);
      final restoreTarget = snapshot.wasCreated
          ? null
          : snapshot.originalContent;
      final expectedCurrent = _expectedCheckpointCurrent(
        checkpoint,
        snapshot,
        patchSet,
      );
      final state = current == restoreTarget
          ? CheckpointRestoreFileState.alreadyRestored
          : current == expectedCurrent
          ? CheckpointRestoreFileState.ready
          : CheckpointRestoreFileState.laterUserChange;
      files.add(
        CheckpointRestoreFilePreview(path: snapshot.path, state: state),
      );
    }
    return CheckpointRestorePreview(
      checkpoint: checkpoint,
      patchSet: patchSet,
      files: files,
    );
  }

  ProposedPatchSet? _patchForCheckpoint(Checkpoint checkpoint) {
    final patchSetId = checkpoint.patchSetId;
    if (patchSetId != null) return _find(patchSetId);
    return _findByCheckpoint(checkpoint.id);
  }

  String? _expectedCheckpointCurrent(
    Checkpoint checkpoint,
    FileSnapshot snapshot,
    ProposedPatchSet? patchSet,
  ) {
    final restoredCheckpointId = checkpoint.restoresCheckpointId;
    if (restoredCheckpointId != null) {
      final source = state.checkpoints[restoredCheckpointId];
      final sourceSnapshot = source?.snapshots
          .where((candidate) => candidate.path == snapshot.path)
          .firstOrNull;
      if (sourceSnapshot != null) {
        return sourceSnapshot.wasCreated
            ? null
            : sourceSnapshot.originalContent;
      }
    }
    final edit = patchSet?.edits
        .where((candidate) => candidate.path == snapshot.path)
        .firstOrNull;
    if (edit == null) {
      return snapshot.wasCreated ? null : snapshot.originalContent;
    }
    return switch (edit.type) {
      ProposedFileEditType.create || ProposedFileEditType.modify => edit.after,
      ProposedFileEditType.delete => null,
    };
  }

  Future<String?> _readCheckpointTargetContent(
    String rootPath,
    FileSnapshot snapshot,
  ) async {
    final fullPath = _resolve(rootPath, snapshot.path);
    if (fullPath == null) throw StateError('Unsafe checkpoint path.');
    final type = await FileSystemEntity.type(fullPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw StateError('${snapshot.path} is no longer a regular file.');
    }
    return File(fullPath).readAsString();
  }

  Future<FileSnapshot> _captureCheckpointRestoreSnapshot(
    String rootPath,
    FileSnapshot target,
  ) async {
    final fullPath = _resolve(rootPath, target.path);
    if (fullPath == null) throw StateError('Unsafe checkpoint path.');
    final type = await FileSystemEntity.type(fullPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return FileSnapshot(
        path: target.path,
        originalContent: null,
        wasCreated: true,
        createdParentDirs: _missingParentDirectories(rootPath, fullPath),
      );
    }
    if (type != FileSystemEntityType.file) {
      throw StateError('${target.path} is no longer a regular file.');
    }
    return FileSnapshot(
      path: target.path,
      originalContent: await File(fullPath).readAsString(),
    );
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
}
