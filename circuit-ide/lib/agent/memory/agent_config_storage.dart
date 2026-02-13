import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../core/utils/platform_utils.dart';
import '../../models/agent_config_model.dart';

class AgentConfigStorage {
  static String get _agentsDir =>
      p.join(PlatformUtils.configDir, 'agents');

  Future<List<AgentConfigModel>> loadAll() async {
    final dir = Directory(_agentsDir);
    if (!await dir.exists()) return [];

    final configs = <AgentConfigModel>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final json = jsonDecode(await entity.readAsString())
              as Map<String, dynamic>;
          configs.add(AgentConfigModel.fromJson(json));
        } catch (e) {
          Logger.error(
              'Failed to load agent config: ${entity.path}', e);
        }
      }
    }
    configs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return configs;
  }

  Future<void> save(AgentConfigModel config) async {
    final dir = Directory(_agentsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File(p.join(_agentsDir, '${config.id}.json'));
    await file.writeAsString(config.toJsonString());
    Logger.info('Agent config saved: ${config.name}', 'AgentConfigStorage');
  }

  Future<void> delete(String id) async {
    final file = File(p.join(_agentsDir, '$id.json'));
    if (await file.exists()) {
      await file.delete();
      Logger.info('Agent config deleted: $id', 'AgentConfigStorage');
    }
  }
}
