import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_first_sync_contract.dart';

/// The small secure-storage boundary required by local-first project keys.
///
/// Keys are deliberately never written to project files, operation envelopes,
/// logs, exports, or ordinary app preferences. The interface keeps the
/// platform Keychain implementation testable without a native test host.
abstract interface class LocalFirstSyncSecureStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterLocalFirstSyncSecureStore implements LocalFirstSyncSecureStore {
  final FlutterSecureStorage _storage;

  const FlutterLocalFirstSyncSecureStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);
}

/// A versioned AES-256 project key loaded only from operating-system secure
/// storage. [keyBytes] must never be persisted outside [LocalFirstSyncKeyRing]
/// or exposed to a collaboration payload.
class LocalFirstSyncProjectKey {
  final String projectId;
  final int version;
  final Uint8List keyBytes;

  LocalFirstSyncProjectKey({
    required this.projectId,
    required this.version,
    required List<int> keyBytes,
  }) : keyBytes = Uint8List.fromList(keyBytes);
}

/// Stores one independently generated AES-256 key per project/key version.
///
/// A rotation creates the next version before switching the secure current-key
/// pointer, preserving previously encrypted envelopes for explicit recovery.
/// It is not a key-wrapping or member-sharing mechanism: those require the
/// separate, approved remote collaboration design from ADR-0008.
class LocalFirstSyncKeyRing {
  static const _keyPrefix = 'circuit.local-first-sync.key.v1';
  static const _maxKeyVersion = 2147483647;

  final LocalFirstSyncSecureStore _secureStore;
  final Cipher _cipher;

  LocalFirstSyncKeyRing({
    LocalFirstSyncSecureStore? secureStore,
    Cipher? cipher,
  }) : _secureStore = secureStore ?? const FlutterLocalFirstSyncSecureStore(),
       _cipher = cipher ?? AesGcm.with256bits();

  Future<LocalFirstSyncProjectKey> loadOrCreateCurrent(String projectId) async {
    _requireProjectId(projectId);
    final current = await _readCurrentVersion(projectId);
    if (current != null) return read(projectId, current);
    return _createAndSetCurrent(projectId, 1);
  }

  Future<LocalFirstSyncProjectKey> read(String projectId, int version) async {
    _requireProjectId(projectId);
    _requireKeyVersion(version);
    final encoded = await _readSecure(_materialStorageKey(projectId, version));
    if (encoded == null) {
      throw const LocalFirstSyncEncryptionException(
        'The required project sync key is unavailable. Restore it from the secure store before opening this envelope.',
      );
    }
    final bytes = _decodeBase64(encoded, label: 'project key');
    if (bytes.lengthInBytes != 32) {
      throw const LocalFirstSyncEncryptionException(
        'The project sync key is malformed. Refuse to open sync envelopes.',
      );
    }
    return LocalFirstSyncProjectKey(
      projectId: projectId,
      version: version,
      keyBytes: bytes,
    );
  }

  /// Generates the next project key version. Existing key material remains so
  /// prior envelopes can be decrypted during the approved recovery window.
  Future<LocalFirstSyncProjectKey> rotate(String projectId) async {
    final current = await loadOrCreateCurrent(projectId);
    if (current.version >= _maxKeyVersion) {
      throw const LocalFirstSyncEncryptionException(
        'The project sync key cannot be rotated further.',
      );
    }
    return _createAndSetCurrent(projectId, current.version + 1);
  }

  /// Removes a superseded project-key version from secure storage.
  ///
  /// The current key is deliberately never removable through this method: a
  /// caller must first rotate to a newer key, retain any required recovery
  /// evidence, and then explicitly retire the older material. This is a local
  /// recovery cutoff, not remote member revocation or key-distribution proof.
  Future<void> retire(String projectId, int version) async {
    _requireProjectId(projectId);
    _requireKeyVersion(version);
    final current = await _readCurrentVersion(projectId);
    if (current == null || version >= current) {
      throw const LocalFirstSyncEncryptionException(
        'Only a superseded project sync key may be retired.',
      );
    }
    try {
      await _secureStore.delete(key: _materialStorageKey(projectId, version));
    } catch (_) {
      throw const LocalFirstSyncEncryptionException(
        'The secure store could not retire the superseded project sync key.',
      );
    }
  }

