import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../core/utils/platform_utils.dart';

enum MemoryProvenance { userAuthored, learned }

class Memory {
  final String name;
  final String content;
  final String filePath;
  final bool isGlobal;
  final DateTime modified;
  final MemoryProvenance provenance;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  const Memory({
    required this.name,
    required this.content,
    required this.filePath,
    required this.isGlobal,
    required this.modified,
    this.provenance = MemoryProvenance.userAuthored,
    required this.createdAt,
    this.lastUsedAt,
  });

  Memory copyWith({DateTime? lastUsedAt}) {
    return Memory(
      name: name,
      content: content,
      filePath: filePath,
      isGlobal: isGlobal,
      modified: modified,
      provenance: provenance,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  String get provenanceLabel => switch (provenance) {
    MemoryProvenance.userAuthored => 'user-authored',
    MemoryProvenance.learned => 'reviewed learned',
  };
}

class MemoriesLoader {
  /// Load project memories from `.circuit/memories/` in the given directory.
  static Future<List<Memory>> loadMemories(String workingDir) async {
    final memoriesDir = Directory(p.join(workingDir, '.circuit', 'memories'));
    return _loadFromDir(memoriesDir, isGlobal: false);
  }

  /// Load global memories from `~/.config/circuit-ide/memories/`.
  static Future<List<Memory>> loadGlobalMemories() async {
    final memoriesDir = Directory(p.join(PlatformUtils.configDir, 'memories'));
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
          final document = _parseDocument(await entity.readAsString());
          if (document.content.trim().isNotEmpty) {
            final stat = await entity.stat();
            memories.add(
              Memory(
                name: name.replaceAll('.md', ''),
                content: document.content.trim(),
                filePath: entity.path,
                isGlobal: isGlobal,
                modified: stat.modified,
                provenance: document.provenance,
                createdAt: document.createdAt ?? stat.modified,
                lastUsedAt: document.lastUsedAt,
              ),
            );
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
    MemoryProvenance provenance = MemoryProvenance.userAuthored,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  }) async {
    final dir = global
        ? Directory(p.join(PlatformUtils.configDir, 'memories'))
        : Directory(p.join(workingDir, '.circuit', 'memories'));

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File(p.join(dir.path, '$name.md'));
    await file.writeAsString(
      _encodeDocument(
        content: content,
        provenance: provenance,
        createdAt: createdAt ?? DateTime.now().toUtc(),
        lastUsedAt: lastUsedAt,
      ),
    );
  }

  /// Records that a memory was included in a model-facing context pack.
  /// This preserves the original source and never promotes a note's scope.
  static Future<void> markUsed(Memory memory, {DateTime? at}) async {
    final file = File(memory.filePath);
    if (!await file.exists()) return;
    final usedAt = (at ?? DateTime.now()).toUtc();
    await file.writeAsString(
      _encodeDocument(
        content: memory.content,
        provenance: memory.provenance,
        createdAt: memory.createdAt,
        lastUsedAt: usedAt,
      ),
    );
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
      'Use these to inform your responses:\n',
    );

    for (final memory in memories) {
      final scope = memory.isGlobal ? 'global' : 'project';
      buffer.writeln('### ${memory.name} [$scope]\n');
      buffer.writeln(memory.content);
      buffer.writeln();
    }

    return buffer.toString();
  }

  static _MemoryDocument _parseDocument(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('---')) {
      return _MemoryDocument(content: raw);
    }
    final lines = raw.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') {
      return _MemoryDocument(content: raw);
    }
    var closingIndex = -1;
    for (var index = 1; index < lines.length; index++) {
      if (lines[index].trim() == '---') {
        closingIndex = index;
        break;
      }
    }
    if (closingIndex < 0) return _MemoryDocument(content: raw);
    final metadata = <String, String>{};
    for (final line in lines.sublist(1, closingIndex)) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      metadata[line.substring(0, separator).trim().toLowerCase()] = line
          .substring(separator + 1)
          .trim();
    }
    final provenance = metadata['provenance'] == 'learned'
        ? MemoryProvenance.learned
        : MemoryProvenance.userAuthored;
    return _MemoryDocument(
      content: lines.sublist(closingIndex + 1).join('\n'),
      provenance: provenance,
      createdAt: DateTime.tryParse(metadata['created-at'] ?? '')?.toUtc(),
      lastUsedAt: DateTime.tryParse(metadata['last-used-at'] ?? '')?.toUtc(),
    );
  }

  static String _encodeDocument({
    required String content,
    required MemoryProvenance provenance,
    required DateTime createdAt,
    DateTime? lastUsedAt,
  }) {
    return [
      '---',
      'kind: circuit-memory',
      'provenance: ${provenance == MemoryProvenance.learned ? 'learned' : 'user-authored'}',
      'created-at: ${createdAt.toUtc().toIso8601String()}',
      if (lastUsedAt != null)
        'last-used-at: ${lastUsedAt.toUtc().toIso8601String()}',
      '---',
      content.trim(),
      '',
    ].join('\n');
  }
}

class _MemoryDocument {
  final String content;
  final MemoryProvenance provenance;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  const _MemoryDocument({
    required this.content,
    this.provenance = MemoryProvenance.userAuthored,
    this.createdAt,
    this.lastUsedAt,
  });
}
