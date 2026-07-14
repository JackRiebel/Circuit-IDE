import 'dart:io';

import 'package:path/path.dart' as p;

/// Represents a single parsed import from a source file.
class ParsedImport {
  final String sourceFile;
  final String targetPath;
  final String rawStatement;
  final bool isRelative;

  const ParsedImport({
    required this.sourceFile,
    required this.targetPath,
    required this.rawStatement,
    this.isRelative = true,
  });
}

/// Multi-language import parser using regex-based extraction.
/// Supports Dart, Python, JS/TS, Go, and Rust.
class ImportParser {
  final String rootPath;

  ImportParser({required this.rootPath});

  /// Parse all imports from the given file.
  List<ParsedImport> parseFile(String filePath, String content) {
    final ext = p.extension(filePath).toLowerCase();
    return switch (ext) {
      '.dart' => _parseDart(filePath, content),
      '.py' => _parsePython(filePath, content),
      '.js' || '.jsx' || '.mjs' => _parseJavaScript(filePath, content),
      '.ts' || '.tsx' || '.mts' => _parseTypeScript(filePath, content),
      '.go' => _parseGo(filePath, content),
      '.rs' => _parseRust(filePath, content),
      _ => [],
    };
  }

  // ── Dart ─────────────────────────────────────────────────────────────

  static final _dartImportRe = RegExp(
    r'''(?:import|export)\s+['"](.*?)['"]''',
    multiLine: true,
  );

  List<ParsedImport> _parseDart(String filePath, String content) {
    final results = <ParsedImport>[];
    for (final match in _dartImportRe.allMatches(content)) {
      final raw = match.group(0)!;
      final target = match.group(1)!;

      if (target.startsWith('dart:') || target.startsWith('package:')) {
        // External / SDK import
        results.add(
          ParsedImport(
            sourceFile: filePath,
            targetPath: target,
            rawStatement: raw,
            isRelative: false,
          ),
        );
      } else {
        // Relative import — resolve against source directory
        final resolved = _resolveRelative(filePath, target);
        results.add(
          ParsedImport(
            sourceFile: filePath,
            targetPath: resolved ?? target,
            rawStatement: raw,
            isRelative: true,
          ),
        );
      }
    }
    return results;
  }

  // ── Python ───────────────────────────────────────────────────────────

  static final _pythonFromImportRe = RegExp(
    r'^from\s+([\w.]+)\s+import',
    multiLine: true,
  );
  static final _pythonImportRe = RegExp(r'^import\s+([\w.]+)', multiLine: true);

  List<ParsedImport> _parsePython(String filePath, String content) {
    final results = <ParsedImport>[];

    for (final match in _pythonFromImportRe.allMatches(content)) {
      final raw = match.group(0)!;
      final module = match.group(1)!;
      final isRelative = module.startsWith('.');
      final resolved = isRelative
          ? _resolvePythonRelative(filePath, module)
          : module;
      results.add(
        ParsedImport(
          sourceFile: filePath,
          targetPath: resolved,
          rawStatement: raw,
          isRelative: isRelative,
        ),
      );
    }

    for (final match in _pythonImportRe.allMatches(content)) {
      final raw = match.group(0)!;
      final module = match.group(1)!;
      results.add(
        ParsedImport(
          sourceFile: filePath,
          targetPath: module,
          rawStatement: raw,
          isRelative: false,
        ),
      );
    }

    return results;
  }

  String _resolvePythonRelative(String filePath, String module) {
    final sourceDir = p.dirname(filePath);
    // Count leading dots
    int dots = 0;
    for (final ch in module.codeUnits) {
      if (ch == '.'.codeUnitAt(0)) {
        dots++;
      } else {
        break;
      }
    }
    // Go up (dots - 1) levels from source dir
    var base = sourceDir;
    for (int i = 1; i < dots; i++) {
      base = p.dirname(base);
    }
    final rest = module.substring(dots).replaceAll('.', '/');
    if (rest.isEmpty) return base;
    return p.join(base, '$rest.py');
  }

  // ── JavaScript ───────────────────────────────────────────────────────

  static final _jsImportRe = RegExp(
    r'''import\s+.*?\s+from\s+['"](.*?)['"]''',
    multiLine: true,
  );
  static final _jsRequireRe = RegExp(
    r'''require\s*\(\s*['"](.*?)['"]\s*\)''',
    multiLine: true,
  );
  static final _jsDynamicImportRe = RegExp(
    r'''import\s*\(\s*['"](.*?)['"]\s*\)''',
    multiLine: true,
  );

