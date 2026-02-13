import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/platform_utils.dart';
import '../../core/constants/app_constants.dart';

class AuditLogger {
  late final File _logFile;
  bool _initialized = false;

  Future<void> init() async {
    final auditDir = Directory(
        p.join(PlatformUtils.configDir, AppConstants.auditDirName));
    if (!await auditDir.exists()) {
      await auditDir.create(recursive: true);
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    _logFile = File(p.join(auditDir.path, 'session-$timestamp.jsonl'));
    _initialized = true;
  }

  Future<void> _log(Map<String, dynamic> entry) async {
    if (!_initialized) return;
    entry['timestamp'] = DateTime.now().toIso8601String();
    await _logFile.writeAsString(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
    );
  }

  Future<void> logUserInput(String input) async {
    await _log({
      'type': 'user_input',
      'preview': input.length > 100 ? '${input.substring(0, 100)}...' : input,
    });
  }

  Future<void> logApiCall(String model, int promptTokens, int completionTokens) async {
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
      'result_preview':
          result.length > 200 ? '${result.substring(0, 200)}...' : result,
      'success': success,
    });
  }

  Future<void> logFileOperation(
      String operation, String path, bool success) async {
    await _log({
      'type': 'file_operation',
      'operation': operation,
      'path': path,
      'success': success,
    });
  }

  Future<void> logError(
      String errorType, String message, Map<String, dynamic> context) async {
    await _log({
      'type': 'error',
      'error_type': errorType,
      'message': message,
      'context': context,
    });
  }
}
