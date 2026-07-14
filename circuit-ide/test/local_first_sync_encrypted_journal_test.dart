import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/services/local_first_sync_contract.dart';
import 'package:circuit_ide/services/local_first_sync_encrypted_journal.dart';
import 'package:circuit_ide/services/local_first_sync_encryption.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const projectId = 'project-journal-613d59a4';

  LocalFirstSyncOperation operation({
    required String id,
    required int tick,
    List<String> predecessors = const [],
    Map<String, Object?> payload = const {
      'kind': 'message',
      'content': 'Customer handoff discussion',
    },
  }) => LocalFirstSyncOperation(
    operationId: id,
    projectId: projectId,
    actorId: 'device-owner',
    predecessorIds: predecessors,
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

  LocalFirstSyncEncryptedJournal journalFor({
    required File file,
    required _MemorySecureStore store,
    int maxEntries = LocalFirstSyncEncryptedJournal.defaultMaxEntries,
  }) => LocalFirstSyncEncryptedJournal(
    projectId: projectId,
    file: file,
    maxEntries: maxEntries,
    cipher: LocalFirstSyncEnvelopeCipher(
      keyRing: LocalFirstSyncKeyRing(secureStore: store),
    ),
  );

  const authority = LocalFirstSyncProjectAuthority(
    projectId: projectId,
    projectOwnerActorId: 'device-owner',
  );

  test(
    'persists encrypted-only records atomically and reopens them for the local conflict simulator',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-local-first-sync-journal-',
      );
      addTearDown(() => root.delete(recursive: true));
      final journal = journalFor(
        file: File('${root.path}${Platform.pathSeparator}pending.json'),
        store: _MemorySecureStore(),
      );

      await Future.wait([
        journal.append(operation(id: 'op-journal-first', tick: 1)),
        journal.append(
          operation(
            id: 'op-journal-second',
            tick: 2,
            predecessors: const ['op-journal-first'],
          ),
        ),
      ]);

      final raw = await journal.file.readAsString();
      expect(raw, contains(LocalFirstSyncEncryptedJournal.format));
      expect(raw, contains('op-journal-first'));
      expect(raw, isNot(contains('Customer handoff discussion')));
      expect(raw, isNot(contains('device-owner')));
      expect(await journal.readEnvelopes(), hasLength(2));
      expect(
        (await journal.openAndMerge(
          authority: authority,
        )).events.map((event) => event.operationId),
        ['op-journal-first', 'op-journal-second'],
      );
      final entries = await root.list().toList();
      expect(
        entries.where((entry) => entry.path.contains('.staging-')),
        isEmpty,
      );
    },
  );

  test('rejects excluded data before creating a key or journal file', () async {
    final root = await Directory.systemTemp.createTemp(
      'circuit-local-first-sync-journal-forbidden-',
    );
    addTearDown(() => root.delete(recursive: true));
    final store = _MemorySecureStore();
    final journal = journalFor(
      file: File('${root.path}${Platform.pathSeparator}pending.json'),
      store: store,
    );

    await expectLater(
      journal.append(
        operation(
          id: 'op-journal-forbidden',
          tick: 3,
          payload: const {'clientSecret': 'seeded-secret'},
        ),
      ),
      throwsA(isA<LocalFirstSyncValidationException>()),
    );
    expect(await journal.file.exists(), isFalse);
    expect(store.values, isEmpty);
  });

  test(
    'refuses duplicate IDs and preserves the existing encrypted journal',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-local-first-sync-journal-duplicate-',
      );
      addTearDown(() => root.delete(recursive: true));
      final journal = journalFor(
        file: File('${root.path}${Platform.pathSeparator}pending.json'),
        store: _MemorySecureStore(),
        maxEntries: 1,
      );
      final first = operation(id: 'op-journal-once', tick: 4);
      await journal.append(first);

      await expectLater(
        journal.append(first),
        throwsA(isA<LocalFirstSyncJournalException>()),
      );
      await expectLater(
        journal.append(operation(id: 'op-journal-over-bound', tick: 5)),
        throwsA(isA<LocalFirstSyncJournalException>()),
      );
      expect(await journal.readEnvelopes(), hasLength(1));
    },
  );

  test('fails closed for tampered ciphertext and a journal symlink', () async {
    final root = await Directory.systemTemp.createTemp(
      'circuit-local-first-sync-journal-tamper-',
    );
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}${Platform.pathSeparator}pending.json');
    final journal = journalFor(file: file, store: _MemorySecureStore());
    await journal.append(operation(id: 'op-journal-tamper', tick: 6));
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final envelope = (json['envelopes'] as List).single as Map<String, dynamic>;
    final ciphertext = envelope['ciphertextBase64'] as String;
    envelope['ciphertextBase64'] =
        '${ciphertext.startsWith('A') ? 'B' : 'A'}${ciphertext.substring(1)}';
    await file.writeAsString(jsonEncode(json));
    await expectLater(
      journal.openAndMerge(authority: authority),
      throwsA(isA<LocalFirstSyncEncryptionException>()),
    );

    final linked = File('${root.path}${Platform.pathSeparator}linked.json');
    final outside = File('${root.path}${Platform.pathSeparator}outside.json');
    await outside.writeAsString('outside data must stay untouched');
    await Link(linked.path).create(outside.path);
    final linkedJournal = journalFor(file: linked, store: _MemorySecureStore());
    await expectLater(
      linkedJournal.readEnvelopes(),
      throwsA(isA<LocalFirstSyncJournalException>()),
    );
    expect(await outside.readAsString(), 'outside data must stay untouched');
  });
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