  Future<LocalFirstSyncProjectKey> _createAndSetCurrent(
    String projectId,
    int version,
  ) async {
    _requireKeyVersion(version);
    final secretKey = await _cipher.newSecretKey();
    final keyBytes = await secretKey.extractBytes();
    if (keyBytes.length != 32) {
      throw const LocalFirstSyncEncryptionException(
        'The configured sync cipher did not generate an AES-256 key.',
      );
    }
    final materialKey = _materialStorageKey(projectId, version);
    try {
      await _writeSecure(materialKey, base64Encode(keyBytes));
      await _writeSecure(_currentStorageKey(projectId), '$version');
    } catch (_) {
      try {
        await _secureStore.delete(key: materialKey);
      } catch (_) {
        // A failed cleanup must not reveal secure-store diagnostics.
      }
      rethrow;
    }
    return LocalFirstSyncProjectKey(
      projectId: projectId,
      version: version,
      keyBytes: keyBytes,
    );
  }

  Future<int?> _readCurrentVersion(String projectId) async {
    final value = await _readSecure(_currentStorageKey(projectId));
    if (value == null) return null;
    final version = int.tryParse(value);
    if (version == null || version < 1 || version > _maxKeyVersion) {
      throw const LocalFirstSyncEncryptionException(
        'The current project sync-key reference is malformed.',
      );
    }
    return version;
  }

  Future<String?> _readSecure(String key) async {
    try {
      return await _secureStore.read(key: key);
    } catch (_) {
      throw const LocalFirstSyncEncryptionException(
        'The secure store could not read the project sync key.',
      );
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    try {
      await _secureStore.write(key: key, value: value);
    } catch (_) {
      throw const LocalFirstSyncEncryptionException(
        'The secure store could not protect the project sync key.',
      );
    }
  }

  static String _currentStorageKey(String projectId) =>
      '$_keyPrefix.current.$projectId';

  static String _materialStorageKey(String projectId, int version) =>
      '$_keyPrefix.material.$projectId.$version';
}

/// Serializable encrypted representation of one validated sync operation.
///
/// Only opaque routing metadata appears outside the authenticated ciphertext.
/// The associated data binds that metadata to the encrypted bytes, so a
/// project, operation, schema, or key-version substitution cannot be opened.
class LocalFirstSyncEncryptedEnvelope {
  static const format = 'circuit.local-first-sync.aes-gcm.v1';
  static const envelopeSchemaVersion = 1;

  final String projectId;
  final String operationId;
  final int payloadSchemaVersion;
  final int keyVersion;
  final String nonceBase64;
  final String ciphertextBase64;
  final String macBase64;

  const LocalFirstSyncEncryptedEnvelope({
    required this.projectId,
    required this.operationId,
    required this.payloadSchemaVersion,
    required this.keyVersion,
    required this.nonceBase64,
    required this.ciphertextBase64,
    required this.macBase64,
  });

  Map<String, Object> toJson() => {
    'format': format,
    'envelopeSchemaVersion': envelopeSchemaVersion,
    'projectId': projectId,
    'operationId': operationId,
    'payloadSchemaVersion': payloadSchemaVersion,
    'keyVersion': keyVersion,
    'nonceBase64': nonceBase64,
    'ciphertextBase64': ciphertextBase64,
    'macBase64': macBase64,
  };

