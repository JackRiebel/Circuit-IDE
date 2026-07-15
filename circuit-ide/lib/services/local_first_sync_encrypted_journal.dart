import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'local_first_sync_contract.dart';
import 'local_first_sync_encryption.dart';

/// A local, encrypted-only staging journal for a single syncable project.
///
/// This class has no account, endpoint, socket, uploader, downloader, or
/// feature flag. It makes the pre-transport boundary concrete: a future
/// user-initiated export/import or reviewed transport can receive only
/// authenticated encrypted envelopes, never a plaintext project operation.
class LocalFirstSyncEncryptedJournal {
  static const format = 'circuit.local-first-sync.encrypted-journal.v1';
  static const schemaVersion = 1;
  static const defaultMaxEntries = LocalFirstSyncContract.maxOperationsPerMerge;
  static const defaultMaxBytes = 16 * 1024 * 1024;

  final String projectId;
  final File file;
  final LocalFirstSyncEnvelopeCipher _cipher;
  final int maxEntries;
  final int maxBytes;

  Future<void> _pendingWrite = Future.value();
  int _stagingSequence = 0;

  LocalFirstSyncEncryptedJournal({
    required this.projectId,
    required this.file,
    LocalFirstSyncEnvelopeCipher? cipher,
    this.maxEntries = defaultMaxEntries,
    this.maxBytes = defaultMaxBytes,
  }) : _cipher = cipher ?? LocalFirstSyncEnvelopeCipher() {
    if (!LocalFirstSyncContract.isOpaqueIdentifier(projectId)) {
      throw const LocalFirstSyncJournalException(
        'The encrypted sync journal requires an opaque project identifier.',
      );
    }
    if (maxEntries < 1 ||
        maxEntries > LocalFirstSyncContract.maxOperationsPerMerge ||
        maxBytes < 1024) {
      throw const LocalFirstSyncJournalException(
        'The encrypted sync journal bounds are invalid.',
      );
    }
  }

  /// Seals [operation] before it is persisted. A journal never writes clear
  /// operation data, and it refuses duplicate operation IDs instead of
  /// overwriting or silently replacing a prior encrypted record.
  Future<LocalFirstSyncEncryptedEnvelope> append(
    LocalFirstSyncOperation operation,
  ) async {
    if (operation.projectId != projectId) {
      throw const LocalFirstSyncJournalException(
        'A sync operation may be appended only to its own project journal.',
      );
    }
    // Reject local-only classes before a new secure key is created.
    LocalFirstSyncContract.validate(operation);
    return _serialize(() async {
      final existing = await readEnvelopes();
      if (existing.length >= maxEntries) {
        throw const LocalFirstSyncJournalException(
          'The encrypted sync journal reached its approved entry bound.',
        );
      }
      if (existing.any(
        (envelope) => envelope.operationId == operation.operationId,
      )) {
        throw const LocalFirstSyncJournalException(
          'An encrypted sync journal cannot store the same operation twice.',
        );
      }
      final sealed = await _cipher.seal(operation);
      await _replaceAtomically([...existing, sealed]);
      return sealed;
    });
  }

  /// Returns only opaque routing metadata and authenticated ciphertext for a
  /// future reviewed transport. It does not decrypt anything.
  Future<List<LocalFirstSyncEncryptedEnvelope>> readEnvelopes() async {
    final bytes = await _safeJournalBytes();
    if (bytes == null) return const [];
    final json = _decodeJournal(bytes);
    final envelopes = json['envelopes'];
    if (envelopes is! List || envelopes.length > maxEntries) {
      throw const LocalFirstSyncJournalException(
        'The encrypted sync journal has invalid entry bounds.',
      );
    }
    final seenOperationIds = <String>{};
    final result = <LocalFirstSyncEncryptedEnvelope>[];
    for (final value in envelopes) {
      final envelope = LocalFirstSyncEncryptedEnvelope.fromJson(value);
      if (envelope.projectId != projectId ||
          !seenOperationIds.add(envelope.operationId)) {
        throw const LocalFirstSyncJournalException(
          'The encrypted sync journal contains an invalid operation record.',
        );
      }
      result.add(envelope);
    }
    return List<LocalFirstSyncEncryptedEnvelope>.unmodifiable(result);
  }

