import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/import_parser.dart';

class FileSignature {
  final String filePath;
  final String relativePath;
  final List<String> classNames;
  final List<String> functionSignatures;
  final List<String> exportedConstants;

  const FileSignature({
    required this.filePath,
    required this.relativePath,
    this.classNames = const [],
    this.functionSignatures = const [],
    this.exportedConstants = const [],
  });

  bool get isEmpty =>
      classNames.isEmpty &&
      functionSignatures.isEmpty &&
      exportedConstants.isEmpty;
}

class FlowContext {
  final String activeFile;
  final List<FileSignature> dependencies;
  final List<FileSignature> dependents;
  final int totalContextTokens;

  const FlowContext({
    required this.activeFile,
    this.dependencies = const [],
    this.dependents = const [],
    this.totalContextTokens = 0,
  });

  bool get isEmpty => dependencies.isEmpty && dependents.isEmpty;
}

class FlowAnalyzer {
  final String rootPath;
  late final ImportParser _parser;

  FlowAnalyzer({required this.rootPath}) {
    _parser = ImportParser(rootPath: rootPath);
  }

  /// Analyze the active file's dependency graph (1 level deep).
  Future<FlowContext> analyze(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return FlowContext(activeFile: filePath);
    }

    final content = await file.readAsString();
    final imports = _parser.parseFile(filePath, content);

    // Resolve direct dependencies (files this file imports)
    final dependencies = <FileSignature>[];
    for (final imp in imports) {
      if (!imp.isRelative) continue;
      final depFile = File(imp.targetPath);
      if (!await depFile.exists()) continue;

      try {
        final depContent = await depFile.readAsString();
        final sig = extractSignatures(imp.targetPath, depContent);
        if (!sig.isEmpty) {
          dependencies.add(sig);
        }
      } catch (_) {}
    }

