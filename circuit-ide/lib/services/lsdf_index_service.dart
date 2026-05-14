import 'dart:io';

import 'package:path/path.dart' as p;

import '../agent/context/flow_analyzer.dart';
import '../core/utils/file_utils.dart';
import 'import_parser.dart';

class LsdfIndexService {
  static const version = '1.1-circuit';

  static const _sourceExtensions = {
    '.dart',
    '.py',
    '.js',
    '.jsx',
    '.ts',
    '.tsx',
    '.mjs',
    '.mts',
    '.go',
    '.rs',
  };

  static const _ignoredDirs = {
    '.git',
    '.dart_tool',
    '.idea',
    '.lsdf',
    '.pytest_cache',
    '.venv',
    'venv',
    '__pycache__',
    'build',
    'dist',
    'node_modules',
    'Pods',
    '.next',
    '.turbo',
  };

  final String rootPath;
  late final ImportParser _importParser;
  late final FlowAnalyzer _flowAnalyzer;

  LsdfIndexService({required this.rootPath}) {
    _importParser = ImportParser(rootPath: rootPath);
    _flowAnalyzer = FlowAnalyzer(rootPath: rootPath);
  }

  Future<void> generate({bool recursive = true}) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return;

    await _writeSupportFiles();
    await _writeProjectManifest(root);
    await _generateDirectory(root, recursive: recursive);
  }

  Future<void> refreshForPath(String changedPath) async {
    final file = File(_resolvePath(changedPath));
    var dir = file.parent;
    if (!await dir.exists()) return;

    final root = p.normalize(rootPath);
    while (p.isWithin(root, dir.path) || p.equals(root, dir.path)) {
      await _generateDirectory(dir, recursive: false);
      if (p.equals(root, dir.path)) break;
      dir = dir.parent;
    }
  }

  Future<LsdfPromptContext> loadPromptContext({int maxChars = 6000}) async {
    final parts = <String>[];

    Future<void> addFile(String label, String path) async {
      final file = File(path);
      if (!await file.exists()) return;
      final content = (await file.readAsString()).trim();
      if (content.isEmpty) return;
      parts.add('$label\n```lsdf\n$content\n```');
    }

    await addFile('project.lsdf', p.join(rootPath, 'project.lsdf'));
    await addFile('INDEX.lsdf', p.join(rootPath, 'INDEX.lsdf'));

    final combined = parts.join('\n\n');
    if (combined.length <= maxChars) {
      return LsdfPromptContext(content: combined, wasTruncated: false);
    }
    return LsdfPromptContext(
      content: '${combined.substring(0, maxChars)}\n... truncated ...',
      wasTruncated: true,
    );
  }

  Future<String> readIndex({
    String directory = '.',
    bool detail = false,
    bool includeProject = false,
  }) async {
    final resolved = FileUtils.safePath(rootPath, directory);
    final dir = FileSystemEntity.typeSync(resolved) == FileSystemEntityType.file
        ? Directory(p.dirname(resolved))
        : Directory(resolved);

    final parts = <String>[];
    if (includeProject) {
      await _appendFile(
        parts,
        'project.lsdf',
        p.join(rootPath, 'project.lsdf'),
      );
    }

    final fileName = detail ? 'INDEX.detail.lsdf' : 'INDEX.lsdf';
    final indexPath = await _nearestIndexPath(dir, fileName);
    if (indexPath != null) {
      final rel = p.relative(indexPath, from: rootPath);
      await _appendFile(parts, rel, indexPath);
    }

    if (parts.isEmpty) {
      final rel = p.relative(dir.path, from: rootPath);
      return 'No L-SDF index found for ${rel == "." ? "project root" : rel}.';
    }
    return parts.join('\n\n');
  }

  Future<void> _writeSupportFiles() async {
    final lsdfDir = Directory(p.join(rootPath, '.lsdf'));
    if (!await lsdfDir.exists()) {
      await lsdfDir.create(recursive: true);
    }

    final instructionsFile = File(p.join(lsdfDir.path, 'lsdf_instructions.md'));
    if (!await instructionsFile.exists()) {
      await instructionsFile.writeAsString(_instructions);
    }

    final ignoreFile = File(p.join(rootPath, '.lsdfignore'));
    if (!await ignoreFile.exists()) {
      await ignoreFile.writeAsString('${_ignoredDirs.join('\n')}\n');
    }
  }

  Future<void> _appendFile(
    List<String> parts,
    String label,
    String path,
  ) async {
    final file = File(path);
    if (!await file.exists()) return;
    final content = (await file.readAsString()).trim();
    if (content.isEmpty) return;
    parts.add('$label\n```lsdf\n$content\n```');
  }

  Future<String?> _nearestIndexPath(Directory start, String fileName) async {
    var dir = start;
    final root = p.normalize(rootPath);

    while (p.isWithin(root, dir.path) || p.equals(root, dir.path)) {
      final candidate = File(p.join(dir.path, fileName));
      if (await candidate.exists()) return candidate.path;
      if (p.equals(root, dir.path)) break;
      dir = dir.parent;
    }
    return null;
  }

  Future<void> _writeProjectManifest(Directory root) async {
    final topLevelDirs = <String>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (_ignoredDirs.contains(name)) continue;
      topLevelDirs.add(name);
    }
    topLevelDirs.sort();

    final stacks = await _detectStacks(root.path);
    final frameworks = await _detectFrameworks(root.path);
    final buffer = StringBuffer()
      ..writeln('^${p.basename(root.path)}:${stacks.join("+")}');

    for (final dir in topLevelDirs) {
      buffer.writeln(' @${_compactPath(dir)}:${_roleForDirectory(dir)}');
    }

    if (frameworks.isNotEmpty) {
      buffer.writeln(' ~[${frameworks.join(",")}]');
    }
    buffer.writeln('\$lsdf:$version');

    await File(
      p.join(root.path, 'project.lsdf'),
    ).writeAsString(buffer.toString());
  }

  Future<void> _generateDirectory(
    Directory dir, {
    required bool recursive,
  }) async {
    if (_shouldSkipDirectory(dir.path)) return;

    final files = <File>[];
    final childDirs = <Directory>[];

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        if (!_shouldSkipDirectory(entity.path)) childDirs.add(entity);
      } else if (entity is File && _isSourceFile(entity.path)) {
        files.add(entity);
      }
    }

    files.sort((a, b) => a.path.compareTo(b.path));
    childDirs.sort((a, b) => a.path.compareTo(b.path));

    final nav = StringBuffer();
    final detail = StringBuffer();

    for (final file in files) {
      final entry = await _buildFileEntry(file);
      if (entry == null) continue;
      if (nav.isNotEmpty) nav.writeln();
      nav.write(entry.nav.trimRight());
      if (detail.isNotEmpty) detail.writeln();
      detail.write(entry.detail.trimRight());
    }

    for (final child in childDirs) {
      final hasSource = await _containsSource(child);
      if (hasSource) {
        if (nav.isNotEmpty) nav.writeln();
        nav.writeln('@INDEX:${_compactPath(p.basename(child.path))}');
        if (detail.isNotEmpty) detail.writeln();
        detail.writeln('@INDEX:${_compactPath(p.basename(child.path))}');
      }
    }

    await _writeOrDelete(p.join(dir.path, 'INDEX.lsdf'), nav.toString());
    await _writeOrDelete(
      p.join(dir.path, 'INDEX.detail.lsdf'),
      detail.toString(),
    );

    if (recursive) {
      for (final child in childDirs) {
        await _generateDirectory(child, recursive: true);
      }
    }
  }

  Future<_LsdfFileEntry?> _buildFileEntry(File file) async {
    String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      return null;
    }

    final relativePath = p.relative(file.path, from: rootPath);
    final signature = _flowAnalyzer.extractSignatures(file.path, content);
    final imports = _importParser.parseFile(file.path, content);
    final deps = _compactImports(imports);

    final nav = StringBuffer()
      ..writeln('@${_compactPath(p.basename(file.path))}');
    if (deps.isNotEmpty) nav.writeln(' ~${deps.join(",")}');
    for (final className in signature.classNames.take(20)) {
      nav.writeln(' @${_compactEntity(className)}');
    }
    for (final fn in signature.functionSignatures.take(40)) {
      nav.writeln(' !${_functionName(fn)}');
    }
    for (final constant in signature.exportedConstants.take(20)) {
      nav.writeln(' \$${_compactEntity(constant)}');
    }

    final detail = StringBuffer()
      ..writeln('@${_compactPath(p.basename(file.path))}');
    if (deps.isNotEmpty) detail.writeln(' ~${deps.join(",")}');
    for (final className in signature.classNames.take(30)) {
      detail.writeln(' @${_compactEntity(className)}');
    }
    for (final fn in signature.functionSignatures.take(80)) {
      detail.writeln(' !${_compactSignature(fn)}');
    }
    for (final constant in signature.exportedConstants.take(30)) {
      detail.writeln(' \$${_compactEntity(constant)}');
    }
    detail.writeln(' \$src:${_compactPath(relativePath)}');

    return _LsdfFileEntry(nav: nav.toString(), detail: detail.toString());
  }

  List<String> _compactImports(List<ParsedImport> imports) {
    final deps = <String>[];
    for (final import in imports) {
      final raw = import.isRelative
          ? p.relative(import.targetPath, from: rootPath)
          : import.targetPath;
      final compact = _compactDependency(raw);
      if (compact.isNotEmpty && !deps.contains(compact)) {
        deps.add(compact);
      }
    }
    deps.sort();
    return deps.take(20).toList();
  }

  String _compactDependency(String raw) {
    var value = raw
        .replaceFirst(RegExp(r'^package:'), '')
        .replaceFirst(RegExp(r'^dart:'), 'dart/')
        .replaceAll('\\', '/');
    final ext = p.extension(value);
    if (_sourceExtensions.contains(ext)) {
      value = value.substring(0, value.length - ext.length);
    }
    return _compactPath(value);
  }

  String _compactSignature(String sig) {
    var compact = sig.trim();
    compact = compact.replaceAll(RegExp(r'\s+'), ' ');
    compact = compact.replaceAll(RegExp(r'\bself,\s*|\bself\b'), '');
    compact = compact.replaceAll(RegExp(r'\bcls,\s*|\bcls\b'), '');
    compact = compact.replaceAll(RegExp(r'\bString\b'), 's');
    compact = compact.replaceAll(RegExp(r'\bint\b'), 'i');
    compact = compact.replaceAll(RegExp(r'\bdouble\b'), 'f');
    compact = compact.replaceAll(RegExp(r'\bbool\b'), 'b');
    compact = compact.replaceAll(RegExp(r'\bdynamic\b'), 'a');
    compact = compact.replaceAll(RegExp(r'\bvoid\s+'), '');
    compact = compact.replaceAll(RegExp(r'\bFuture<'), 'F<');
    compact = compact.replaceAll(RegExp(r'\bStream<'), 'S<');
    compact = compact.replaceAll(RegExp(r'\s*{\s*$'), '');
    compact = compact.replaceAll(RegExp(r'\s*=>\s*$'), '');
    return _compactEntity(compact);
  }

  String _functionName(String sig) {
    final python = RegExp(r'def\s+(\w+)').firstMatch(sig);
    if (python != null) return python.group(1)!;

    final generic = RegExp(r'([A-Za-z_]\w*)\s*\(').allMatches(sig).toList();
    if (generic.isNotEmpty) return generic.last.group(1)!;

    return _compactSignature(sig);
  }

  Future<bool> _containsSource(Directory dir) async {
    if (_shouldSkipDirectory(dir.path)) return false;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (_shouldSkipDirectory(entity.path)) continue;
      if (entity is File && _isSourceFile(entity.path)) return true;
    }
    return false;
  }

  Future<void> _writeOrDelete(String path, String content) async {
    final file = File(path);
    final trimmed = content.trimRight();
    if (trimmed.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString('$trimmed\n');
  }

  Future<List<String>> _detectStacks(String root) async {
    final stacks = <String>[];
    Future<void> addIf(String fileName, String stack) async {
      if (await File(p.join(root, fileName)).exists() &&
          !stacks.contains(stack)) {
        stacks.add(stack);
      }
    }

    await addIf('pubspec.yaml', 'Dart');
    await addIf('package.json', 'Node');
    await addIf('tsconfig.json', 'TypeScript');
    await addIf('pyproject.toml', 'Python');
    await addIf('requirements.txt', 'Python');
    await addIf('go.mod', 'Go');
    await addIf('Cargo.toml', 'Rust');
    return stacks.isEmpty ? ['Mixed'] : stacks;
  }

  Future<List<String>> _detectFrameworks(String root) async {
    final frameworks = <String>[];
    final candidates = {
      'pubspec.yaml': {
        'flutter:': 'Flutter',
        'riverpod': 'Riverpod',
        'dio:': 'Dio',
      },
      'package.json': {
        'react': 'React',
        'next': 'Next.js',
        'express': 'Express',
        'typescript': 'TypeScript',
      },
      'pyproject.toml': {
        'pytest': 'Pytest',
        'click': 'Click',
        'fastapi': 'FastAPI',
      },
      'requirements.txt': {
        'pytest': 'Pytest',
        'flask': 'Flask',
        'fastapi': 'FastAPI',
      },
    };

    for (final entry in candidates.entries) {
      final file = File(p.join(root, entry.key));
      if (!await file.exists()) continue;
      final content = (await file.readAsString()).toLowerCase();
      for (final marker in entry.value.entries) {
        if (content.contains(marker.key.toLowerCase()) &&
            !frameworks.contains(marker.value)) {
          frameworks.add(marker.value);
        }
      }
    }
    return frameworks;
  }

  String _roleForDirectory(String name) {
    final lower = name.toLowerCase();
    if (lower == 'lib' || lower == 'src') return 'main-code';
    if (lower == 'test' || lower == 'tests') return 'test-suite';
    if (lower == 'docs' || lower == 'doc') return 'documentation';
    if (lower == 'assets') return 'assets';
    if (lower == 'scripts' || lower == 'tool') return 'automation';
    if (lower == 'examples') return 'examples';
    if (lower.contains('server') || lower.contains('api')) return 'service';
    return 'module';
  }

  bool _isSourceFile(String path) {
    if (FileUtils.isBinaryFile(path)) return false;
    return _sourceExtensions.contains(p.extension(path).toLowerCase());
  }

  bool _shouldSkipDirectory(String path) {
    final segments = p.split(path);
    return segments.any(_ignoredDirs.contains);
  }

  String _resolvePath(String path) =>
      p.isAbsolute(path) ? path : p.normalize(p.join(rootPath, path));

  String _compactPath(String value) =>
      value.replaceAll('\\', '/').replaceAll(RegExp(r'\s+'), '_');

  String _compactEntity(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static const _instructions = '''
# L-SDF Protocol

Use compact L-SDF maps before opening source files:
1. Read `project.lsdf` for repository layout.
2. Read the nearest `INDEX.lsdf` for navigation.
3. Read `INDEX.detail.lsdf` for signatures, schemas, imports, and source paths.
4. Open raw source only when implementation bodies are needed.
5. After structural edits, regenerate affected indexes.

Sigils: `^` project, `@` entity/file/class, `!` function, `~` dependency, `?` schema, `\$` annotation.
''';
}

class LsdfPromptContext {
  final String content;
  final bool wasTruncated;

  const LsdfPromptContext({required this.content, required this.wasTruncated});

  bool get isEmpty => content.trim().isEmpty;
}

class _LsdfFileEntry {
  final String nav;
  final String detail;

  const _LsdfFileEntry({required this.nav, required this.detail});
}
