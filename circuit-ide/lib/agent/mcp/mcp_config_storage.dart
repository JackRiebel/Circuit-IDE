import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../core/utils/platform_utils.dart';
import 'mcp_config.dart';

/// Persists MCP server configurations to ~/.config/circuit-ide/mcp_servers.json
class McpConfigStorage {
  static String get _filePath =>
      p.join(PlatformUtils.configDir, 'mcp_servers.json');

  Future<List<McpServerConfig>> load() async {
    final file = File(_filePath);
    if (!await file.exists()) return [];

    try {
      final json = jsonDecode(await file.readAsString());
      final list = json['servers'] as List? ?? [];
      return list
          .map((e) => McpServerConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Logger.error('Failed to load MCP server configs', e);
      return [];
    }
  }

  Future<void> save(List<McpServerConfig> configs) async {
    final dir = Directory(p.dirname(_filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final json = jsonEncode({
      'servers': configs.map((c) => c.toJson()).toList(),
    });
    await File(_filePath).writeAsString(json);
    Logger.info(
      'Saved ${configs.length} MCP server configs',
      'McpConfigStorage',
    );
  }
}
