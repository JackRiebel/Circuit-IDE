import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils/logger.dart';
import '../models/notebook.dart';

/// Persists notebooks as JSON files in {projectRoot}/.circuit/notebooks/.
class NotebookStorage {
  static const _notebooksDir = '.circuit/notebooks';

  /// Get the notebooks directory path for a given project root.
  String _notebooksPath(String projectRoot) {
    return p.join(projectRoot, _notebooksDir);
  }

  /// Save a notebook to disk as JSON.
  Future<void> saveNotebook(Notebook notebook, String projectRoot) async {
    try {
      final dir = Directory(_notebooksPath(projectRoot));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File(p.join(dir.path, '${notebook.id}.json'));
      final json = const JsonEncoder.withIndent('  ').convert(notebook.toJson());
      await file.writeAsString(json);
    } catch (e) {
      Logger.error('NotebookStorage.saveNotebook failed', e.toString());
    }
  }

  /// Load all notebooks from the project's .circuit/notebooks/ directory.
  Future<List<Notebook>> loadAll(String projectRoot) async {
    final notebooks = <Notebook>[];

    try {
      final dir = Directory(_notebooksPath(projectRoot));
      if (!await dir.exists()) return notebooks;

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            notebooks.add(Notebook.fromJson(json));
          } catch (e) {
            Logger.error(
              'Failed to load notebook: ${entity.path}',
              e.toString(),
            );
          }
        }
      }

      // Sort by most recently modified
      notebooks.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    } catch (e) {
      Logger.error('NotebookStorage.loadAll failed', e.toString());
    }

    return notebooks;
  }

  /// Delete a notebook file from disk.
  Future<void> deleteNotebook(String id, String projectRoot) async {
    try {
      final file = File(p.join(_notebooksPath(projectRoot), '$id.json'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      Logger.error('NotebookStorage.deleteNotebook failed', e.toString());
    }
  }
}
