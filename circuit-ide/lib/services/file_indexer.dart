import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils/logger.dart';

class IndexedFile {
  final String relativePath;
  final String fileName;
  final String extension;
  final bool isDirectory;

  const IndexedFile({
    required this.relativePath,
    required this.fileName,
    required this.extension,
    required this.isDirectory,
  });
}

class FileIndexer {
  final String workingDir;
  final List<IndexedFile> _files = [];
  bool _isIndexing = false;
  DateTime? _lastIndexTime;

  static const _ignoreDirs = {
    '.git', '.dart_tool', 'build', 'node_modules', '__pycache__',
    '.venv', 'venv', '.idea', '.vscode', 'target', '.gradle',
    '.cache', 'dist', '.next', '.nuxt', 'coverage',
  };

  static const _ignoreExtensions = {
    '.lock', '.log', '.cache', '.pyc', '.class', '.o', '.obj',
    '.exe', '.dll', '.so', '.dylib', '.png', '.jpg', '.jpeg',
    '.gif', '.ico', '.svg', '.woff', '.woff2', '.ttf', '.eot',
  };

  FileIndexer({required this.workingDir});

  List<IndexedFile> get files => List.unmodifiable(_files);
  bool get isIndexing => _isIndexing;

  /// Search files matching a query (fuzzy path match).
  List<IndexedFile> search(String query, {int limit = 20}) {
    if (query.isEmpty) return _files.take(limit).toList();

    final lower = query.toLowerCase();
    final scored = <(IndexedFile, double)>[];

    for (final file in _files) {
      final score = _fuzzyScore(file, lower);
      if (score > 0) {
        scored.add((file, score));
      }
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }

  double _fuzzyScore(IndexedFile file, String query) {
    final fileName = file.fileName.toLowerCase();
    final path = file.relativePath.toLowerCase();

    // Exact filename match
    if (fileName == query) return 100;

    // Filename starts with query
    if (fileName.startsWith(query)) return 80;

    // Filename contains query
    if (fileName.contains(query)) return 60;

    // Path contains query
    if (path.contains(query)) return 40;

    // Fuzzy character match in filename
    int matchedChars = 0;
    int queryIdx = 0;
    for (int i = 0; i < fileName.length && queryIdx < query.length; i++) {
      if (fileName[i] == query[queryIdx]) {
        matchedChars++;
        queryIdx++;
      }
    }
    if (queryIdx == query.length) {
      return 20 * (matchedChars / fileName.length);
    }

    return 0;
  }

  /// Index all files in the working directory.
  Future<void> index() async {
    if (_isIndexing) return;
    _isIndexing = true;

    try {
      _files.clear();
      final dir = Directory(workingDir);
      if (!await dir.exists()) return;

      await _indexDirectory(dir, '');
      _lastIndexTime = DateTime.now();

      Logger.info(
        'Indexed ${_files.length} files in $workingDir',
        'FileIndexer',
      );
    } catch (e) {
      Logger.error('Indexing failed', e);
    } finally {
      _isIndexing = false;
    }
  }

  Future<void> _indexDirectory(Directory dir, String prefix) async {
    try {
      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);

        // Skip hidden files and ignored directories
        if (name.startsWith('.') && name != '.gitignore') continue;
        if (entity is Directory && _ignoreDirs.contains(name)) continue;

        final relativePath =
            prefix.isEmpty ? name : '$prefix/$name';
        final ext = p.extension(name).toLowerCase();

        if (entity is Directory) {
          _files.add(IndexedFile(
            relativePath: relativePath,
            fileName: name,
            extension: '',
            isDirectory: true,
          ));
          await _indexDirectory(entity, relativePath);
        } else if (!_ignoreExtensions.contains(ext)) {
          _files.add(IndexedFile(
            relativePath: relativePath,
            fileName: name,
            extension: ext,
            isDirectory: false,
          ));
        }
      }
    } catch (e) {
      // Skip directories we can't read
    }
  }

  /// Re-index if stale (older than 30 seconds).
  Future<void> refreshIfStale() async {
    if (_lastIndexTime == null ||
        DateTime.now().difference(_lastIndexTime!).inSeconds > 30) {
      await index();
    }
  }
}
