import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../core/utils/platform_utils.dart';
import '../../models/agent_config_model.dart';
import '../../services/versioned_json_document.dart';

class AgentConfigStorage {
  static const _schemaKind = 'circuit.agent-definition';
  static const _schemaVersion = 4;

  final String agentsDir;

  AgentConfigStorage({String? agentsDir})
    : agentsDir = agentsDir ?? p.join(PlatformUtils.configDir, 'agents');

  Future<List<AgentConfigModel>> loadAll() async {
    final dir = Directory(agentsDir);
    if (!await dir.exists()) return [];

    final configs = <AgentConfigModel>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final contents = await entity.readAsString();
          final document = VersionedJsonDocument.decode(
            jsonDecode(contents),
            expectedKind: _schemaKind,
            currentSchemaVersion: _schemaVersion,
          );
          final payload = document.payload;
          if (payload is! Map) {
            throw const FormatException(
              'Agent definition payload is not an object.',
            );
          }
          var config = AgentConfigModel.fromJson(
            Map<String, dynamic>.from(payload),
          );
          // Agent activation is an explicit library review step. Older
          // packages predate the review UI, so migrate them disabled instead
          // of silently allowing a saved capability set to run.
          if (document.schemaVersion < _schemaVersion) {
            config = config.copyWith(enabled: false);
          }
          final validationErrors = config.validate();
          if (validationErrors.isNotEmpty) {
            throw FormatException(validationErrors.join(' '));
          }
          if (document.schemaVersion < _schemaVersion) {
            await migrateVersionedJsonFile(
              file: entity,
              originalContents: contents,
              migratedContents: _encode(config),
              previousSchemaVersion: document.schemaVersion,
            );
          }
          configs.add(config);
        } catch (e) {
          if (e is UnsupportedRuntimeSchemaVersion) rethrow;
          Logger.error('Failed to load agent config: ${entity.path}', e);
        }
      }
    }
    configs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return configs;
  }

  Future<void> save(AgentConfigModel config) async {
    final validationErrors = config.validate();
    if (validationErrors.isNotEmpty) {
      throw FormatException(validationErrors.join(' '));
    }
    final dir = Directory(agentsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File(p.join(agentsDir, '${config.id}.json'));
    await writeVersionedJsonAtomically(file, _encode(config));
    Logger.info('Agent config saved: ${config.name}', 'AgentConfigStorage');
  }

  Future<void> delete(String id) async {
    final file = File(p.join(agentsDir, '$id.json'));
    if (await file.exists()) {
      await file.delete();
      Logger.info('Agent config deleted: $id', 'AgentConfigStorage');
    }
  }

  String _encode(AgentConfigModel config) => VersionedJsonDocument(
    kind: _schemaKind,
    schemaVersion: _schemaVersion,
    payload: config.toJson(),
  ).encode(pretty: true);
}
