import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/search_result.dart';
import '../state/file_tree_provider.dart';

class SearchNotifier extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }

    state = state.copyWith(
      query: query,
      isSearching: true,
      results: [],
      totalMatches: 0,
      filesSearched: 0,
    );

    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) {
      state = state.copyWith(isSearching: false);
      return;
    }

    final results = <SearchResult>[];
    int filesSearched = 0;
    final pattern = state.isRegex
        ? RegExp(query, caseSensitive: state.caseSensitive)
        : RegExp(
            RegExp.escape(query),
            caseSensitive: state.caseSensitive,
          );

    try {
      await for (final entity in Directory(rootPath).list(recursive: true)) {
        if (entity is! File) continue;

        final relativePath = p.relative(entity.path, from: rootPath);
        final parts = relativePath.split(p.separator);
        if (parts.any((part) =>
            part.startsWith('.') ||
            _ignoredDirs.contains(part))) {
          continue;
        }

        if (_isBinary(entity.path)) continue;

        filesSearched++;
        try {
          final lines = await entity.readAsLines();
          for (int i = 0; i < lines.length; i++) {
            final matches = pattern.allMatches(lines[i]);
            for (final match in matches) {
              results.add(SearchResult(
                filePath: entity.path,
                fileName: p.basename(entity.path),
                lineNumber: i + 1,
                lineContent: lines[i],
                matchStart: match.start,
                matchEnd: match.end,
              ));
              if (results.length >= 500) break;
            }
            if (results.length >= 500) break;
          }
        } catch (_) {}
        if (results.length >= 500) break;
      }
    } catch (_) {}

    state = state.copyWith(
      results: results,
      isSearching: false,
      totalMatches: results.length,
      filesSearched: filesSearched,
    );
  }

  void setRegex(bool value) {
    state = state.copyWith(isRegex: value);
  }

  void setCaseSensitive(bool value) {
    state = state.copyWith(caseSensitive: value);
  }

  void setWholeWord(bool value) {
    state = state.copyWith(wholeWord: value);
  }

  void clear() {
    state = const SearchState();
  }

  static const _ignoredDirs = {
    'node_modules', '__pycache__', '.git', '.dart_tool',
    'build', 'dist', '.venv', 'venv', '.idea', '.vscode',
  };

  bool _isBinary(String path) {
    final ext = p.extension(path).toLowerCase();
    return {
      '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico',
      '.zip', '.tar', '.gz', '.exe', '.dll', '.so',
      '.pdf', '.doc', '.docx', '.class', '.pyc',
      '.woff', '.woff2', '.ttf', '.otf',
    }.contains(ext);
  }
}

final searchProvider =
    NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);