  static LocalFirstSyncEncryptedEnvelope fromJson(Object? value) {
    if (value is! Map) {
      throw const LocalFirstSyncEncryptionException(
        'An encrypted sync envelope must be a JSON object.',
      );
    }
    final json = Map<String, Object?>.fromEntries(
      value.entries
          .where((entry) => entry.key is String)
          .map((entry) => MapEntry(entry.key as String, entry.value)),
    );
    const expectedKeys = {
      'format',
      'envelopeSchemaVersion',
      'projectId',
      'operationId',
      'payloadSchemaVersion',
      'keyVersion',
      'nonceBase64',
      'ciphertextBase64',
      'macBase64',
    };
    if (json.length != value.length ||
        json.keys.toSet().length != expectedKeys.length ||
        !json.keys.toSet().containsAll(expectedKeys) ||
        json['format'] != format ||
        json['envelopeSchemaVersion'] != envelopeSchemaVersion) {
      throw const LocalFirstSyncEncryptionException(
        'The encrypted sync envelope format is unsupported.',
      );
    }
    final envelope = LocalFirstSyncEncryptedEnvelope(
      projectId: _requiredString(json, 'projectId'),
      operationId: _requiredString(json, 'operationId'),
      payloadSchemaVersion: _requiredInt(json, 'payloadSchemaVersion'),
      keyVersion: _requiredInt(json, 'keyVersion'),
      nonceBase64: _requiredString(json, 'nonceBase64'),
      ciphertextBase64: _requiredString(json, 'ciphertextBase64'),
      macBase64: _requiredString(json, 'macBase64'),
    );
    envelope._validateMetadata();
    return envelope;
  }

  void _validateMetadata() {
    _requireProjectId(projectId);
    if (!LocalFirstSyncContract.isOpaqueIdentifier(operationId) ||
        payloadSchemaVersion != localFirstSyncSchemaVersion ||
        keyVersion < 1 ||
        keyVersion > LocalFirstSyncKeyRing._maxKeyVersion) {
      throw const LocalFirstSyncEncryptionException(
        'The encrypted sync envelope metadata is invalid.',
      );
    }
    final nonce = _decodeBase64(nonceBase64, label: 'nonce');
    final ciphertext = _decodeBase64(ciphertextBase64, label: 'ciphertext');
    final mac = _decodeBase64(macBase64, label: 'authentication tag');
    if (nonce.length != 12 || ciphertext.isEmpty || mac.length != 16) {
      throw const LocalFirstSyncEncryptionException(
        'The encrypted sync envelope has invalid AES-GCM fields.',
      );
    }
  }
}

/// Encrypts and authenticates approved local-first operations.
///
/// This class has no filesystem, account, socket, upload, download, or feature
/// flag dependency. It is the local foundation for a future, separately
/// approved user-initiated export/import or remote transport implementation.
class LocalFirstSyncEnvelopeCipher {
  final LocalFirstSyncKeyRing _keyRing;
  final Cipher _cipher;

  LocalFirstSyncEnvelopeCipher({LocalFirstSyncKeyRing? keyRing, Cipher? cipher})
    : _keyRing = keyRing ?? LocalFirstSyncKeyRing(cipher: cipher),
      _cipher = cipher ?? AesGcm.with256bits();

  Future<LocalFirstSyncEncryptedEnvelope> seal(
    LocalFirstSyncOperation operation,
  ) async {
    LocalFirstSyncContract.validate(operation);
    final key = await _keyRing.loadOrCreateCurrent(operation.projectId);
    final cleartext = utf8.encode(_canonicalJson(_operationToJson(operation)));
    final envelope = _emptyEnvelopeFor(operation, key.version);
    final box = await _cipher.encrypt(
      cleartext,
      secretKey: SecretKey(key.keyBytes),
      nonce: _cipher.newNonce(),
      aad: utf8.encode(_associatedData(envelope)),
    );
    return LocalFirstSyncEncryptedEnvelope(
      projectId: envelope.projectId,
      operationId: envelope.operationId,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      keyVersion: envelope.keyVersion,
      nonceBase64: base64Encode(box.nonce),
      ciphertextBase64: base64Encode(box.cipherText),
      macBase64: base64Encode(box.mac.bytes),
    );
  }

