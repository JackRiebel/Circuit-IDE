import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils/logger.dart';

class IndexedFile {
  final String relativePath;
  final String fileName;
  final String extension;
  final bool isDirectory;
  final Set<String> contentTerms;

  const IndexedFile({
    required this.relativePath,
    required this.fileName,
    required this.extension,
    required this.isDirectory,
    this.contentTerms = const {},
  });
}

class FileIndexer {
  final String workingDir;
  final List<IndexedFile> _files = [];
  bool _isIndexing = false;
  DateTime? _lastIndexTime;

  static const _ignoreDirs = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    '__pycache__',
    '.venv',
    'venv',
    '.idea',
    '.vscode',
    'target',
    '.gradle',
    '.cache',
    'dist',
    '.next',
    '.nuxt',
    'coverage',
  };

  static const _allowedHiddenDirs = {'.github'};

  static const _ignoreExtensions = {
    '.lock',
    '.log',
    '.cache',
    '.pyc',
    '.class',
    '.o',
    '.obj',
    '.exe',
    '.dll',
    '.so',
    '.dylib',
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.ico',
    '.svg',
    '.woff',
    '.woff2',
    '.ttf',
    '.eot',
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

    if (file.contentTerms.contains(query)) {
      return query.length >= 8 ? 70 : 18;
    }

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

        // Skip hidden files and ignored directories. `.github` is retained
        // because CI/workflow files are high-value project context.
        if (name.startsWith('.') &&
            name != '.gitignore' &&
            !(entity is Directory && _allowedHiddenDirs.contains(name))) {
          continue;
        }
        if (entity is Directory && _ignoreDirs.contains(name)) continue;

        final relativePath = prefix.isEmpty ? name : '$prefix/$name';
        final ext = p.extension(name).toLowerCase();

        if (entity is Directory) {
          _files.add(
            IndexedFile(
              relativePath: relativePath,
              fileName: name,
              extension: '',
              isDirectory: true,
            ),
          );
          await _indexDirectory(entity, relativePath);
        } else if (!_ignoreExtensions.contains(ext)) {
          _files.add(
            IndexedFile(
              relativePath: relativePath,
              fileName: name,
              extension: ext,
              isDirectory: false,
              contentTerms: await _extractContentTerms(File(entity.path), ext),
            ),
          );
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

  Future<Set<String>> _extractContentTerms(File file, String extension) async {
    if (!_contentIndexedExtensions.contains(extension)) return const {};
    try {
      if (await file.length() > 80 * 1024) return const {};
      final content = await file.readAsString();
      final terms = <String>{};
      for (final match in RegExp(
        r'[A-Za-z_][A-Za-z0-9_]{2,}',
      ).allMatches(content)) {
        final raw = match.group(0)!;
        void add(String value) {
          final term = value.toLowerCase();
          if (term.length < 3) return;
          terms.add(term);
        }

        add(raw);
        for (final part
            in raw
                .replaceAllMapped(
                  RegExp(r'([a-z0-9])([A-Z])'),
                  (match) => '${match.group(1)} ${match.group(2)}',
                )
                .split(RegExp(r'\s+'))) {
          add(part);
        }
        if (terms.length >= 160) break;
      }
      return terms;
    } catch (_) {
      return const {};
    }
  }

  static const _contentIndexedExtensions = {
    '.dart',
    '.js',
    '.jsx',
    '.ts',
    '.tsx',
    '.py',
    '.md',
    '.json',
    '.yaml',
    '.yml',
    '.html',
    '.css',
    '.scss',
    '.go',
    '.rs',
    '.java',
    '.kt',
    '.swift',
    '.sh',
    '.toml',
    '.tf',
    '.hcl',
    '.sql',
    '.txt',
  };
}
