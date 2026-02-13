import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils/file_utils.dart';
import '../core/utils/logger.dart';
import '../models/semantic_search_models.dart';
import 'code_chunker.dart';

/// Callback for index build progress.
typedef IndexProgressCallback = void Function(int indexed, int total);

/// Builds, stores, queries, and persists a chunk-based semantic index
/// for a project directory.
class SemanticIndex {
  final _chunker = CodeChunker();
  final List<CodeChunk> _chunks = [];
  DateTime? _lastBuildTime;

  static const _ignoreDirs = {
    '.git', '.dart_tool', 'build', 'node_modules', '__pycache__',
    '.venv', 'venv', '.idea', '.vscode', 'target', '.gradle',
    '.cache', 'dist', '.next', '.nuxt', 'coverage',
  };

  static const _sourceExtensions = {
    '.dart', '.py', '.js', '.jsx', '.ts', '.tsx', '.java', '.kt',
    '.rs', '.go', '.c', '.cpp', '.h', '.hpp', '.cs', '.rb',
    '.swift', '.sh', '.bash', '.zsh', '.yaml', '.yml', '.json',
    '.toml', '.xml', '.html', '.css', '.scss', '.sql', '.md',
    '.r', '.lua', '.php', '.pl', '.scala', '.ex', '.exs',
  };

  int get chunkCount => _chunks.length;
  List<CodeChunk> get chunks => List.unmodifiable(_chunks);

  bool get isStale {
    if (_lastBuildTime == null) return true;
    return DateTime.now().difference(_lastBuildTime!).inMinutes > 10;
  }

  /// Walk project tree, chunk each source file, store in memory.
  Future<void> buildIndex(
    String rootPath, {
    IndexProgressCallback? onProgress,
  }) async {
    _chunks.clear();

    // Collect all source files first
    final sourceFiles = <File>[];
    await _collectSourceFiles(Directory(rootPath), sourceFiles);

    final total = sourceFiles.length;
    int indexed = 0;

    for (final file in sourceFiles) {
      try {
        final content = await file.readAsString();
        final language = FileUtils.getLanguageFromPath(file.path);
        final fileChunks = _chunker.chunkFile(file.path, content, language);
        _chunks.addAll(fileChunks);
      } catch (e) {
        // Skip files that can't be read (binary, permission errors, etc.)
      }

      indexed++;
      onProgress?.call(indexed, total);
    }

    _lastBuildTime = DateTime.now();
    Logger.info(
      'Built semantic index: $_chunks chunks from $indexed files',
      'SemanticIndex',
    );
  }

  /// Fast keyword pre-filter: tokenize query, score chunks by keyword
  /// overlap + name match + file path relevance.
  List<CodeChunk> getCandidates(String query, {int limit = 30}) {
    if (query.trim().isEmpty || _chunks.isEmpty) return [];

    final queryTokens = _tokenize(query.toLowerCase());
    if (queryTokens.isEmpty) return [];

    final scored = <(CodeChunk, double)>[];

    for (final chunk in _chunks) {
      final score = _scoreChunk(chunk, queryTokens, query.toLowerCase());
      if (score > 0) {
        scored.add((chunk, score));
      }
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }

  /// Incremental re-index: remove old chunks for changed files and re-chunk.
  Future<void> updateIndex(
    List<String> changedFiles,
    String rootPath,
  ) async {
    for (final filePath in changedFiles) {
      // Remove old chunks for this file
      _chunks.removeWhere((c) => c.filePath == filePath);

      // Re-chunk if file still exists
      final file = File(filePath);
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          final language = FileUtils.getLanguageFromPath(filePath);
          final newChunks = _chunker.chunkFile(filePath, content, language);
          _chunks.addAll(newChunks);
        } catch (_) {}
      }
    }

