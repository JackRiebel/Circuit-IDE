import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'worker_cancellation.dart';

/// Recovers project paths represented by durable task/thread-history files.
///
/// The storage directories can contain hundreds of history files. Listing
/// them, decoding project keys, and checking the recovered paths is all
/// filesystem work, so project-rail discovery keeps it in a worker isolate.
class ProjectHistoryPathScanner {
  const ProjectHistoryPathScanner();

  Future<List<String>> recover({
    required Iterable<String> storageDirectories,
    WorkerCancellationToken? cancellationToken,
  }) {
    return CancellableWorker.run<List<String>>(
      entryPoint: _projectHistoryPathWorkerEntry,
      arguments: {'storageDirectories': storageDirectories.toList()},
      cancellationToken: cancellationToken,
      decodeResult: (result) {
        if (result is! List) {
          throw StateError(
            'Project-history worker returned a malformed path list.',
          );
        }
        return result
            .whereType<String>()
            .where((path) => path.trim().isNotEmpty)
            .toList(growable: false);
      },
    );
  }
}

void _projectHistoryPathWorkerEntry(Map<String, Object?> arguments) {
  final replyPort = arguments['replyPort'];
  if (replyPort is! SendPort) return;
  try {
    final directories =
        (arguments['storageDirectories'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const <String>[];
    replyPort.send({'result': _recoverProjectPaths(directories)});
  } catch (error) {
    replyPort.send({'error': error.toString()});
  }
}

List<String> _recoverProjectPaths(Iterable<String> storageDirectories) {
  final recovered = <String>{};
  for (final directoryPath in storageDirectories) {
    try {
      final directory = Directory(directoryPath);
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final name = entity.uri.pathSegments.last.replaceFirst('.json', '');
        final projectPath = _decodeProjectKey(name);
        if (projectPath != null && Directory(projectPath).existsSync()) {
          recovered.add(projectPath);
        }
      }
    } catch (_) {
      // A single unavailable history directory must not hide other projects.
    }
  }
  return recovered.toList(growable: false);
}

String? _decodeProjectKey(String key) {
  if (key == 'scratch') return null;
  try {
    final normalized = base64Url.normalize(key);
    return utf8.decode(base64Url.decode(normalized));
  } catch (_) {
    return null;
  }
}
