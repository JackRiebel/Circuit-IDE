import 'dart:convert';

import 'package:circuit_ide/services/local_first_sync_contract.dart';
import 'package:circuit_ide/services/local_first_sync_encryption.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const projectId = 'project-encrypted-6d995c3f';

  LocalFirstSyncOperation operation({
    required String id,
    required int tick,
    Map<String, Object?> payload = const {
      'kind': 'message',
      'content': 'Customer handoff discussion',
    },
  }) => LocalFirstSyncOperation(
    operationId: id,
    projectId: projectId,
    actorId: 'device-owner',
    entityId: 'thread-immutable-17',
    kind: LocalFirstSyncEntityKind.event,
    payloadSchemaVersion: localFirstSyncSchemaVersion,
    timestamp: LocalFirstSyncTimestamp(
      wallTimeMillis: 1736776800000 + tick,
      logicalCounter: tick,
      actorId: 'device-owner',
    ),
    payload: payload,
  );

  LocalFirstSyncEnvelopeCipher cipherFor(_MemorySecureStore store) {
    return LocalFirstSyncEnvelopeCipher(
      keyRing: LocalFirstSyncKeyRing(secureStore: store),
    );
  }

  test(
    'seals a validated operation with opaque metadata and opens it from the secure project key',
    () async {
      final store = _MemorySecureStore();
      final cipher = cipherFor(store);
      final original = operation(id: 'op-encrypted-first', tick: 1);

      final envelope = await cipher.seal(original);
      final serialized = jsonEncode(envelope.toJson());
      final opened = await cipher.open(
        LocalFirstSyncEncryptedEnvelope.fromJson(jsonDecode(serialized)),
      );

      expect(envelope.projectId, projectId);
      expect(envelope.operationId, original.operationId);
      expect(envelope.keyVersion, 1);
      expect(envelope.payloadSchemaVersion, localFirstSyncSchemaVersion);
      expect(serialized, isNot(contains('Customer handoff discussion')));
      expect(serialized, isNot(contains('device-owner')));
      expect(opened.operationId, original.operationId);
      expect(opened.actorId, original.actorId);
      expect(
        opened.timestamp.wallTimeMillis,
        original.timestamp.wallTimeMillis,
      );
      expect(opened.payload, original.payload);
      expect(
        store.values.keys,
        contains('circuit.local-first-sync.key.v1.current.$projectId'),
      );
      expect(
        store.values.keys,
        contains('circuit.local-first-sync.key.v1.material.$projectId.1'),
      );
    },
  );

  test('same plaintext receives a fresh authenticated AES-GCM nonce', () async {
    final store = _MemorySecureStore();
    final cipher = cipherFor(store);
    final original = operation(id: 'op-encrypted-nonce', tick: 2);

    final first = await cipher.seal(original);
    final second = await cipher.seal(original);

    expect(first.keyVersion, second.keyVersion);
    expect(first.nonceBase64, isNot(second.nonceBase64));
    expect(await cipher.open(first), isA<LocalFirstSyncOperation>());
    expect(await cipher.open(second), isA<LocalFirstSyncOperation>());
  });

  test(
    'metadata and ciphertext substitutions fail closed before merge',
    () async {
      final store = _MemorySecureStore();
      final cipher = cipherFor(store);
      final envelope = await cipher.seal(
        operation(id: 'op-encrypted-tamper', tick: 3),
      );
      final substitutedMetadata = LocalFirstSyncEncryptedEnvelope(
        projectId: envelope.projectId,
        operationId: 'op-encrypted-other',
        payloadSchemaVersion: envelope.payloadSchemaVersion,
        keyVersion: envelope.keyVersion,
        nonceBase64: envelope.nonceBase64,
        ciphertextBase64: envelope.ciphertextBase64,
        macBase64: envelope.macBase64,
      );
      final ciphertext = base64Decode(envelope.ciphertextBase64);
      ciphertext[0] ^= 0x01;
      final substitutedCiphertext = LocalFirstSyncEncryptedEnvelope(
        projectId: envelope.projectId,
        operationId: envelope.operationId,
        payloadSchemaVersion: envelope.payloadSchemaVersion,
        keyVersion: envelope.keyVersion,
        nonceBase64: envelope.nonceBase64,
        ciphertextBase64: base64Encode(ciphertext),
        macBase64: envelope.macBase64,
      );

      await expectLater(
        cipher.open(substitutedMetadata),
        throwsA(isA<LocalFirstSyncEncryptionException>()),
      );
      await expectLater(
        cipher.open(substitutedCiphertext),
        throwsA(isA<LocalFirstSyncEncryptionException>()),
      );
    },
  );

  test(
    'key rotation retains prior envelopes and makes later envelopes use a new key version',
    () async {
      final store = _MemorySecureStore();
      final cipher = cipherFor(store);
      final beforeRotation = await cipher.seal(
        operation(id: 'op-encrypted-before-rotation', tick: 4),
      );

      final rotated = await cipher.rotateProjectKey(projectId);
      final afterRotation = await cipher.seal(
        operation(id: 'op-encrypted-after-rotation', tick: 5),
      );

      expect(rotated.version, 2);
      expect(beforeRotation.keyVersion, 1);
      expect(afterRotation.keyVersion, 2);
      expect(
        (await cipher.open(beforeRotation)).operationId,
        'op-encrypted-before-rotation',
      );
      expect(
        (await cipher.open(afterRotation)).operationId,
        'op-encrypted-after-rotation',
      );
    },
  );

  test(
    'a rotated superseded key can be retired without removing the current key',
    () async {
      final store = _MemorySecureStore();
      final cipher = cipherFor(store);
      final beforeRetirement = await cipher.seal(
        operation(id: 'op-encrypted-retire-before', tick: 8),
      );
      await cipher.rotateProjectKey(projectId);
      final currentEnvelope = await cipher.seal(
        operation(id: 'op-encrypted-retire-current', tick: 9),
      );

      await cipher.retireProjectKeyVersion(
        projectId,
        beforeRetirement.keyVersion,
      );

      await expectLater(
        cipher.open(beforeRetirement),
        throwsA(isA<LocalFirstSyncEncryptionException>()),
      );
      expect(
        (await cipher.open(currentEnvelope)).operationId,
        'op-encrypted-retire-current',
      );
      expect(
        store.values.keys,
        isNot(
          contains(
            'circuit.local-first-sync.key.v1.material.$projectId.${beforeRetirement.keyVersion}',
          ),
        ),
      );
      await expectLater(
        cipher.retireProjectKeyVersion(projectId, currentEnvelope.keyVersion),
        throwsA(isA<LocalFirstSyncEncryptionException>()),
      );
    },
  );

  test(
    'a missing secure project key and malformed envelope are refused',
    () async {
      final sourceStore = _MemorySecureStore();
      final sourceCipher = cipherFor(sourceStore);
      final envelope = await sourceCipher.seal(
        operation(id: 'op-encrypted-missing-key', tick: 6),
      );

      await expectLater(
        cipherFor(_MemorySecureStore()).open(envelope),
        throwsA(isA<LocalFirstSyncEncryptionException>()),
      );
      expect(
        () => LocalFirstSyncEncryptedEnvelope.fromJson({
          ...envelope.toJson(),
          'nonceBase64': 'not-base64',
        }),
        throwsA(isA<LocalFirstSyncEncryptionException>()),
      );
    },
  );

  test(
    'excluded payload data is rejected before any project key is created',
    () async {
      final store = _MemorySecureStore();
      final cipher = cipherFor(store);

      await expectLater(
        cipher.seal(
          operation(
            id: 'op-encrypted-forbidden',
            tick: 7,
            payload: const {'clientSecret': 'seeded-secret'},
          ),
        ),
        throwsA(isA<LocalFirstSyncValidationException>()),
      );
      expect(store.values, isEmpty);
    },
  );
}

class _MemorySecureStore implements LocalFirstSyncSecureStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
