import 'dart:io';

import '../core/utils/logger.dart';
import '../ui/editor/error_lens.dart';

class LinterService {
  /// Run linter on a file and return errors
  Future<List<ErrorInfo>> lint(String filePath) async {
    final ext = filePath.split('.').last.toLowerCase();

    try {
      return switch (ext) {
        'py' => _runPythonLint(filePath),
        'js' || 'jsx' || 'ts' || 'tsx' => _runESLint(filePath),
        'dart' => _runDartAnalyze(filePath),
        _ => Future.value([]),
      };
    } catch (e) {
      Logger.error('Linter error', e);
      return [];
    }
  }

  Future<List<ErrorInfo>> _runPythonLint(String filePath) async {
    try {
      final result = await Process.run('ruff', [
        'check',
        '--output-format=json',
        filePath,
      ]);
      // Parse ruff JSON output
      return _parseRuffOutput(result.stdout as String);
    } catch (_) {
      // ruff not installed, try flake8
      try {
        final result = await Process.run('flake8', [filePath]);
        return _parseFlake8Output(result.stdout as String);
      } catch (_) {
        return [];
      }
    }
  }

  Future<List<ErrorInfo>> _runESLint(String filePath) async {
    try {
      final result = await Process.run('npx', [
        'eslint',
        '--format=json',
        filePath,
      ]);
      return _parseESLintOutput(result.stdout as String);
    } catch (_) {
      return [];
    }
  }

  Future<List<ErrorInfo>> _runDartAnalyze(String filePath) async {
    try {
      final result = await Process.run('dart', [
        'analyze',
        '--format=machine',
        filePath,
      ]);
      return _parseDartAnalyzeOutput(result.stdout as String);
    } catch (_) {
      return [];
    }
  }

  List<ErrorInfo> _parseRuffOutput(String output) {
    // Simplified parser
    return [];
  }

  List<ErrorInfo> _parseFlake8Output(String output) {
    final errors = <ErrorInfo>[];
    for (final line in output.split('\n')) {
      final match = RegExp(r':(\d+):\d+:\s+(\w+)\s+(.+)').firstMatch(line);
      if (match != null) {
        final lineNum = int.tryParse(match.group(1)!) ?? 0;
        final code = match.group(2) ?? '';
        final message = match.group(3) ?? '';
        errors.add(
          ErrorInfo(
            line: lineNum,
            message: '$code: $message',
            severity: code.startsWith('E')
                ? ErrorSeverity.error
                : ErrorSeverity.warning,
          ),
        );
      }
    }
    return errors;
  }

  List<ErrorInfo> _parseESLintOutput(String output) {
    return [];
  }

  List<ErrorInfo> _parseDartAnalyzeOutput(String output) {
    final errors = <ErrorInfo>[];
    for (final line in output.split('\n')) {
      final parts = line.split('|');
      if (parts.length >= 4) {
        final severity = parts[0].trim().toLowerCase();
        final lineNum = int.tryParse(parts[2].trim()) ?? 0;
        final message = parts[3].trim();
        errors.add(
          ErrorInfo(
            line: lineNum,
            message: message,
            severity: severity == 'error'
                ? ErrorSeverity.error
                : severity == 'warning'
                ? ErrorSeverity.warning
                : ErrorSeverity.info,
          ),
        );
      }
    }
    return errors;
  }
}
