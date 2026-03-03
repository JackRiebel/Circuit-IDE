import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../core/utils/platform_utils.dart';

class Memory {
  final String name;
  final String content;
  final String filePath;
  final bool isGlobal;
  final DateTime modified;

  const Memory({
    required this.name,
    required this.content,
    required this.filePath,
    required this.isGlobal,
    required this.modified,
  });
}

class MemoriesLoader {
  /// Load project memories from `.circuit/memories/` in the given directory.
  static Future<List<Memory>> loadMemories(String workingDir) async {
    final memoriesDir =
        Directory(p.join(workingDir, '.circuit', 'memories'));
    return _loadFromDir(memoriesDir, isGlobal: false);
  }

  /// Load global memories from `~/.config/circuit-ide/memories/`.
  static Future<List<Memory>> loadGlobalMemories() async {
    final memoriesDir =
        Directory(p.join(PlatformUtils.configDir, 'memories'));
    return _loadFromDir(memoriesDir, isGlobal: true);
  }

  static Future<List<Memory>> _loadFromDir(
    Directory dir, {
    required bool isGlobal,
  }) async {
    if (!await dir.exists()) return [];

    final memories = <Memory>[];

    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.md')) continue;

        try {
          final content = await entity.readAsString();
          if (content.trim().isNotEmpty) {
            final stat = await entity.stat();
            memories.add(Memory(
              name: name.replaceAll('.md', ''),
              content: content.trim(),
              filePath: entity.path,
              isGlobal: isGlobal,
              modified: stat.modified,
            ));
          }
        } catch (e) {
          Logger.warning('Could not read memory file $name: $e', 'Memories');
        }
      }
    } catch (e) {
      Logger.warning('Could not list memories directory: $e', 'Memories');
    }

    memories.sort((a, b) => b.modified.compareTo(a.modified));
    return memories;
  }

  /// Save a memory file. If [global] is true, saves to global config dir.
  static Future<void> saveMemory(
    String workingDir,
    String name,
    String content, {
    bool global = false,
  }) async {
    final dir = global
        ? Directory(p.join(PlatformUtils.configDir, 'memories'))
        : Directory(p.join(workingDir, '.circuit', 'memories'));

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File(p.join(dir.path, '$name.md'));
    await file.writeAsString(content);
  }

  /// Delete a memory file by its full path.
  static Future<void> deleteMemory(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Format memories into a system prompt section.
  static String formatMemoriesPrompt(List<Memory> memories) {
    if (memories.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('\n\n## AI Memories\n');
    buffer.writeln(
        'The following are learned preferences and patterns from previous sessions. '
        'Use these to inform your responses:\n');

    for (final memory in memories) {
      final scope = memory.isGlobal ? 'global' : 'project';
      buffer.writeln('### ${memory.name} [$scope]\n');
      buffer.writeln(memory.content);
      buffer.writeln();
    }

    return buffer.toString();
  }
}