  /// Opens the local encrypted journal only for the deterministic conflict
  /// simulator. This is not a remote merge, account, or authorization flow.
  Future<LocalFirstSyncMergeResult> openAndMerge({
    required LocalFirstSyncProjectAuthority authority,
  }) async {
    if (authority.projectId != projectId) {
      throw const LocalFirstSyncJournalException(
        'The encrypted sync journal may merge only with its local project authority.',
      );
    }
    final envelopes = await readEnvelopes();
    final operations = <LocalFirstSyncOperation>[];
    for (final envelope in envelopes) {
      operations.add(await _cipher.open(envelope));
    }
    return LocalFirstSyncContract.merge(operations, authority: authority);
  }

  Future<void> _replaceAtomically(
    List<LocalFirstSyncEncryptedEnvelope> envelopes,
  ) async {
    await _ensureSafeParent();
    final bytes = utf8.encode(
      jsonEncode({
        'format': format,
        'schemaVersion': schemaVersion,
        'projectId': projectId,
        'envelopes': envelopes.map((envelope) => envelope.toJson()).toList(),
      }),
    );
    if (bytes.length > maxBytes) {
      throw const LocalFirstSyncJournalException(
        'The encrypted sync journal would exceed its approved byte bound.',
      );
    }
    final staged = _stagedFile();
    try {
      await staged.create(exclusive: true);
      final handle = await staged.open(mode: FileMode.write);
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
      // Renaming a sibling replaces a complete file entry rather than writing
      // through a pre-existing target link.
      await staged.rename(file.path);
    } catch (error) {
      if (error is LocalFirstSyncJournalException) rethrow;
      throw const LocalFirstSyncJournalException(
        'The encrypted sync journal could not be stored safely.',
      );
    } finally {
      if (await FileSystemEntity.type(staged.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        await staged.delete();
      }
    }
  }

  Future<void> _ensureSafeParent() async {
    final parent = file.parent;
    var type = await FileSystemEntity.type(parent.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await parent.create(recursive: true);
      type = await FileSystemEntity.type(parent.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory) {
      throw const LocalFirstSyncJournalException(
        'The encrypted sync journal parent is not a regular directory.',
      );
    }
  }

  Future<List<int>?> _safeJournalBytes() async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file || await file.length() > maxBytes) {
      throw const LocalFirstSyncJournalException(
        'The encrypted sync journal is not a safe bounded regular file.',
      );
    }
    try {
      final bytes = await file.readAsBytes();
      final typeAfterRead = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      if (typeAfterRead != FileSystemEntityType.file ||
          bytes.isEmpty ||
          bytes.length > maxBytes) {
        throw const LocalFirstSyncJournalException(
          'The encrypted sync journal changed while it was being read.',
        );
      }
      return bytes;
    } on LocalFirstSyncJournalException {
      rethrow;
    } catch (_) {
      throw const LocalFirstSyncJournalException(
        'The encrypted sync journal could not be read safely.',
      );
    }
  }

  Map<String, Object?> _decodeJournal(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException();
      final json = Map<String, Object?>.fromEntries(
        decoded.entries
            .where((entry) => entry.key is String)
            .map((entry) => MapEntry(entry.key as String, entry.value)),
      );
      const expectedKeys = {
        'format',
        'schemaVersion',
        'projectId',
        'envelopes',
      };
      if (json.length != decoded.length ||
          json.keys.toSet().length != expectedKeys.length ||
          !json.keys.toSet().containsAll(expectedKeys) ||
          json['format'] != format ||
          json['schemaVersion'] != schemaVersion ||
          json['projectId'] != projectId) {
        throw const FormatException();
      }
      return json;
    } catch (_) {
      throw const LocalFirstSyncJournalException(
        'The encrypted sync journal format is unsupported.',
      );
    }
  }

  File _stagedFile() => File(
    '${file.path}.staging-${DateTime.now().microsecondsSinceEpoch}-$pid-'
    '${Random.secure().nextInt(1 << 32)}-${_stagingSequence++}',
  );

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pendingWrite.then((_) => action());
    _pendingWrite = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

class LocalFirstSyncJournalException implements Exception {
  final String message;

  const LocalFirstSyncJournalException(this.message);

  @override
  String toString() => message;
}