  Future<LocalFirstSyncOperation> open(
    LocalFirstSyncEncryptedEnvelope envelope,
  ) async {
    envelope._validateMetadata();
    final key = await _keyRing.read(envelope.projectId, envelope.keyVersion);
    final cleartext = await _decrypt(envelope, key);
    final operation = _operationFromJson(_decodeJsonObject(cleartext));
    LocalFirstSyncContract.validate(operation);
    if (operation.projectId != envelope.projectId ||
        operation.operationId != envelope.operationId ||
        operation.payloadSchemaVersion != envelope.payloadSchemaVersion) {
      throw const LocalFirstSyncEncryptionException(
        'The encrypted sync envelope metadata does not match its authenticated operation.',
      );
    }
    return operation;
  }

  Future<LocalFirstSyncProjectKey> rotateProjectKey(String projectId) =>
      _keyRing.rotate(projectId);

  /// Stops this installation from opening envelopes sealed with a retired
  /// historical version. The current project key is never retired here.
  Future<void> retireProjectKeyVersion(String projectId, int version) =>
      _keyRing.retire(projectId, version);

  Future<List<int>> _decrypt(
    LocalFirstSyncEncryptedEnvelope envelope,
    LocalFirstSyncProjectKey key,
  ) async {
    try {
      return await _cipher.decrypt(
        SecretBox(
          _decodeBase64(envelope.ciphertextBase64, label: 'ciphertext'),
          nonce: _decodeBase64(envelope.nonceBase64, label: 'nonce'),
          mac: Mac(
            _decodeBase64(envelope.macBase64, label: 'authentication tag'),
          ),
        ),
        secretKey: SecretKey(key.keyBytes),
        aad: utf8.encode(_associatedData(envelope)),
      );
    } catch (_) {
      throw const LocalFirstSyncEncryptionException(
        'The encrypted sync envelope could not be authenticated or opened.',
      );
    }
  }

  static LocalFirstSyncEncryptedEnvelope _emptyEnvelopeFor(
    LocalFirstSyncOperation operation,
    int keyVersion,
  ) => LocalFirstSyncEncryptedEnvelope(
    projectId: operation.projectId,
    operationId: operation.operationId,
    payloadSchemaVersion: operation.payloadSchemaVersion,
    keyVersion: keyVersion,
    nonceBase64: '',
    ciphertextBase64: '',
    macBase64: '',
  );