    // Find dependents (files that import this file) — scan siblings
    final dependents = <FileSignature>[];
    final dir = Directory(p.dirname(filePath));
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (entity.path == filePath) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!_supportedExtensions.contains(ext)) continue;

        try {
          final sibContent = await entity.readAsString();
          final sibImports = _parser.parseFile(entity.path, sibContent);
          final importsThisFile = sibImports.any((imp) =>
              imp.isRelative &&
              p.normalize(imp.targetPath) == p.normalize(filePath));

          if (importsThisFile) {
            final sig = extractSignatures(entity.path, sibContent);
            if (!sig.isEmpty) {
              dependents.add(sig);
            }
          }
        } catch (_) {}
      }
    }

    final allSigs = [...dependencies, ...dependents];
    final tokenEstimate = allSigs.fold<int>(0, (sum, sig) {
      final chars = sig.classNames.join(', ').length +
          sig.functionSignatures.join('\n').length +
          sig.exportedConstants.join('\n').length;
      return sum + (chars / 4).ceil();
    });

    return FlowContext(
      activeFile: filePath,
      dependencies: dependencies,
      dependents: dependents,
      totalContextTokens: tokenEstimate,
    );
  }

  /// Extract class/function signatures from a file (no bodies).
  FileSignature extractSignatures(String filePath, String content) {
    final ext = p.extension(filePath).toLowerCase();
    final relativePath = p.relative(filePath, from: rootPath);

    final classNames = <String>[];
    final functionSigs = <String>[];
    final constants = <String>[];

    switch (ext) {
      case '.dart':
        _extractDartSignatures(content, classNames, functionSigs, constants);
      case '.py':
        _extractPythonSignatures(content, classNames, functionSigs, constants);
      case '.js' || '.jsx' || '.ts' || '.tsx' || '.mjs' || '.mts':
        _extractJsSignatures(content, classNames, functionSigs, constants);
      case '.go':
        _extractGoSignatures(content, classNames, functionSigs, constants);
    }

    return FileSignature(
      filePath: filePath,
      relativePath: relativePath,
      classNames: classNames,
      functionSignatures: functionSigs,
      exportedConstants: constants,
    );
  }

  // --- Language-specific extractors ---

  static final _dartClassRe = RegExp(
    r'(?:abstract\s+)?class\s+(\w+)(?:\s+extends\s+(\w+))?(?:\s+(?:with|implements)\s+[\w,\s]+)?',
  );
  static final _dartFuncRe = RegExp(
    r'^\s*(?:static\s+)?(?:Future<[\w<>?]+>|Stream<[\w<>?]+>|[\w<>?]+)\s+(\w+)\s*\([^)]*\)',
    multiLine: true,
  );
  static final _dartConstRe = RegExp(
    r'^\s*(?:static\s+)?(?:final|const)\s+(?:[\w<>?]+\s+)?(\w+)\s*=',
    multiLine: true,
  );

  void _extractDartSignatures(
    String content,
    List<String> classes,
    List<String> functions,
    List<String> constants,
  ) {
    for (final m in _dartClassRe.allMatches(content)) {
      final name = m.group(1)!;
      final parent = m.group(2);
      classes.add(parent != null ? '$name extends $parent' : name);
    }
    for (final m in _dartFuncRe.allMatches(content)) {
      final line = m.group(0)!.trim();
      if (!line.startsWith('//') && !line.startsWith('if') && !line.startsWith('return')) {
        functions.add(line);
      }
    }
    for (final m in _dartConstRe.allMatches(content)) {
      constants.add(m.group(1)!);
    }
  }

  static final _pyClassRe = RegExp(r'^class\s+(\w+)(?:\(([^)]*)\))?:', multiLine: true);
  static final _pyFuncRe = RegExp(r'^(?:async\s+)?def\s+(\w+)\s*\(([^)]*)\)', multiLine: true);

  void _extractPythonSignatures(
    String content,
    List<String> classes,
    List<String> functions,
    List<String> constants,
  ) {
    for (final m in _pyClassRe.allMatches(content)) {
      final name = m.group(1)!;
      final bases = m.group(2);
      classes.add(bases != null && bases.isNotEmpty ? '$name($bases)' : name);
    }
    for (final m in _pyFuncRe.allMatches(content)) {
      functions.add('def ${m.group(1)!}(${m.group(2)!})');
    }
  }

  static final _jsClassRe = RegExp(r'(?:export\s+)?class\s+(\w+)(?:\s+extends\s+(\w+))?');
  static final _jsFuncRe = RegExp(
    r'(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(([^)]*)\)',
  );
  static final _jsExportConstRe = RegExp(
    r'export\s+(?:const|let|var)\s+(\w+)',
  );

  void _extractJsSignatures(
    String content,
    List<String> classes,
    List<String> functions,
    List<String> constants,
  ) {
    for (final m in _jsClassRe.allMatches(content)) {
      final name = m.group(1)!;
      final parent = m.group(2);
      classes.add(parent != null ? '$name extends $parent' : name);
    }
    for (final m in _jsFuncRe.allMatches(content)) {
      functions.add('function ${m.group(1)!}(${m.group(2)!})');
    }
    for (final m in _jsExportConstRe.allMatches(content)) {
      constants.add(m.group(1)!);
    }
  }

  static final _goTypeRe = RegExp(r'type\s+(\w+)\s+(struct|interface)');
  static final _goFuncRe = RegExp(
    r'func\s+(?:\(\s*\w+\s+\*?(\w+)\s*\)\s+)?(\w+)\s*\(([^)]*)\)',
  );

  void _extractGoSignatures(
    String content,
    List<String> classes,
    List<String> functions,
    List<String> constants,
  ) {
    for (final m in _goTypeRe.allMatches(content)) {
      classes.add('${m.group(1)!} ${m.group(2)!}');
    }
    for (final m in _goFuncRe.allMatches(content)) {
      final receiver = m.group(1);
      final name = m.group(2)!;
      final params = m.group(3)!;
      if (receiver != null) {
        functions.add('($receiver) $name($params)');
      } else {
        functions.add('$name($params)');
      }
    }
  }

  static const _supportedExtensions = {
    '.dart', '.py', '.js', '.jsx', '.ts', '.tsx', '.mjs', '.mts', '.go',
  };
}
