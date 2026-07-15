import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../agent/security/audit_logger.dart';
import '../core/utils/platform_utils.dart';
import 'versioned_json_document.dart';

/// Stable crash-ledger events. Breadcrumbs cannot carry arbitrary user text.
enum CrashBreadcrumbEvent {
  appStarted('app.started'),
  turnStarted('turn.started'),
  turnFailed('turn.failed'),
  artifactGenerationFailed('artifact.generation_failed');

  final String id;

  const CrashBreadcrumbEvent(this.id);
}

/// A local-only crash ledger. Collection remains off by default and this class
/// deliberately has no transport or endpoint configuration: users may inspect
/// and export the redacted records themselves when support asks for evidence.
class PrivacyCrashReporter {
  static const _fileName = 'redacted_crash_reports.jsonl';
  static const maxBreadcrumbs = 24;
  static const defaultLedgerByteLimit = 1024 * 1024;

  final bool Function() isEnabled;
  final String? directoryPath;
  final int ledgerByteLimit;
  final AuditRedactor redactor;
  final List<CrashBreadcrumb> _breadcrumbs = [];
  Future<void> _pendingAsyncWrite = Future.value();
  int _stagedFileSequence = 0;

  PrivacyCrashReporter({
    required this.isEnabled,
    this.directoryPath,
    this.ledgerByteLimit = defaultLedgerByteLimit,
    AuditRedactor? redactor,
  }) : assert(ledgerByteLimit > 0),
       redactor = redactor ?? AuditRedactor();

  String get filePath => p.join(
    directoryPath ?? p.join(PlatformUtils.configDir, 'crash_reports'),
    _fileName,
  );

  void addBreadcrumb(
    CrashBreadcrumbEvent event, {
    Map<String, Object?> metadata = const {},
  }) {
    _breadcrumbs.add(
      CrashBreadcrumb(
        eventId: event.id,
        timestamp: DateTime.now().toUtc(),
        metadata: Map<String, Object?>.from(
          redactor.redactValue(metadata) as Map,
        ),
      ),
    );
    if (_breadcrumbs.length > maxBreadcrumbs) {
      _breadcrumbs.removeRange(0, _breadcrumbs.length - maxBreadcrumbs);
    }
  }

  Future<void> record({
    required Object error,
    required StackTrace stackTrace,
    required String source,
  }) async {
    final event = _eventFor(
      error: error,
      stackTrace: stackTrace,
      source: source,
    );
    if (event == null) return;
    final write = _pendingAsyncWrite.then<void>((_) => _writeEventAsync(event));
    _pendingAsyncWrite = write.catchError((_) {});
    await write;
  }

  /// Flushes one already-redacted record for an unhandled-error boundary.
  ///
  /// This is deliberately limited to the same small event shape as [record].
  /// Synchronous I/O prevents a fatal platform error from losing an opt-in
  /// local report before the process exits.
  void recordSync({
    required Object error,
    required StackTrace stackTrace,
    required String source,
  }) {
    final event = _eventFor(
      error: error,
      stackTrace: stackTrace,
      source: source,
    );
    if (event == null) return;
    try {
      final file = File(filePath);
      file.parent.createSync(recursive: true);
      final existing = _safeLedgerBytesSync(file);
      final line = _eventLine(event);
      if (existing == null || line == null) return;
      _replaceLedgerSync(file, _appendBounded(existing, line));
    } catch (_) {
      // A failed diagnostic write must never create a secondary app failure.
    }
  }

