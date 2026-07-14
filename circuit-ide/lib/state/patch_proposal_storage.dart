import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/utils/platform_utils.dart';
import '../models/checkpoint.dart';
import '../models/reviewed_edit.dart';
import '../services/versioned_json_document.dart';
import 'work_item_provider.dart';

const _sentinel = Object();

/// Test-only seam for simulating an abrupt process termination after a
/// workspace mutation. Production stores never set this callback.
typedef PatchApplyMutationObserver =
    FutureOr<void> Function(int completedMutations);

class PatchApplySimulatedCrash implements Exception {
  const PatchApplySimulatedCrash();

  @override
  String toString() => 'PatchApplySimulatedCrash';
}

class PatchApplyJournal {
  static const schemaVersion = 2;

  final String transactionId;
  final String workspaceRoot;
  final String patchSetId;
  final String checkpointId;
  final DateTime preparedAt;
  final List<FileSnapshot> snapshots;
  final PatchApplyOperation operation;

  const PatchApplyJournal({
    required this.transactionId,
    required this.workspaceRoot,
    required this.patchSetId,
    required this.checkpointId,
    required this.preparedAt,
    required this.snapshots,
    this.operation = PatchApplyOperation.apply,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'transactionId': transactionId,
    'workspaceRoot': workspaceRoot,
    'patchSetId': patchSetId,
    'checkpointId': checkpointId,
    'preparedAt': preparedAt.toIso8601String(),
    'snapshots': snapshots.map((snapshot) => snapshot.toJson()).toList(),
    'operation': operation.name,
  };

  factory PatchApplyJournal.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 1 &&
        schemaVersion != PatchApplyJournal.schemaVersion) {
      throw const FormatException('Unsupported patch apply journal schema.');
    }
    final snapshots = json['snapshots'];
    if (snapshots is! List) {
      throw const FormatException('Patch apply journal snapshots are missing.');
    }
    return PatchApplyJournal(
      transactionId: json['transactionId'] as String,
      workspaceRoot: json['workspaceRoot'] as String,
      patchSetId: json['patchSetId'] as String,
      checkpointId: json['checkpointId'] as String,
      preparedAt: DateTime.parse(json['preparedAt'] as String),
      snapshots: snapshots
          .map((entry) => FileSnapshot.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
      operation: PatchApplyOperation.values.firstWhere(
        (candidate) => candidate.name == json['operation'],
        orElse: () => PatchApplyOperation.apply,
      ),
    );
  }
}

enum PatchApplyOperation { apply, checkpointRestore }

class PatchApplyRecovery {
  final String patchSetId;
  final String checkpointId;
  final int restoredFileCount;
  final PatchApplyOperation operation;

  const PatchApplyRecovery({
    required this.patchSetId,
    required this.checkpointId,
    required this.restoredFileCount,
    required this.operation,
  });
}

enum CheckpointRestoreFileState { ready, alreadyRestored, laterUserChange }

class CheckpointRestoreFilePreview {
  final String path;
  final CheckpointRestoreFileState state;

  const CheckpointRestoreFilePreview({required this.path, required this.state});

  bool get requiresOverwrite =>
      state == CheckpointRestoreFileState.laterUserChange;
}

/// A read-only, repeatable description of a checkpoint restore. The actual
/// restore recalculates this preview immediately before writing so a stale
/// confirmation cannot overwrite a file that changed while the dialog was open.
class CheckpointRestorePreview {
  final Checkpoint checkpoint;
  final ProposedPatchSet? patchSet;
  final List<CheckpointRestoreFilePreview> files;

  const CheckpointRestorePreview({
    required this.checkpoint,
    required this.patchSet,
    required this.files,
  });

  bool get hasLaterUserChanges => files.any((file) => file.requiresOverwrite);

  int get fileCount => files.length;

