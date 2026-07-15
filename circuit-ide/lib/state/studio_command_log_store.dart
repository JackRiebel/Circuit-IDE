import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils/platform_utils.dart';
import '../models/tool_result_envelope.dart';

const inlineCommandOutputLimit = 1600;
const commandOutputTailLength = 1200;

class StudioCommandLogStore {
  final String baseDir;

  StudioCommandLogStore({String? baseDir})
    : baseDir =
          baseDir ?? p.join(PlatformUtils.configDir, 'studio-command-logs');

  String? write({
    required String requestId,
    required String turnId,
    required String commandRunId,
    required String command,
    required String status,
    required String output,
    int? exitCode,
  }) {
    if (output.trim().isEmpty || output.length <= inlineCommandOutputLimit) {
      return null;
    }
    try {
      final safeRequestId = _safeLogPart(requestId);
      final safeCommandRunId = _safeLogPart(commandRunId);
      final safeTurnId = _safeLogPart(turnId);
      final dir = Directory(p.join(baseDir, safeRequestId));
      dir.createSync(recursive: true);
      final file = File(p.join(dir.path, '$safeTurnId-$safeCommandRunId.log'));
      file.writeAsStringSync(
        [
          'Command: $command',
          'Status: $status',
          if (exitCode != null) 'Exit code: $exitCode',
          'Request: $requestId',
          'Turn: $turnId',
          'Command run: $commandRunId',
          '',
          'Output:',
          output,
        ].join('\n'),
      );
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static String _safeLogPart(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }
}

ToolResultEnvelope compactCommandToolResult({
  required ToolResultEnvelope result,
  required StudioCommandLogStore store,
  required String requestId,
  required String turnId,
}) {
  if (result.toolName != 'run_command') return result;
  if (result.data['outputTruncated'] == true) return result;
  final combinedOutput = [
    if (result.stdout?.trim().isNotEmpty == true) result.stdout!.trim(),
    if (result.stderr?.trim().isNotEmpty == true) result.stderr!.trim(),
    if (result.diagnostic?.trim().isNotEmpty == true) result.diagnostic!.trim(),
  ].join('\n');
  if (combinedOutput.length <= inlineCommandOutputLimit) return result;
  final command = (result.data['command'] as String?)?.trim() ?? '';
  final logPath = store.write(
    requestId: requestId,
    turnId: turnId,
    commandRunId: result.toolCallId,
    command: command,
    status: result.status.name,
    output: combinedOutput,
    exitCode: result.data['exitCode'] as int?,
  );
  return ToolResultEnvelope(
    toolCallId: result.toolCallId,
    toolName: result.toolName,
    status: result.status,
    summary: result.summary,
    data: {...result.data, 'outputTruncated': true, 'logPath': ?logPath},
    stdout: _summarizeNullableOutput(result.stdout),
    stderr: _summarizeNullableOutput(result.stderr),
    artifacts: result.artifacts,
    changedFiles: result.changedFiles,
    diagnostic: [
      if (result.diagnostic?.trim().isNotEmpty == true)
        _summarizeCommandOutput(result.diagnostic!.trim(), null),
      if (logPath != null) 'Full log: $logPath',
    ].where((line) => line.trim().isNotEmpty).join('\n'),
    retryable: result.retryable,
  );
}

String? _summarizeNullableOutput(String? output) {
  final trimmed = output?.trim();
  if (trimmed == null || trimmed.isEmpty) return output;
  return _summarizeCommandOutput(trimmed, null);
}

String summarizeCommandOutput(String output, String? commandLogPath) {
  return _summarizeCommandOutput(output, commandLogPath);
}

String _summarizeCommandOutput(String output, String? commandLogPath) {
  if (output.length <= inlineCommandOutputLimit) return output;
  final tailStart = output.length - commandOutputTailLength;
  return [
    'Output tail (${output.length} chars total):',
    output.substring(tailStart < 0 ? 0 : tailStart),
    if (commandLogPath != null) 'Full log: $commandLogPath',
  ].join('\n');
}