  Future<List<CrashReportEvent>> load() async {
    final file = File(filePath);
    final bytes = await _safeLedgerBytes(file);
    if (bytes == null || bytes.isEmpty) return const [];
    final events = <CrashReportEvent>[];
    for (final line in const LineSplitter().convert(utf8.decode(bytes))) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          final event = CrashReportEvent.fromJson(decoded);
          if (event != null) events.add(event);
        }
      } catch (_) {
        // An incomplete crash write does not hide earlier usable records.
      }
    }
    return events.reversed.toList(growable: false);
  }

  Future<void> _writeEventAsync(CrashReportEvent event) async {
    try {
      final file = File(filePath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final existing = await _safeLedgerBytes(file);
      final line = _eventLine(event);
      if (existing == null || line == null) return;
      await _replaceLedger(file, _appendBounded(existing, line));
    } catch (_) {
      // A failed diagnostic write must never create a secondary app failure.
    }
  }

  /// Refuses a link, directory, or unexpectedly large ledger rather than
  /// following it. A regular oversized legacy ledger is safely replaced by
  /// the next bounded event, without first loading unbounded data into memory.
  Future<List<int>?> _safeLedgerBytes(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return const <int>[];
    if (type != FileSystemEntityType.file) return null;
    if (await file.length() > ledgerByteLimit) return const <int>[];
    final bytes = await file.readAsBytes();
    final typeAfterRead = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );
    if (typeAfterRead != FileSystemEntityType.file ||
        bytes.length > ledgerByteLimit) {
      return null;
    }
    return bytes;
  }

  List<int>? _safeLedgerBytesSync(File file) {
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return const <int>[];
    if (type != FileSystemEntityType.file) return null;
    if (file.lengthSync() > ledgerByteLimit) return const <int>[];
    final bytes = file.readAsBytesSync();
    final typeAfterRead = FileSystemEntity.typeSync(
      file.path,
      followLinks: false,
    );
    if (typeAfterRead != FileSystemEntityType.file ||
        bytes.length > ledgerByteLimit) {
      return null;
    }
    return bytes;
  }

  List<int>? _eventLine(CrashReportEvent event) {
    final line = utf8.encode('${jsonEncode(event.toJson())}\n');
    // Keep every retained record complete JSONL. Skipping an unusually large
    // diagnostic is safer than truncating it into a malformed or unbounded
    // local crash record.
    return line.length <= ledgerByteLimit ? line : null;
  }

  List<int> _appendBounded(List<int> existing, List<int> line) {
    final combined = <int>[...existing, ...line];
    if (combined.length <= ledgerByteLimit) return combined;
    final firstCompleteLine = combined.indexOf(
      0x0a,
      combined.length - ledgerByteLimit,
    );
    return firstCompleteLine == -1
        ? List<int>.from(line)
        : combined.sublist(firstCompleteLine + 1);
  }

  File _stagedLedgerFile(File target) => File(
    '${target.path}.staging-${DateTime.now().microsecondsSinceEpoch}-$pid-'
    '${Random.secure().nextInt(1 << 32)}-${_stagedFileSequence++}',
  );

  Future<void> _replaceLedger(File target, List<int> bytes) async {
    final staged = _stagedLedgerFile(target);
    try {
      await staged.create(exclusive: true);
      final handle = await staged.open(mode: FileMode.write);
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
      // A sibling rename writes a complete ledger at once and cannot follow a
      // pre-existing ledger symlink into another file.
      await staged.rename(target.path);
    } finally {
      if (await FileSystemEntity.type(staged.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        await staged.delete();
      }
    }
  }

  void _replaceLedgerSync(File target, List<int> bytes) {
    final staged = _stagedLedgerFile(target);
    try {
      staged.createSync(exclusive: true);
      final handle = staged.openSync(mode: FileMode.write);
      try {
        handle.writeFromSync(bytes);
        handle.flushSync();
      } finally {
        handle.closeSync();
      }
      staged.renameSync(target.path);
    } finally {
      if (FileSystemEntity.typeSync(staged.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        staged.deleteSync();
      }
    }
  }

  Future<void> export(File destination) async {
    final events = await load();
    final payload = {
      'kind': 'circuit.redacted-crash-report-export',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'records': events.map((event) => event.toJson()).toList(),
    };
    final safe = redactor.redactValue(payload) as Map;
    await writeVersionedJsonAtomically(
      destination,
      const JsonEncoder.withIndent('  ').convert(safe),
    );
  }

  String _redactedStack(String value) {
    final lines = const LineSplitter()
        .convert(value)
        .where((line) => RegExp(r'^\s*#\d+\s+').hasMatch(line))
        .take(32)
        .map(redactor.redactDiagnostic)
        .toList(growable: false);
    return lines.isEmpty ? '[STACK TRACE UNAVAILABLE]' : lines.join('\n');
  }

  CrashReportEvent? _eventFor({
    required Object error,
    required StackTrace stackTrace,
    required String source,
  }) {
    if (!isEnabled()) return null;
    return CrashReportEvent(
      timestamp: DateTime.now().toUtc(),
      source: _category(source),
      error: _errorSummary(error),
      stack: _redactedStack(stackTrace.toString()),
      breadcrumbs: List.unmodifiable(_breadcrumbs),
    );
  }

  String _errorSummary(Object error) =>
      '${error.runtimeType}: [REDACTED DIAGNOSTIC BODY]';

  String _category(String source) {
    final normalized = source.trim().toLowerCase();
    return switch (normalized) {
      'flutter' || 'platform' || 'runtime' => normalized,
      _ => 'runtime',
    };
  }
}

class CrashBreadcrumb {
  final String eventId;
  final DateTime timestamp;
  final Map<String, Object?> metadata;

  const CrashBreadcrumb({
    required this.eventId,
    required this.timestamp,
    this.metadata = const {},
  });

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'timestamp': timestamp.toIso8601String(),
    'metadata': metadata,
  };

  static CrashBreadcrumb? fromJson(Object? value) {
    if (value is! Map) return null;
    final eventId = value['eventId']?.toString().trim() ?? '';
    final timestamp = DateTime.tryParse(value['timestamp']?.toString() ?? '');
    if (eventId.isEmpty || timestamp == null) return null;
    final metadata = value['metadata'] is Map
        ? Map<String, Object?>.from(value['metadata'] as Map)
        : const <String, Object?>{};
    return CrashBreadcrumb(
      eventId: eventId,
      timestamp: timestamp.toUtc(),
      metadata: metadata,
    );
  }
}

class CrashReportEvent {
  final DateTime timestamp;
  final String source;
  final String error;
  final String stack;
  final List<CrashBreadcrumb> breadcrumbs;

  const CrashReportEvent({
    required this.timestamp,
    required this.source,
    required this.error,
    required this.stack,
    this.breadcrumbs = const [],
  });

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'error': error,
    'stack': stack,
    'breadcrumbs': breadcrumbs
        .map((breadcrumb) => breadcrumb.toJson())
        .toList(),
  };

  static CrashReportEvent? fromJson(Map<String, dynamic> value) {
    final timestamp = DateTime.tryParse(value['timestamp']?.toString() ?? '');
    final source = value['source']?.toString() ?? '';
    final error = value['error']?.toString() ?? '';
    final stack = value['stack']?.toString() ?? '';
    if (timestamp == null || source.isEmpty || error.isEmpty) return null;
    return CrashReportEvent(
      timestamp: timestamp.toUtc(),
      source: source,
      error: error,
      stack: stack,
      breadcrumbs:
          (value['breadcrumbs'] as List?)
              ?.map(CrashBreadcrumb.fromJson)
              .whereType<CrashBreadcrumb>()
              .toList(growable: false) ??
          const [],
    );
  }
}
