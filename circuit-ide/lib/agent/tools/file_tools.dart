import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/utils/file_utils.dart';

class FileTools {
  final String workingDir;

  FileTools({required this.workingDir});

  String _safePath(String path) {
    return FileUtils.safePath(workingDir, path);
  }

  Future<String> readFile(Map<String, dynamic> args) async {
    final path = _safePath(args['path'] as String);
    final startLine = args['start_line'] as int?;
    final endLine = args['end_line'] as int?;

    final file = File(path);
    if (!await file.exists()) {
      return 'Error: File not found: ${args['path']}';
    }

    if (FileUtils.isBinaryFile(path)) {
      return 'Error: Cannot read binary file: ${args['path']}';
    }

    final lines = await file.readAsLines();
    final total = lines.length;

    int start = (startLine ?? 1) - 1;
    int end = endLine ?? (start + AppConstants.maxFileReadLines);
    start = start.clamp(0, total);
    end = end.clamp(start, total);

    final selectedLines = lines.sublist(start, end);
    final numbered = <String>[];
    for (int i = 0; i < selectedLines.length; i++) {
      numbered.add('${start + i + 1} | ${selectedLines[i]}');
    }

    final result = numbered.join('\n');

    if (end < total) {
      return '$result\n\n... (${total - end} more lines, $total total)';
    }
    return result;
  }

  Future<String> writeFile(Map<String, dynamic> args) async {
    final path = _safePath(args['path'] as String);
    final content = args['content'] as String;

    final file = File(path);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await file.writeAsString(content);
    final lines = content.split('\n').length;
    return 'Successfully wrote $lines lines to ${args['path']}';
  }

  Future<String> editFile(Map<String, dynamic> args) async {
    final path = _safePath(args['path'] as String);
    final oldText = args['old_text'] as String;
    final newText = args['new_text'] as String;

    final file = File(path);
    if (!await file.exists()) {
      return 'Error: File not found: ${args['path']}';
    }

    final content = await file.readAsString();
    final occurrences = RegExp(
      RegExp.escape(oldText),
    ).allMatches(content).length;

    if (occurrences == 0) {
      // Find similar text for better error messages
      final preview = oldText.length > 50
          ? '${oldText.substring(0, 50)}...'
          : oldText;
      return 'Error: Text not found in ${args['path']}: "$preview"';
    }

    if (occurrences > 1) {
      return 'Error: Found $occurrences matches in ${args['path']}. '
          'Please provide more specific text to match exactly one location.';
    }

    final newContent = content.replaceFirst(oldText, newText);
    await file.writeAsString(newContent);
    return 'Successfully edited ${args['path']}';
  }

  Future<String> listFiles(Map<String, dynamic> args) async {
    final pattern = args['pattern'] as String? ?? '**';
    final baseDir = Directory(workingDir);

    if (!await baseDir.exists()) {
      return 'Error: Working directory not found';
    }

    final files = <String>[];
    final regExp = _globToRegExp(pattern);

    await for (final entity in baseDir.list(recursive: true)) {
      if (files.length >= AppConstants.maxListFiles) break;

      final relativePath = p.relative(entity.path, from: workingDir);

      // Skip hidden files and common ignore patterns
      if (_shouldIgnore(relativePath)) continue;

      if (regExp.hasMatch(relativePath)) {
        final type = entity is Directory ? 'd' : 'f';
        files.add('[$type] $relativePath');
      }
    }

    if (files.isEmpty) {
      return 'No files found matching "$pattern"';
    }

    files.sort();
    final result = files.join('\n');
    if (files.length >= AppConstants.maxListFiles) {
      return '$result\n\n(showing first ${AppConstants.maxListFiles} results)';
    }
    return result;
  }

  Future<String> searchFiles(Map<String, dynamic> args) async {
    final pattern = args['pattern'] as String;
    final searchPath = args['path'] as String?;
    final caseSensitive = args['case_sensitive'] as bool? ?? true;

    final baseDir = Directory(
      searchPath != null ? _safePath(searchPath) : workingDir,
    );

    if (!await baseDir.exists()) {
      return 'Error: Directory not found';
    }

    final regex = RegExp(pattern, caseSensitive: caseSensitive);
    final results = <String>[];

    await for (final entity in baseDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (results.length >= AppConstants.maxSearchResults) break;

      final relativePath = p.relative(entity.path, from: workingDir);
      if (_shouldIgnore(relativePath)) continue;
      if (FileUtils.isBinaryFile(entity.path)) continue;

      try {
        final lines = await entity.readAsLines();
        for (int i = 0; i < lines.length; i++) {
          if (regex.hasMatch(lines[i])) {
            results.add('$relativePath:${i + 1}: ${lines[i].trimRight()}');
            if (results.length >= AppConstants.maxSearchResults) break;
          }
        }
      } catch (_) {
        // Skip unreadable files
      }
    }

    if (results.isEmpty) {
      return 'No matches found for "$pattern"';
    }

    final result = results.join('\n');
    if (results.length >= AppConstants.maxSearchResults) {
      return '$result\n\n(showing first ${AppConstants.maxSearchResults} matches)';
    }
    return result;
  }

  bool _shouldIgnore(String path) {
    final parts = path.split(p.separator);
    for (final part in parts) {
      if (part.startsWith('.') && part != '.') return true;
      if (_ignoreDirs.contains(part)) return true;
    }
    return false;
  }

  static const _ignoreDirs = {
    'node_modules',
    '__pycache__',
    '.git',
    '.dart_tool',
    'build',
    'dist',
    '.venv',
    'venv',
    '.idea',
    '.vscode',
    'target',
  };

  RegExp _globToRegExp(String glob) {
    var pattern = glob
        .replaceAll('.', r'\.')
        .replaceAll('**/', '.*')
        .replaceAll('**', '.*')
        .replaceAll('*', '[^/]*')
        .replaceAll('?', '[^/]');
    return RegExp('^$pattern\$');
  }
}