  List<ParsedImport> _parseJavaScript(String filePath, String content) {
    return _parseJsTs(filePath, content);
  }

  List<ParsedImport> _parseTypeScript(String filePath, String content) {
    return _parseJsTs(filePath, content);
  }

  List<ParsedImport> _parseJsTs(String filePath, String content) {
    final results = <ParsedImport>[];
    final patterns = [_jsImportRe, _jsRequireRe, _jsDynamicImportRe];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(content)) {
        final raw = match.group(0)!;
        final target = match.group(1)!;
        final isRelative = target.startsWith('.') || target.startsWith('/');

        if (isRelative) {
          final resolved = _resolveJsRelative(filePath, target);
          results.add(
            ParsedImport(
              sourceFile: filePath,
              targetPath: resolved ?? target,
              rawStatement: raw,
              isRelative: true,
            ),
          );
        } else {
          results.add(
            ParsedImport(
              sourceFile: filePath,
              targetPath: target,
              rawStatement: raw,
              isRelative: false,
            ),
          );
        }
      }
    }
    return results;
  }

  String? _resolveJsRelative(String filePath, String target) {
    final sourceDir = p.dirname(filePath);
    final base = p.normalize(p.join(sourceDir, target));

    // Try exact path first
    if (File(base).existsSync()) return base;

    // Try common JS/TS extensions
    const extensions = [
      '.js',
      '.jsx',
      '.ts',
      '.tsx',
      '.mjs',
      '/index.js',
      '/index.ts',
    ];
    for (final ext in extensions) {
      final candidate = '$base$ext';
      if (File(candidate).existsSync()) return candidate;
    }

    return base;
  }

  // ── Go ───────────────────────────────────────────────────────────────

  static final _goImportSingleRe = RegExp(
    r'''import\s+"(.*?)"''',
    multiLine: true,
  );
  static final _goImportBlockRe = RegExp(
    r'''import\s*\(([\s\S]*?)\)''',
    multiLine: true,
  );
  static final _goImportLineRe = RegExp(r'''"(.*?)"''');

  List<ParsedImport> _parseGo(String filePath, String content) {
    final results = <ParsedImport>[];

    // Single-line imports
    for (final match in _goImportSingleRe.allMatches(content)) {
      final raw = match.group(0)!;
      final target = match.group(1)!;
      results.add(
        ParsedImport(
          sourceFile: filePath,
          targetPath: target,
          rawStatement: raw,
          isRelative: target.startsWith('.'),
        ),
      );
    }

    // Block imports
    for (final blockMatch in _goImportBlockRe.allMatches(content)) {
      final block = blockMatch.group(1)!;
      for (final lineMatch in _goImportLineRe.allMatches(block)) {
        final target = lineMatch.group(1)!;
        results.add(
          ParsedImport(
            sourceFile: filePath,
            targetPath: target,
            rawStatement: 'import "$target"',
            isRelative: target.startsWith('.'),
          ),
        );
      }
    }

    return results;
  }

  // ── Rust ─────────────────────────────────────────────────────────────

  static final _rustUseRe = RegExp(r'^use\s+([\w:]+)', multiLine: true);
  static final _rustModRe = RegExp(r'^mod\s+(\w+)\s*;', multiLine: true);

  List<ParsedImport> _parseRust(String filePath, String content) {
    final results = <ParsedImport>[];

    for (final match in _rustUseRe.allMatches(content)) {
      final raw = match.group(0)!;
      final target = match.group(1)!;
      final isLocal =
          target.startsWith('crate::') || target.startsWith('super::');
      results.add(
        ParsedImport(
          sourceFile: filePath,
          targetPath: target,
          rawStatement: raw,
          isRelative: isLocal,
        ),
      );
    }

    for (final match in _rustModRe.allMatches(content)) {
      final raw = match.group(0)!;
      final modName = match.group(1)!;
      final sourceDir = p.dirname(filePath);
      // mod foo; → foo.rs or foo/mod.rs
      final candidate1 = p.join(sourceDir, '$modName.rs');
      final candidate2 = p.join(sourceDir, modName, 'mod.rs');
      final resolved = File(candidate1).existsSync() ? candidate1 : candidate2;
      results.add(
        ParsedImport(
          sourceFile: filePath,
          targetPath: resolved,
          rawStatement: raw,
          isRelative: true,
        ),
      );
    }

    return results;
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Resolve a relative path against the source file's directory.
  String? _resolveRelative(String sourceFile, String target) {
    final sourceDir = p.dirname(sourceFile);
    final resolved = p.normalize(p.join(sourceDir, target));
    if (File(resolved).existsSync()) return resolved;
    return resolved;
  }
}