  static String _associatedData(LocalFirstSyncEncryptedEnvelope envelope) =>
      '${LocalFirstSyncEncryptedEnvelope.format}\n'
      '${LocalFirstSyncEncryptedEnvelope.envelopeSchemaVersion}\n'
      '${envelope.projectId}\n'
      '${envelope.operationId}\n'
      '${envelope.payloadSchemaVersion}\n'
      '${envelope.keyVersion}';
}

Map<String, Object?> _operationToJson(LocalFirstSyncOperation operation) => {
  'operationId': operation.operationId,
  'projectId': operation.projectId,
  'actorId': operation.actorId,
  'predecessorIds': operation.predecessorIds,
  'entityId': operation.entityId,
  'kind': operation.kind.name,
  'payloadSchemaVersion': operation.payloadSchemaVersion,
  'timestamp': {
    'wallTimeMillis': operation.timestamp.wallTimeMillis,
    'logicalCounter': operation.timestamp.logicalCounter,
    'actorId': operation.timestamp.actorId,
  },
  'payload': operation.payload,
};

LocalFirstSyncOperation _operationFromJson(Map<String, Object?> json) {
  const expectedKeys = {
    'operationId',
    'projectId',
    'actorId',
    'predecessorIds',
    'entityId',
    'kind',
    'payloadSchemaVersion',
    'timestamp',
    'payload',
  };
  if (json.keys.toSet().length != expectedKeys.length ||
      !json.keys.toSet().containsAll(expectedKeys)) {
    throw const LocalFirstSyncEncryptionException(
      'The encrypted sync operation has an unsupported schema.',
    );
  }
  final timestamp = _requiredObject(json, 'timestamp');
  final payload = _requiredObject(json, 'payload');
  final predecessors = json['predecessorIds'];
  if (predecessors is! List ||
      predecessors.any((value) => value is! String) ||
      timestamp is! Map ||
      payload is! Map) {
    throw const LocalFirstSyncEncryptionException(
      'The encrypted sync operation has malformed fields.',
    );
  }
  final kindName = _requiredString(json, 'kind');
  final kind = LocalFirstSyncEntityKind.values
      .where((candidate) => candidate.name == kindName)
      .firstOrNull;
  if (kind == null) {
    throw const LocalFirstSyncEncryptionException(
      'The encrypted sync operation has an unsupported entity kind.',
    );
  }
  final timestampJson = Map<String, Object?>.fromEntries(
    timestamp.entries
        .where((entry) => entry.key is String)
        .map((entry) => MapEntry(entry.key as String, entry.value)),
  );
  final payloadJson = Map<String, Object?>.fromEntries(
    payload.entries
        .where((entry) => entry.key is String)
        .map((entry) => MapEntry(entry.key as String, entry.value)),
  );
  if (timestampJson.length != timestamp.length ||
      payloadJson.length != payload.length) {
    throw const LocalFirstSyncEncryptionException(
      'The encrypted sync operation has malformed JSON keys.',
    );
  }
  return LocalFirstSyncOperation(
    operationId: _requiredString(json, 'operationId'),
    projectId: _requiredString(json, 'projectId'),
    actorId: _requiredString(json, 'actorId'),
    predecessorIds: predecessors.cast<String>(),
    entityId: _requiredString(json, 'entityId'),
    kind: kind,
    payloadSchemaVersion: _requiredInt(json, 'payloadSchemaVersion'),
    timestamp: LocalFirstSyncTimestamp(
      wallTimeMillis: _requiredInt(timestampJson, 'wallTimeMillis'),
      logicalCounter: _requiredInt(timestampJson, 'logicalCounter'),
      actorId: _requiredString(timestampJson, 'actorId'),
    ),
    payload: payloadJson,
  );
}

Map<String, Object?> _decodeJsonObject(List<int> bytes) {
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map) throw const FormatException();
    final json = Map<String, Object?>.fromEntries(
      value.entries
          .where((entry) => entry.key is String)
          .map((entry) => MapEntry(entry.key as String, entry.value)),
    );
    if (json.length != value.length) throw const FormatException();
    return json;
  } catch (_) {
    throw const LocalFirstSyncEncryptionException(
      'The authenticated sync operation is not valid JSON.',
    );
  }
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const LocalFirstSyncEncryptionException(
          'Sync JSON maps must use string keys.',
        );
      }
      sorted[entry.key as String] = _canonicalize(entry.value);
    }
    return sorted;
  }
  if (value is List) return value.map(_canonicalize).toList(growable: false);
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw LocalFirstSyncEncryptionException(
      'The encrypted sync envelope is missing $key.',
    );
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw LocalFirstSyncEncryptionException(
      'The encrypted sync envelope has an invalid $key.',
    );
  }
  return value;
}

Object _requiredObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    throw LocalFirstSyncEncryptionException(
      'The encrypted sync envelope is missing $key.',
    );
  }
  return value;
}

Uint8List _decodeBase64(String value, {required String label}) {
  if (value.isEmpty ||
      value.length % 4 != 0 ||
      !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(value)) {
    throw LocalFirstSyncEncryptionException(
      'The encrypted sync $label is malformed.',
    );
  }
  try {
    return Uint8List.fromList(base64Decode(value));
  } catch (_) {
    throw LocalFirstSyncEncryptionException(
      'The encrypted sync $label is malformed.',
    );
  }
}

void _requireProjectId(String projectId) {
  if (!LocalFirstSyncContract.isOpaqueIdentifier(projectId)) {
    throw const LocalFirstSyncEncryptionException(
      'Project sync keys require an opaque project identifier.',
    );
  }
}

void _requireKeyVersion(int version) {
  if (version < 1 || version > LocalFirstSyncKeyRing._maxKeyVersion) {
    throw const LocalFirstSyncEncryptionException(
      'Project sync key versions must be positive and bounded.',
    );
  }
}

class LocalFirstSyncEncryptionException implements Exception {
  final String message;

  const LocalFirstSyncEncryptionException(this.message);

  @override
  String toString() => message;
}
