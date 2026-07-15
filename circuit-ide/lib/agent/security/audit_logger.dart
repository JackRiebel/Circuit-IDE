import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/utils/platform_utils.dart';

/// Conservative redaction for persisted diagnostics. Diagnostic records are
/// useful only when they cannot become an alternate store for prompts,
/// workspace contents, credentials, or local machine paths.
class AuditRedactor {
  static const _redacted = '[REDACTED]';

  static const _contentKeys = {
    'content',
    'contents',
    'body',
    'data',
    'input',
    'prompt',
    'result',
    'stdout',
    'stderr',
    'output',
    'message',
    'response',
    'file',
    'filecontents',
    'command',
  };
  static const _secretKeys = {
    'token',
    'apikey',
    'api_key',
    'authorization',
    'credential',
    'credentials',
    'secret',
    'password',
    'privatekey',
    'private_key',
    'cookie',
    'set-cookie',
    'env',
    'environment',
  };
  static const _pathKeys = {
    'path',
    'filepath',
    'file_path',
    'directory',
    'cwd',
  };
  static const _urlKeys = {'url', 'uri', 'endpoint', 'origin', 'host'};

  dynamic redactValue(dynamic value, {String? key}) {
    final normalizedKey = key?.trim().toLowerCase() ?? '';
    if (_contentKeys.contains(normalizedKey)) {
      return _contentSummary(value);
    }
    if (_secretKeys.contains(normalizedKey)) return _redacted;
    if (_pathKeys.contains(normalizedKey)) {
      return _redactPath(value?.toString());
    }
    if (_urlKeys.contains(normalizedKey)) return _redactUrl(value?.toString());
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): redactValue(
            entry.value,
            key: entry.key.toString(),
          ),
      };
    }
    if (value is Iterable) {
      return value.map((item) => redactValue(item, key: key)).toList();
    }
    return value is String ? redactText(value) : value;
  }

  String redactText(String value) {
    var redacted = value;
    // Stack frames and third-party diagnostics occasionally include a prompt
    // assignment on the same line as an otherwise useful frame. Unlike a
    // credential, prompt text commonly contains whitespace, so redact the
    // entire remainder of that diagnostic line instead of only its first word.
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'\b(prompt|user[_ -]?prompt)\b\s*([:=])\s*[^\r\n]*',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}${match.group(2)}$_redacted',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'''\b(bearer|token|api[-_ ]?key|authorization|password|secret|client_secret)\b\s*([:=])\s*([^\s,;"']+)''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}${match.group(2)}$_redacted',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(r'''\bbearer\s+[a-z0-9._~+/=-]+''', caseSensitive: false),
      (_) => 'Bearer $_redacted',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(r'''\b(?:sk|rk|pk|xox[baprs])-[a-zA-Z0-9_-]{12,}\b'''),
      (_) => _redacted,
    );
    redacted = redacted.replaceAllMapped(
      RegExp(r'''https?://[^\s'"<>]+''', caseSensitive: false),
      (match) => _redactUrl(match.group(0)),
    );
    redacted = redacted.replaceAllMapped(
      RegExp(r'''(?<![\w.-])(?:/Users|/home|/private|/var|/etc)/[^\s'"<>]+'''),
      (_) => '[PATH]',
    );
    redacted = redacted.replaceAllMapped(
      RegExp(
        r'''\b[A-Z_][A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|API_KEY)\s*=\s*[^\s,;]+''',
        caseSensitive: false,
      ),
      (match) {
        final equals = match.group(0)!.indexOf('=');
        return '${match.group(0)!.substring(0, equals + 1)}$_redacted';
      },
    );
    return redacted;
  }

  /// Provider diagnostics are not durable transcripts. Keep the actionable
  /// category/detail while suppressing any raw transport body that might carry
  /// prompt or tenant data.
  String redactDiagnostic(String value) => redactText(value);

  String redactedDiagnosticBody(String value) =>
      '[REDACTED DIAGNOSTIC BODY (${value.length} chars)]';

  String _contentSummary(Object? value) {
    final length = value?.toString().length ?? 0;
    return '[REDACTED CONTENT${length == 0 ? '' : ' ($length chars)'}]';
  }

  String _redactPath(String? path) {
    if (path == null || path.trim().isEmpty) return _redacted;
    return '[PATH]';
  }

  String _redactUrl(String? value) {
    if (value == null || value.trim().isEmpty) return _redacted;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) return _redacted;
    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://${uri.host}$port/[REDACTED]';
  }
}

class AuditLogSession {
  final String id;
  final DateTime modifiedAt;
  final int byteLength;

  const AuditLogSession({
    required this.id,
    required this.modifiedAt,
    required this.byteLength,
  });
}

class AuditLogger {
  final String? directoryPath;
  final Duration retention;
  final AuditRedactor redactor;
  File? _logFile;
  bool _initialized = false;

  AuditLogger({
    this.directoryPath,
    this.retention = const Duration(days: 14),
    AuditRedactor? redactor,
  }) : redactor = redactor ?? AuditRedactor();

  String get _auditDirectoryPath =>
      directoryPath ??
      p.join(PlatformUtils.configDir, AppConstants.auditDirName);

  Future<void> init() async {
    final auditDir = Directory(_auditDirectoryPath);
    if (!await auditDir.exists()) {
      await auditDir.create(recursive: true);
    }
    await purgeExpired();

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    _logFile = File(p.join(auditDir.path, 'session-$timestamp.jsonl'));
    _initialized = true;
  }

  Future<void> _log(Map<String, dynamic> entry) async {
    final logFile = _logFile;
    if (!_initialized || logFile == null) return;
    final safe = redactor.redactValue(entry) as Map<String, dynamic>;
    safe['timestamp'] = DateTime.now().toIso8601String();
    await logFile.writeAsString('${jsonEncode(safe)}\n', mode: FileMode.append);
  }

