import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/agent_workspace.dart';
import '../models/studio_thread.dart';
import '../services/versioned_json_document.dart';
import '../state/agent_workspace_provider.dart';
import '../state/studio_thread_provider.dart';

class StudioProjectTransferExport {
  final int taskCount;
  final int threadCount;
  final int redactionCount;
  final List<String> warnings;

  const StudioProjectTransferExport({
    required this.taskCount,
    required this.threadCount,
    required this.redactionCount,
    this.warnings = const [],
  });
}

class StudioProjectTransferImport {
  final int taskCount;
  final int threadCount;
  final List<String> missingReferences;
  final List<String> warnings;

  const StudioProjectTransferImport({
    required this.taskCount,
    required this.threadCount,
    this.missingReferences = const [],
    this.warnings = const [],
  });
}

/// Portable, local-first project transfer with a deliberately small contract.
///
/// The package includes durable task/thread history, accepted plans and patch
/// metadata already represented by turns, plus source-artifact references. It
/// never copies source files, command logs, credentials, or raw artifact
/// payloads. Import is blocked into a non-empty destination unless the caller
/// explicitly opts into a collision-free merge.
class StudioProjectTransferService {
  static const packageKind = 'circuit.studio-project-transfer';
  static const packageVersion = 1;

  final AgentWorkspaceStore taskStore;
  final StudioThreadStore threadStore;

  StudioProjectTransferService({
    AgentWorkspaceStore? taskStore,
    StudioThreadStore? threadStore,
  }) : taskStore = taskStore ?? AgentWorkspaceStore(),
       threadStore = threadStore ?? StudioThreadStore();