  String get verificationStatus {
    if (patchSet == null || !patchSet!.verificationRequested) {
      return 'No verification requested';
    }
    if ((patchSet!.verificationRequestId ?? '').trim().isEmpty) {
      return 'Verification requested';
    }
    return 'Verification recorded';
  }
}

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
  static const _schemaKind = 'circuit.patch-proposals';
  static const _schemaVersion = 2;
  static const _applyJournalSchemaKind = 'circuit.patch-apply-journal';
  static const _applyJournalSchemaVersion = 2;

  final String baseDir;
  final PatchApplyMutationObserver? onMutationApplied;

  PatchProposalStore({String? baseDir, this.onMutationApplied})
    : baseDir = baseDir ?? p.join(PlatformUtils.configDir, 'patch_proposals');

  String historyPath(String? rootPath) {
    return p.join(baseDir, '${WorkItemStore.projectKey(rootPath)}.json');
  }

  String applyJournalPath(String rootPath) {
    return p.join(
      baseDir,
      '${WorkItemStore.projectKey(rootPath)}.apply-journal.json',
    );
  }

  Future<void> writeApplyJournal(PatchApplyJournal journal) async {
    final file = File(applyJournalPath(journal.workspaceRoot));
    await _writeAtomically(file, _encodeApplyJournal(journal));
  }

  Future<void> clearApplyJournal(String rootPath) async {
    final file = File(applyJournalPath(rootPath));
    if (await file.exists()) await file.delete();
  }

  Future<void> notifyMutationApplied(int completedMutations) async {
    await onMutationApplied?.call(completedMutations);
  }

  /// Restores a transaction that was journaled but never finalized. The
  /// journal stays on disk until every snapshot is safely restored, so an
  /// interruption during recovery is itself restart-safe and idempotent.
  Future<PatchApplyRecovery?> recoverPendingApply(String rootPath) async {
    final file = File(applyJournalPath(rootPath));
    if (!await file.exists()) return null;

    final contents = await file.readAsString();
    final raw = jsonDecode(contents);
    // PatchApplyJournal schema 1 predates the common envelope and already
    // used `schemaVersion` for its own payload. Recognize that precise shape
    // as legacy rather than mistaking it for an envelope without a kind.
    final document =
        raw is Map<String, dynamic> &&
            raw['kind'] == null &&
            raw['transactionId'] is String
        ? VersionedJsonDocument(
            kind: _applyJournalSchemaKind,
            schemaVersion: 1,
            payload: raw,
            isLegacy: true,
          )
        : VersionedJsonDocument.decode(
            raw,
            expectedKind: _applyJournalSchemaKind,
            currentSchemaVersion: _applyJournalSchemaVersion,
          );
    final decoded = document.payload;
    if (decoded is! Map) {
      throw const FormatException('Patch apply journal is not an object.');
    }
    final journal = PatchApplyJournal.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (document.schemaVersion < _applyJournalSchemaVersion) {
      await migrateVersionedJsonFile(
        file: file,
        originalContents: contents,
        migratedContents: _encodeApplyJournal(journal),
        previousSchemaVersion: document.schemaVersion,
      );
    }
    final normalizedRoot = p.normalize(rootPath);
    if (p.normalize(journal.workspaceRoot) != normalizedRoot) {
      throw StateError(
        'Refusing to recover a patch journal for a different workspace.',
      );
    }
    await _preflightJournalRecovery(normalizedRoot, journal.snapshots);

    for (final snapshot in journal.snapshots.reversed) {
      final fullPath = _resolveJournalPath(normalizedRoot, snapshot.path);
      if (fullPath == null) {
        throw StateError('Patch journal contains an unsafe workspace path.');
      }
      final file = File(fullPath);
      if (snapshot.wasCreated) {
        if (await file.exists()) await file.delete();
      } else if (snapshot.originalContent != null) {
        await writePatchFileAtomically(file, snapshot.originalContent!);
      }
    }
    for (final snapshot in journal.snapshots.reversed) {
      if (!snapshot.wasCreated) continue;
      await _removeJournalCreatedParentDirs(
        normalizedRoot,
        snapshot.createdParentDirs,
      );
    }
    await clearApplyJournal(normalizedRoot);
    return PatchApplyRecovery(
      patchSetId: journal.patchSetId,
      checkpointId: journal.checkpointId,
      restoredFileCount: journal.snapshots.length,
      operation: journal.operation,
    );
  }

  Future<PatchProposalState> load(String? rootPath) async {
    final file = File(historyPath(rootPath));
    if (!await file.exists()) return const PatchProposalState();
    final contents = await file.readAsString();
    final document = VersionedJsonDocument.decode(
      jsonDecode(contents),
      expectedKind: _schemaKind,
      currentSchemaVersion: _schemaVersion,
    );
    final json = document.payload;
    if (json is! Map) {
      throw const FormatException('Patch proposal payload is not an object.');
    }
    final payload = Map<String, dynamic>.from(json);
    final state = _decodePayload(payload);
    if (document.schemaVersion < _schemaVersion) {
      await migrateVersionedJsonFile(
        file: file,
        originalContents: contents,
        migratedContents: _encode(state),
        previousSchemaVersion: document.schemaVersion,
      );
    }
    return state;
  }

  PatchProposalState _decodePayload(Map<String, dynamic> json) {
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
    await _writeAtomically(file, _encode(state));
  }

  void saveSync(String? rootPath, PatchProposalState state) {
    final file = File(historyPath(rootPath));
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    final staged = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-$pid',
    );
    try {
      staged.writeAsStringSync(_encode(state), flush: true);
      staged.renameSync(file.path);
    } finally {
      if (staged.existsSync()) staged.deleteSync();
    }
  }

  String _encode(PatchProposalState state) {
    final payload = {
      'active': state.active?.toJson(),
      'history': state.history.map((patchSet) => patchSet.toJson()).toList(),
      'checkpoints': state.checkpoints.map(
        (id, checkpoint) => MapEntry(id, checkpoint.toJson()),
      ),
      'message': state.message,
    };
    return VersionedJsonDocument(
      kind: _schemaKind,
      schemaVersion: _schemaVersion,
      payload: payload,
    ).encode(pretty: true);
  }

  String _encodeApplyJournal(PatchApplyJournal journal) {
    return VersionedJsonDocument(
      kind: _applyJournalSchemaKind,
      schemaVersion: _applyJournalSchemaVersion,
      payload: journal.toJson(),
    ).encode(pretty: true);
  }

  Future<void> _writeAtomically(File file, String contents) async {
    await writeVersionedJsonAtomically(file, contents);
  }
}

