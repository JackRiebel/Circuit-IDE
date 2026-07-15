import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/utils/logger.dart';
import '../models/notebook.dart';
import 'versioned_json_document.dart';

/// Persists notebooks as JSON files in {projectRoot}/.circuit/notebooks/.
class NotebookStorage {
  static const _notebooksDir = '.circuit/notebooks';
  static const _schemaKind = 'circuit.notebook';
  static const _schemaVersion = 2;

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
      await writeVersionedJsonAtomically(file, _encode(notebook));
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
            final document = VersionedJsonDocument.decode(
              jsonDecode(content),
              expectedKind: _schemaKind,
              currentSchemaVersion: _schemaVersion,
            );
            final payload = document.payload;
            if (payload is! Map) {
              throw const FormatException('Notebook payload is not an object.');
            }
            final notebook = Notebook.fromJson(
              Map<String, dynamic>.from(payload),
            );
            if (document.schemaVersion < _schemaVersion) {
              await migrateVersionedJsonFile(
                file: entity,
                originalContents: content,
                migratedContents: _encode(notebook),
                previousSchemaVersion: document.schemaVersion,
              );
            }
            notebooks.add(notebook);
          } catch (e) {
            if (e is UnsupportedRuntimeSchemaVersion) rethrow;
            Logger.error(
              'Failed to load notebook: ${entity.path}',
              e.toString(),
            );
          }
        }
      }

      // Sort by most recently modified
      notebooks.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    } on UnsupportedRuntimeSchemaVersion {
      rethrow;
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

  String _encode(Notebook notebook) => VersionedJsonDocument(
    kind: _schemaKind,
    schemaVersion: _schemaVersion,
    payload: notebook.toJson(),
  ).encode(pretty: true);
}
