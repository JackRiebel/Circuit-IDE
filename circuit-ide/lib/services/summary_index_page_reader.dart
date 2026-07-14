import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'worker_cancellation.dart';

/// One metadata page read from a durable JSON-lines summary index.
///
/// Project rails can contain thousands of archived tasks and threads. Reading
/// and decoding the complete index is filesystem and JSON work, so it belongs
/// in a worker isolate even though the caller keeps only one small page.
class SummaryIndexPageData {
  final int declaredTotalCount;
  final int readableRecordCount;
  final List<Map<String, Object?>> records;

  const SummaryIndexPageData({
    required this.declaredTotalCount,
    required this.readableRecordCount,
    required this.records,
  });

  int get totalCount => declaredTotalCount < readableRecordCount
      ? readableRecordCount
      : declaredTotalCount;
}

/// Reads only the requested metadata page while keeping index scanning and
/// malformed-row handling out of the UI isolate.
class SummaryIndexPageReader {
  const SummaryIndexPageReader();

  Future<SummaryIndexPageData> read({
    required String path,
    required String headerKind,
    required int offset,
    required int limit,
    WorkerCancellationToken? cancellationToken,
  }) {
    return CancellableWorker.run<SummaryIndexPageData>(
      entryPoint: _summaryIndexPageWorkerEntry,
      arguments: {
        'path': path,
        'headerKind': headerKind,
        'offset': offset,
        'limit': limit,
      },
      cancellationToken: cancellationToken,
      decodeResult: (result) {
        if (result is! Map) {
          throw StateError('Summary-index worker returned a malformed page.');
        }
        final records = <Map<String, Object?>>[];
        final rawRecords = result['records'];
        if (rawRecords is List) {
          for (final rawRecord in rawRecords) {
            if (rawRecord is Map) {
              records.add(Map<String, Object?>.from(rawRecord));
            }
          }
        }
        return SummaryIndexPageData(
          declaredTotalCount: result['declaredTotalCount'] as int? ?? 0,
          readableRecordCount: result['readableRecordCount'] as int? ?? 0,
          records: records,
        );
      },
    );
  }
}

void _summaryIndexPageWorkerEntry(Map<String, Object?> arguments) {
  final replyPort = arguments['replyPort'];
  if (replyPort is! SendPort) return;
  try {
    replyPort.send({
      'result': _readSummaryIndexPage(
        path: arguments['path'] as String? ?? '',
        headerKind: arguments['headerKind'] as String? ?? '',
        offset: arguments['offset'] as int? ?? 0,
        limit: arguments['limit'] as int? ?? 1,
      ),
    });
  } catch (error) {
    replyPort.send({'error': error.toString()});
  }
}

Map<String, Object?> _readSummaryIndexPage({
  required String path,
  required String headerKind,
  required int offset,
  required int limit,
}) {
  var declaredTotalCount = 0;
  var readableRecordCount = 0;
  final records = <Map<String, Object?>>[];
  final safeOffset = offset < 0 ? 0 : offset;
  final safeLimit = limit.clamp(1, 100);
  final file = File(path);

  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) continue;
      final record = Map<String, Object?>.from(decoded);
      if (record['kind'] == headerKind) {
        declaredTotalCount = record['totalCount'] as int? ?? 0;
        continue;
      }
      if (readableRecordCount++ < safeOffset) continue;
      if (records.length >= safeLimit) continue;
      records.add(record);
    } catch (_) {
      // One corrupt JSON-line row must not hide later archived history.
    }
  }

  return {
    'declaredTotalCount': declaredTotalCount,
    'readableRecordCount': readableRecordCount,
    'records': records,
  };
}
