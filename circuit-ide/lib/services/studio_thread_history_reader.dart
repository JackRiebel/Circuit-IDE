import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'versioned_json_document.dart';
import 'worker_cancellation.dart';

/// The one selected durable thread, decoded away from the Studio UI isolate.
///
/// Project rails intentionally retain summaries only. Hydrating one selected
/// thread must not parse and rebuild every archived transcript on the UI
/// isolate just because all threads share a durable history envelope.
class StudioThreadHistoryRecord {
  final Map<String, Object?>? thread;
  final String? legacyContents;

  const StudioThreadHistoryRecord({
    required this.thread,
    required this.legacyContents,
  });
}

/// Reads and validates the full durable envelope in a cancellable worker, but
/// returns only the selected thread's JSON-shaped record to the caller.
class StudioThreadHistoryReader {
  const StudioThreadHistoryReader();

  Future<StudioThreadHistoryRecord> readThread({
    required String path,
    required String expectedKind,
    required int currentSchemaVersion,
    required String threadId,
    WorkerCancellationToken? cancellationToken,
  }) {
    return CancellableWorker.run<StudioThreadHistoryRecord>(
      entryPoint: _studioThreadHistoryWorkerEntry,
      arguments: {
        'path': path,
        'expectedKind': expectedKind,
        'currentSchemaVersion': currentSchemaVersion,
        'threadId': threadId,
      },
      cancellationToken: cancellationToken,
      decodeResult: (result) {
        if (result is! Map) {
          throw StateError(
            'Thread-history worker returned a malformed result.',
          );
        }
        Map<String, Object?>? thread;
        final rawThread = result['thread'];
        if (rawThread is Map) {
          thread = Map<String, Object?>.from(rawThread);
        }
        final legacyContents = result['legacyContents'];
        if (legacyContents != null && legacyContents is! String) {
          throw StateError(
            'Thread-history worker returned invalid migration data.',
          );
        }
        return StudioThreadHistoryRecord(
          thread: thread,
          legacyContents: legacyContents as String?,
        );
      },
    );
  }
}

/// Reads an append-only crash journal away from the UI isolate. Only checksum-
/// verified payload records cross the isolate boundary; malformed or tampered
/// bytes remain individually recoverable just as they are in the durable
/// storage fallback.
class StudioThreadJournalReader {
  const StudioThreadJournalReader();

  Future<List<Map<String, Object?>>> read({
    required String path,
    required String envelopeKind,
    WorkerCancellationToken? cancellationToken,
  }) {
    return CancellableWorker.run<List<Map<String, Object?>>>(
      entryPoint: _studioThreadJournalWorkerEntry,
      arguments: {'path': path, 'envelopeKind': envelopeKind},
      cancellationToken: cancellationToken,
      decodeResult: (result) {
        if (result is! List) {
          throw StateError('Thread-journal worker returned malformed records.');
        }
        return [
          for (final raw in result)
            if (raw is Map) Map<String, Object?>.from(raw),
        ];
      },
    );
  }
}

void _studioThreadHistoryWorkerEntry(Map<String, Object?> arguments) {
  final replyPort = arguments['replyPort'];
  if (replyPort is! SendPort) return;
  try {
    final currentSchemaVersion = arguments['currentSchemaVersion'];
    if (currentSchemaVersion is! int) {
      throw const FormatException('Thread history schema version is invalid.');
    }
    final contents = File(
      arguments['path'] as String? ?? '',
    ).readAsStringSync();
    final document = VersionedJsonDocument.decode(
      jsonDecode(contents),
      expectedKind: arguments['expectedKind'] as String? ?? '',
      currentSchemaVersion: currentSchemaVersion,
    );
    final payload = document.payload;
    if (payload is! List) {
      throw const FormatException(
        'Studio thread history payload is not a list.',
      );
    }
    Map<String, Object?>? selected;
    final threadId = arguments['threadId'] as String? ?? '';
    for (final value in payload) {
      if (value is! Map || value['id'] != threadId) continue;
      selected = Map<String, Object?>.from(value);
      break;
    }
    replyPort.send({
      'result': {
        'thread': selected,
        // Only migrations need the original source bytes. Current-schema
        // hydration sends a single selected record back to the UI isolate.
        'legacyContents': document.schemaVersion < currentSchemaVersion
            ? contents
            : null,
      },
    });
  } catch (error) {
    replyPort.send({'error': error.toString()});
  }
}

void _studioThreadJournalWorkerEntry(Map<String, Object?> arguments) {
  final replyPort = arguments['replyPort'];
  if (replyPort is! SendPort) return;
  try {
    final bytes = File(arguments['path'] as String? ?? '').readAsBytesSync();
    final records = <Map<String, Object?>>[];
    final envelopeKind = arguments['envelopeKind'] as String? ?? '';
    for (final rawLine in const LineSplitter().convert(
      utf8.decode(bytes, allowMalformed: true),
    )) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final record = _decodeJournalRecord(line, envelopeKind: envelopeKind);
      if (record != null) records.add(record);
    }
    replyPort.send({'result': records});
  } catch (error) {
    replyPort.send({'error': error.toString()});
  }
}

Map<String, Object?>? _decodeJournalRecord(
  String line, {
  required String envelopeKind,
}) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map) return null;
    final record = Map<String, Object?>.from(decoded);
    if (record['envelopeKind'] != envelopeKind) return record;
    final payload = record['payload'];
    final checksum = record['checksum'];
    if (payload is! Map ||
        checksum is! String ||
        checksum != VersionedJsonDocument.checksumFor(payload)) {
      return null;
    }
    return Map<String, Object?>.from(payload);
  } catch (_) {
    return null;
  }
}