String? _resolveJournalPath(String rootPath, String targetPath) {
  final sanitized = targetPath.trim().replaceAll('\\', '/');
  if (sanitized.isEmpty ||
      sanitized.codeUnits.any((unit) => unit < 32 || unit == 127) ||
      RegExp(r'^[A-Za-z]:/').hasMatch(sanitized) ||
      sanitized.startsWith('//')) {
    return null;
  }
  final normalized = p.normalize(
    p.isAbsolute(sanitized) ? sanitized : p.join(rootPath, sanitized),
  );
  if (normalized == rootPath || !p.isWithin(rootPath, normalized)) return null;
  return normalized;
}

bool _journalPathIsSensitive(String path) {
  final normalized = path.trim().replaceAll('\\', '/').toLowerCase();
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

bool _journalPathTraversesSymlink(String rootPath, String fullPath) {
  if (FileSystemEntity.typeSync(rootPath, followLinks: false) ==
      FileSystemEntityType.link) {
    return true;
  }
  final relative = p.relative(fullPath, from: rootPath);
  var current = rootPath;
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

Future<void> _preflightJournalRecovery(
  String rootPath,
  List<FileSnapshot> snapshots,
) async {
  final seen = <String>{};
  for (final snapshot in snapshots) {
    final fullPath = _resolveJournalPath(rootPath, snapshot.path);
    if (fullPath == null || _journalPathIsSensitive(snapshot.path)) {
      throw StateError('Patch journal contains an unsafe workspace path.');
    }
    if (!seen.add(fullPath)) {
      throw StateError('Patch journal contains duplicate workspace paths.');
    }
    if (_journalPathTraversesSymlink(rootPath, fullPath)) {
      throw StateError('Patch journal path traverses a symbolic link.');
    }
    final type = await FileSystemEntity.type(fullPath, followLinks: false);
    if (type == FileSystemEntityType.directory ||
        type == FileSystemEntityType.link) {
      throw StateError('Patch journal target is not a regular file.');
    }
    if (snapshot.wasCreated) continue;
    if (snapshot.originalContent == null) {
      throw StateError('Patch journal is missing original file content.');
    }
    var parent = p.dirname(fullPath);
    while (parent != rootPath && p.isWithin(rootPath, parent)) {
      final parentType = await FileSystemEntity.type(
        parent,
        followLinks: false,
      );
      if (parentType == FileSystemEntityType.notFound) {
        parent = p.dirname(parent);
        continue;
      }
      if (parentType != FileSystemEntityType.directory) {
        throw StateError('Patch journal has a non-directory parent path.');
      }
      parent = p.dirname(parent);
    }
  }
}

Future<void> writePatchFileAtomically(File file, String contents) async {
  if (!await file.parent.exists()) await file.parent.create(recursive: true);
  final staged = File(
    '${file.path}.circuit-tmp-${DateTime.now().microsecondsSinceEpoch}-$pid',
  );
  try {
    await staged.writeAsString(contents, flush: true);
    await staged.rename(file.path);
  } finally {
    if (await staged.exists()) await staged.delete();
  }
}

Future<void> _removeJournalCreatedParentDirs(
  String rootPath,
  List<String> createdParentDirs,
) async {
  for (final relativeDir in createdParentDirs) {
    final fullPath = _resolveJournalPath(rootPath, relativeDir);
    if (fullPath == null || _journalPathTraversesSymlink(rootPath, fullPath)) {
      continue;
    }
    final directory = Directory(fullPath);
    if (!await directory.exists()) continue;
    try {
      if (await directory.list().isEmpty) await directory.delete();
    } catch (_) {
      // Empty-directory cleanup is best effort; never remove user content.
    }
  }
}

final patchProposalStoreProvider = Provider<PatchProposalStore>(
  (ref) => PatchProposalStore(),
);