  Future<StudioProjectTransferExport> exportProject(
    String projectRoot,
    String destinationPath,
  ) async {
    final tasks = await taskStore.load(projectRoot);
    final threads = await threadStore.load(projectRoot);
    final redactor = _TransferRedactor();
    final taskJson = tasks
        .map((task) => redactor.value(task.toJson()))
        .toList();
    final threadJson = threads
        .map((thread) => _portableThreadJson(thread, redactor))
        .toList();
    final payload = <String, dynamic>{
      'kind': packageKind,
      'version': packageVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'project': {
        'label': p.basename(p.normalize(projectRoot)),
        'sourceReferencesIncluded': true,
        'sourceFilesIncluded': false,
        'commandLogsIncluded': false,
      },
      'tasks': taskJson,
      'threads': threadJson,
      'redaction': {
        'credentials': 'redacted',
        'artifactPayloads': 'metadata-only',
        'count': redactor.count,
      },
    };
    await writeVersionedJsonAtomically(
      File(destinationPath),
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    return StudioProjectTransferExport(
      taskCount: tasks.length,
      threadCount: threads.length,
      redactionCount: redactor.count,
      warnings: const [
        'Source files and command logs are references only; they are not copied into the transfer.',
      ],
    );
  }

  Future<StudioProjectTransferImport> importProject(
    String projectRoot,
    String sourcePath, {
    bool allowMerge = false,
  }) async {
    final decoded = jsonDecode(await File(sourcePath).readAsString());
    if (decoded is! Map<String, dynamic> || decoded['kind'] != packageKind) {
      throw const FormatException(
        'This is not a CircuitCode project transfer.',
      );
    }
    if (decoded['version'] is! int || decoded['version'] > packageVersion) {
      throw const FormatException(
        'This project transfer was created by a newer CircuitCode version.',
      );
    }
    final importedTasks = (decoded['tasks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AgentTask.fromJson)
        .nonNulls
        .toList();
    final importedThreads = (decoded['threads'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StudioThread.fromJson)
        .nonNulls
        .toList();
    final existingTasks = await taskStore.load(projectRoot);
    final existingThreads = await threadStore.load(projectRoot);
    if (!allowMerge &&
        (existingTasks.isNotEmpty || existingThreads.isNotEmpty)) {
      throw StateError(
        'The destination already has project history. Choose an empty project or confirm a merge.',
      );
    }
    final taskIds = existingTasks.map((task) => task.id).toSet();
    final threadIds = existingThreads.map((thread) => thread.id).toSet();
    final collisions = [
      ...importedTasks
          .where((task) => !taskIds.add(task.id))
          .map((task) => task.id),
      ...importedThreads
          .where((thread) => !threadIds.add(thread.id))
          .map((thread) => thread.id),
    ];
    if (collisions.isNotEmpty) {
      throw StateError(
        'Import would overwrite ${collisions.length} existing task or thread record${collisions.length == 1 ? '' : 's'}.',
      );
    }
    await taskStore.save(projectRoot, [...importedTasks, ...existingTasks]);
    await threadStore.save(projectRoot, [
      ...importedThreads,
      ...existingThreads,
    ]);
    final missingReferences = _missingReferences(projectRoot, importedThreads);
    return StudioProjectTransferImport(
      taskCount: importedTasks.length,
      threadCount: importedThreads.length,
      missingReferences: missingReferences,
      warnings: missingReferences.isEmpty
          ? const []
          : [
              '${missingReferences.length} source reference${missingReferences.length == 1 ? '' : 's'} could not be found in this installation.',
            ],
    );
  }

  Map<String, dynamic> _portableThreadJson(
    StudioThread thread,
    _TransferRedactor redactor,
  ) {
    final json = Map<String, dynamic>.from(thread.toJson());
    final artifacts = <Map<String, dynamic>>[];
    for (final artifact in thread.sourceArtifacts) {
      artifacts.add(
        redactor.value({
              ...artifact.toJson(),
              // `value` can be a raw tool/artifact payload. Preserve only a
              // readable metadata marker and its structured references.
              'value': '[Exported metadata only]',
            })
            as Map<String, dynamic>,
      );
    }
    json['sourceArtifacts'] = artifacts;
    return redactor.value(json) as Map<String, dynamic>;
  }

  List<String> _missingReferences(
    String projectRoot,
    List<StudioThread> threads,
  ) {
    final missing = <String>{};
    for (final artifact in threads.expand((thread) => thread.sourceArtifacts)) {
      final reference = artifact.filePath?.trim();
      if (reference == null || reference.isEmpty) continue;
      final target = p.isAbsolute(reference)
          ? reference
          : p.join(projectRoot, reference);
      if (!File(target).existsSync() && !Directory(target).existsSync()) {
        missing.add(reference);
      }
    }
    return missing.toList()..sort();
  }
}

class _TransferRedactor {
  static final _secretValue = RegExp(
    r'(sk-[A-Za-z0-9_-]{12,}|bearer\s+[A-Za-z0-9._-]{12,}|(?:api[_ -]?key|token|secret|password)\s*[:=]\s*[^\s,;]+)',
    caseSensitive: false,
  );

  int count = 0;

  dynamic value(dynamic input, {String? key}) {
    if (key != null && _isSensitiveKey(key)) {
      count++;
      return '[REDACTED]';
    }
    if (input is Map) {
      return <String, dynamic>{
        for (final entry in input.entries)
          entry.key.toString(): value(entry.value, key: entry.key.toString()),
      };
    }
    if (input is List) return input.map((item) => value(item)).toList();
    if (input is String) {
      var matches = 0;
      final redacted = input.replaceAllMapped(_secretValue, (match) {
        matches++;
        return '[REDACTED]';
      });
      count += matches;
      return redacted;
    }
    return input;
  }

  bool _isSensitiveKey(String key) {
    final normalized = key
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    return normalized == 'authorization' ||
        normalized == 'cookie' ||
        normalized == 'password' ||
        normalized == 'secret' ||
        normalized == 'apikey' ||
        normalized == 'privatekey' ||
        normalized.endsWith('token');
  }
}