  Future<void> logUserInput(String input) async {
    await _log({
      'type': 'user_input',
      'preview': '[REDACTED PROMPT (${input.length} chars)]',
    });
  }

  Future<void> logApiCall(
    String model,
    int promptTokens,
    int completionTokens,
  ) async {
    await _log({
      'type': 'api_call',
      'model': model,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
    });
  }

  Future<void> logToolCall(
    String toolName,
    Map<String, dynamic> args,
    String result,
    bool success,
  ) async {
    await _log({
      'type': 'tool_call',
      'tool': toolName,
      'args': args,
      'result_preview': '[REDACTED TOOL RESULT (${result.length} chars)]',
      'success': success,
    });
  }

  Future<void> logFileOperation(
    String operation,
    String path,
    bool success,
  ) async {
    await _log({
      'type': 'file_operation',
      'operation': operation,
      'path': path,
      'success': success,
    });
  }

  Future<void> logError(
    String errorType,
    String message,
    Map<String, dynamic> context,
  ) async {
    await _log({
      'type': 'error',
      'error_type': errorType,
      'message': message,
      'context': context,
    });
  }

  Future<List<AuditLogSession>> listSessions() async {
    final directory = Directory(_auditDirectoryPath);
    if (!await directory.exists()) return const [];
    final sessions = <AuditLogSession>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !p.basename(entity.path).startsWith('session-')) {
        continue;
      }
      final stat = await entity.stat();
      sessions.add(
        AuditLogSession(
          id: p.basename(entity.path),
          modifiedAt: stat.modified,
          byteLength: stat.size,
        ),
      );
    }
    sessions.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return sessions;
  }

  Future<String?> inspectSession(String id) async {
    final records = await _redactedSessionRecords(id);
    if (records == null) return null;
    // Re-redact structured records before handing a retained diagnostic to any
    // UI or exporter. This protects users who still have pre-redaction logs.
    return const JsonEncoder.withIndent('  ').convert(records);
  }

  /// Builds a user-shareable diagnostic bundle from retained audit sessions.
  /// The bundle intentionally contains only redacted metadata and records;
  /// callers must not add prompts, workspace paths, raw provider bodies, or
  /// credentials to [metadata]. The redactor is still applied defensively.
  Future<String> buildSupportBundle({
    Map<String, dynamic> metadata = const {},
    Iterable<String>? sessionIds,
  }) async {
    await purgeExpired();
    final available = await listSessions();
    final requestedIds = sessionIds?.toSet();
    final sessions = requestedIds == null
        ? available
        : available
              .where((session) => requestedIds.contains(session.id))
              .toList(growable: false);
    final redactedSessions = <Map<String, dynamic>>[];
    for (final session in sessions) {
      final records = await _redactedSessionRecords(session.id);
      if (records == null) continue;
      redactedSessions.add({
        'id': session.id,
        'modifiedAt': session.modifiedAt.toUtc().toIso8601String(),
        'byteLength': session.byteLength,
        'records': records,
      });
    }
    return const JsonEncoder.withIndent('  ').convert({
      'schema': 'circuit.support-bundle',
      'schemaVersion': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'metadata': redactor.redactValue(metadata),
      'auditSessions': redactedSessions,
    });
  }

  /// Writes a bundle only to a path selected by the user. This method never
  /// reads arbitrary local files; it exports the redacted audit store above.
  Future<File> exportSupportBundle(
    String destinationPath, {
    Map<String, dynamic> metadata = const {},
    Iterable<String>? sessionIds,
  }) async {
    final normalizedPath = destinationPath.trim();
    if (normalizedPath.isEmpty) {
      throw ArgumentError.value(
        destinationPath,
        'destinationPath',
        'Choose a destination for the support bundle.',
      );
    }
    final bundle = await buildSupportBundle(
      metadata: metadata,
      sessionIds: sessionIds,
    );
    final destination = File(normalizedPath);
    await destination.parent.create(recursive: true);
    await destination.writeAsString(bundle, flush: true);
    return destination;
  }

  Future<bool> deleteSession(String id) async {
    final file = _sessionFile(id);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  Future<int> purgeExpired({DateTime? now}) async {
    final directory = Directory(_auditDirectoryPath);
    if (!await directory.exists()) return 0;
    final cutoff = (now ?? DateTime.now()).subtract(retention);
    var purged = 0;
    await for (final entity in directory.list()) {
      if (entity is! File || !p.basename(entity.path).startsWith('session-')) {
        continue;
      }
      if ((await entity.stat()).modified.isBefore(cutoff)) {
        await entity.delete();
        purged++;
      }
    }
    return purged;
  }

  File _sessionFile(String id) {
    final fileName = p.basename(id);
    if (!fileName.startsWith('session-') || !fileName.endsWith('.jsonl')) {
      throw ArgumentError.value(id, 'id', 'Invalid audit session id.');
    }
    return File(p.join(_auditDirectoryPath, fileName));
  }

  Future<List<Map<String, dynamic>>?> _redactedSessionRecords(String id) async {
    final file = _sessionFile(id);
    if (!await file.exists()) return null;
    final records = <Map<String, dynamic>>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          final redacted = redactor.redactValue(decoded);
          records.add(Map<String, dynamic>.from(redacted as Map));
          continue;
        }
      } catch (_) {
        // Preserve the fact that a retained record was malformed without
        // copying its bytes into a support surface.
      }
      records.add({
        'type': 'unparseable_diagnostic',
        'preview': redactor.redactedDiagnosticBody(line),
      });
    }
    return records;
  }
}
