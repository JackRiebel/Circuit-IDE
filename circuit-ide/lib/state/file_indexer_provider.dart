import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/file_indexer.dart';
import 'file_tree_provider.dart';

class FileIndexerNotifier extends Notifier<FileIndexer?> {
  @override
  FileIndexer? build() {
    // Auto-index when project changes
    ref.listen(fileTreeProvider, (prev, next) {
      if (next.rootPath != null && next.rootPath != prev?.rootPath) {
        _createIndexer(next.rootPath!);
      }
    });
    return null;
  }

  void _createIndexer(String workingDir) {
    final indexer = FileIndexer(workingDir: workingDir);
    state = indexer;
    indexer.index();
  }

  Future<void> refresh() async {
    await state?.index();
  }

  Future<void> refreshIfStale() async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;

    var indexer = state;
    if (indexer == null || indexer.workingDir != rootPath) {
      indexer = FileIndexer(workingDir: rootPath);
      state = indexer;
    }
    await indexer.refreshIfStale();
  }

  List<IndexedFile> search(String query, {int limit = 20}) {
    return state?.search(query, limit: limit) ?? [];
  }
}

final fileIndexerProvider = NotifierProvider<FileIndexerNotifier, FileIndexer?>(
  FileIndexerNotifier.new,
);
