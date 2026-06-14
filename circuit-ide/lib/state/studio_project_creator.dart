import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils/platform_utils.dart';

class StudioProjectCreator {
  static Future<String> createProject({
    required String name,
    String? parentPath,
  }) async {
    final safeName = sanitizeProjectName(name);
    final parent = parentPath?.trim().isNotEmpty == true
        ? parentPath!.trim()
        : PlatformUtils.defaultProjectsDir;
    final parentDir = Directory(parent);
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }
    final projectDir = Directory(_uniquePath(parent, safeName));
    await projectDir.create(recursive: true);
    return projectDir.path;
  }

  static String sanitizeProjectName(String input) {
    final normalized = input
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final trimmed = normalized.replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    if (trimmed.isEmpty) return 'Circuit-project';
    return trimmed.length <= 64 ? trimmed : trimmed.substring(0, 64);
  }

  static String projectNameFromPrompt(String prompt) {
    final words = prompt
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 1)
        .take(8)
        .join(' ');
    return sanitizeProjectName(words.isEmpty ? 'Circuit project' : words);
  }

  static String _uniquePath(String parent, String safeName) {
    var candidate = p.join(parent, safeName);
    var index = 2;
    while (Directory(candidate).existsSync() || File(candidate).existsSync()) {
      candidate = p.join(parent, '$safeName-$index');
      index += 1;
    }
    return candidate;
  }
}
