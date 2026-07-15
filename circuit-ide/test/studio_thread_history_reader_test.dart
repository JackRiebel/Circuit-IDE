import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/services/studio_thread_history_reader.dart';
import 'package:circuit_ide/services/versioned_json_document.dart';
import 'package:circuit_ide/services/worker_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'worker returns only the selected current-schema thread record',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'thread-history-reader-',
      );
      addTearDown(() => root.delete(recursive: true));
      final history = File('${root.path}${Platform.pathSeparator}threads.json');
      final payload = [
        for (var index = 0; index < 1000; index++)
          {
            'id': 'thread-$index',
            'title': 'Archived transcript $index',
            'turns': [
              {'id': 'turn-$index', 'prompt': 'private payload $index'},
            ],
          },
      ];
      await history.writeAsString(
        VersionedJsonDocument(
          kind: 'circuit.studio-thread-history',
          schemaVersion: 3,
          payload: payload,
        ).encode(),
      );

      final record = await const StudioThreadHistoryReader().readThread(
        path: history.path,
        expectedKind: 'circuit.studio-thread-history',
        currentSchemaVersion: 3,
        threadId: 'thread-777',
      );

      expect(record.legacyContents, isNull);
      expect(record.thread?['id'], 'thread-777');
      expect(record.thread?['title'], 'Archived transcript 777');
      expect(record.thread?['turns'], hasLength(1));
    },
  );

  test('worker cancellation fails before reading the history file', () async {
    final cancellation = WorkerCancellationToken()
      ..cancel('Test cancellation.');

    await expectLater(
      const StudioThreadHistoryReader().readThread(
        path: '/missing/history.json',
        expectedKind: 'circuit.studio-thread-history',
        currentSchemaVersion: 3,
        threadId: 'thread',
        cancellationToken: cancellation,
      ),
      throwsA(isA<WorkerCancelledException>()),
    );
  });

  test('journal worker keeps only checksum-verified payload records', () async {
    final root = await Directory.systemTemp.createTemp(
      'thread-journal-reader-',
    );
    addTearDown(() => root.delete(recursive: true));
    final journal = File('${root.path}${Platform.pathSeparator}threads.jsonl');
    const payload = {
      'kind': 'thread_snapshot',
      'threadId': 'thread-verified',
      'thread': {'id': 'thread-verified', 'title': 'Verified journal'},
    };
    await journal.writeAsString(
      [
        jsonEncode({
          'envelopeKind': 'circuit.studio-thread-journal-record',
          'payload': payload,
          'checksum': VersionedJsonDocument.checksumFor(payload),
        }),
        'not-json',
        jsonEncode({
          'envelopeKind': 'circuit.studio-thread-journal-record',
          'payload': {'kind': 'thread_snapshot', 'threadId': 'tampered'},
          'checksum': 'not-a-valid-checksum',
        }),
      ].join('\n'),
    );

    final records = await const StudioThreadJournalReader().read(
      path: journal.path,
      envelopeKind: 'circuit.studio-thread-journal-record',
    );

    expect(records, hasLength(1));
    expect(records.single['threadId'], 'thread-verified');
  });
}
