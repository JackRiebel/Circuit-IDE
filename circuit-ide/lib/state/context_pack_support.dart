part of 'context_pack_provider.dart';

class _RelevantFileScore {
  final String path;
  final String content;
  final int score;
  final String reason;

  const _RelevantFileScore(this.path, this.content, this.score, this.reason);
}

class _RelevantFileResult {
  final List<ContextPackItem> items;
  final List<ContextCandidate> omittedCandidates;

  const _RelevantFileResult({
    required this.items,
    required this.omittedCandidates,
  });
}

class _InstructionFileScore {
  final ContextPackItem item;
  final int score;
  final String relativePath;

  const _InstructionFileScore({
    required this.item,
    required this.score,
    required this.relativePath,
  });
}

class ContextPreferenceStore {
  final String baseDir;

  ContextPreferenceStore({String? baseDir})
    : baseDir = baseDir ?? p.join(PlatformUtils.configDir, 'context');

  String pathForRoot(String? rootPath) {
    final key = _projectKey(rootPath);
    return p.join(baseDir, '$key.preferences.json');
  }

  Set<String> loadIncludedPaths(String? rootPath) {
    return _loadPaths(rootPath, 'include_next_paths');
  }

  Set<String> loadExcludedPaths(String? rootPath) {
    return _loadPaths(rootPath, 'exclude_project_paths');
  }

  Set<String> _loadPaths(String? rootPath, String key) {
    try {
      final file = File(pathForRoot(rootPath));
      if (!file.existsSync()) return const {};
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final paths =
          (json[key] as List<dynamic>?)?.whereType<String>() ??
          const Iterable<String>.empty();
      return paths.map(_normalizePreferencePath).whereType<String>().toSet();
    } catch (_) {
      return const {};
    }
  }

  void saveIncludedPaths(String? rootPath, Set<String> paths) {
    _savePaths(rootPath, include: paths);
  }

  void saveExcludedPaths(String? rootPath, Set<String> paths) {
    _savePaths(rootPath, exclude: paths);
  }

  void clear(String? rootPath) {
    try {
      final file = File(pathForRoot(rootPath));
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  void _savePaths(
    String? rootPath, {
    Set<String>? include,
    Set<String>? exclude,
  }) {
    try {
      final file = File(pathForRoot(rootPath));
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      List<String> safePaths(Set<String> paths) =>
          paths.map(_normalizePreferencePath).whereType<String>().toList()
            ..sort();
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'rootPath': rootPath,
          'include_next_paths': safePaths(
            include ?? loadIncludedPaths(rootPath),
          ),
          'exclude_project_paths': safePaths(
            exclude ?? loadExcludedPaths(rootPath),
          ),
        }),
      );
    } catch (_) {}
  }

  static String _projectKey(String? rootPath) {
    if (rootPath == null || rootPath.isEmpty) return 'scratch';
    return base64Url.encode(utf8.encode(rootPath)).replaceAll('=', '');
  }

  static String? _normalizePreferencePath(String path) {
    final normalized = p.normalize(path).replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('/') ||
        normalized.startsWith('//') ||
        p.isAbsolute(normalized) ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
      return null;
    }
    final parts = normalized.split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      return null;
    }
    return normalized;
  }
}

final contextPreferenceStoreProvider = Provider<ContextPreferenceStore>(
  (ref) => ContextPreferenceStore(),
);

/// The directory containing user-wide Circuit instruction files. Keeping this
/// injectable makes instruction precedence deterministic in tests without
/// reading a developer's real home-directory configuration.
final globalCircuitInstructionDirectoryProvider = Provider<String>(
  (ref) => PlatformUtils.configDir,
);

class ContextPreferenceRevisionController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state++;
  }
}

final contextPreferenceRevisionProvider =
    NotifierProvider<ContextPreferenceRevisionController, int>(
      ContextPreferenceRevisionController.new,
    );