    _lastBuildTime = DateTime.now();
  }

  /// Save the index to disk as JSON.
  Future<void> saveIndex(String rootPath) async {
    try {
      final dir = await _getIndexDir();
      final file = File(p.join(dir.path, _indexFileName(rootPath)));
      final data = {
        'rootPath': rootPath,
        'buildTime': _lastBuildTime?.toIso8601String(),
        'chunks': _chunks.map((c) => c.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(data));
      Logger.info('Saved semantic index to ${file.path}', 'SemanticIndex');
    } catch (e) {
      Logger.error('Failed to save semantic index', e);
    }
  }

  /// Load a previously saved index from disk.
  Future<bool> loadIndex(String rootPath) async {
    try {
      final dir = await _getIndexDir();
      final file = File(p.join(dir.path, _indexFileName(rootPath)));
      if (!await file.exists()) return false;

      final data = jsonDecode(await file.readAsString());
      final chunkList = data['chunks'] as List<dynamic>? ?? [];

      _chunks.clear();
      for (final json in chunkList) {
        _chunks.add(CodeChunk.fromJson(json as Map<String, dynamic>));
      }

      final buildTimeStr = data['buildTime'] as String?;
      if (buildTimeStr != null) {
        _lastBuildTime = DateTime.tryParse(buildTimeStr);
      }

      Logger.info(
        'Loaded semantic index: ${_chunks.length} chunks',
        'SemanticIndex',
      );
      return true;
    } catch (e) {
      Logger.error('Failed to load semantic index', e);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _collectSourceFiles(
    Directory dir,
    List<File> files,
  ) async {
    try {
      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);

        // Skip hidden files and ignored directories
        if (name.startsWith('.') && name != '.gitignore') continue;
        if (entity is Directory && _ignoreDirs.contains(name)) continue;

        if (entity is Directory) {
          await _collectSourceFiles(entity, files);
        } else if (entity is File) {
          final ext = p.extension(name).toLowerCase();
          if (_sourceExtensions.contains(ext)) {
            // Skip very large files (> 500KB)
            final stat = await entity.stat();
            if (stat.size < 500 * 1024) {
              files.add(entity);
            }
          }
        }
      }
    } catch (_) {
      // Skip directories we can't read
    }
  }

  List<String> _tokenize(String text) {
    // Split on non-alphanumeric, camelCase boundaries, underscores
    final words = <String>[];
    // First split camelCase
    final camelSplit = text.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    // Then split on non-alphanumeric
    for (final word in camelSplit.split(RegExp(r'[^a-z0-9]+'))) {
      if (word.length >= 2) {
        words.add(word);
      }
    }
    return words.toSet().toList(); // deduplicate
  }

  double _scoreChunk(
    CodeChunk chunk,
    List<String> queryTokens,
    String queryLower,
  ) {
    double score = 0;

    final nameLower = chunk.name.toLowerCase();
    final contentLower = chunk.content.toLowerCase();
    final pathLower = chunk.filePath.toLowerCase();

    // Exact name match
    if (nameLower == queryLower) {
      score += 10;
    }
    // Name contains full query
    else if (nameLower.contains(queryLower)) {
      score += 7;
    }

    // Token-based scoring
    int nameHits = 0;
    int contentHits = 0;
    int pathHits = 0;

    for (final token in queryTokens) {
      if (nameLower.contains(token)) nameHits++;
      if (contentLower.contains(token)) contentHits++;
      if (pathLower.contains(token)) pathHits++;
    }

    if (queryTokens.isNotEmpty) {
      score += 5 * (nameHits / queryTokens.length);
      score += 3 * (contentHits / queryTokens.length);
      score += 1 * (pathHits / queryTokens.length);
    }

    // Bonus for functions/methods (usually more relevant than imports)
    if (chunk.type == ChunkType.function ||
        chunk.type == ChunkType.method) {
      score *= 1.2;
    }

    // Slight penalty for very large chunks (likely less focused)
    final lineCount = chunk.endLine - chunk.startLine + 1;
    if (lineCount > 100) {
      score *= 0.8;
    }

    return score;
  }

  Future<Directory> _getIndexDir() async {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final dir = Directory(p.join(home, '.config', 'circuit-ide', 'semantic-index'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _indexFileName(String rootPath) {
    // Hash the root path to create a stable file name
    final hash = rootPath.hashCode.toRadixString(16).padLeft(8, '0');
    return 'index_$hash.json';
  }
}
