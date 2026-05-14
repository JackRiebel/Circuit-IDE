import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../core/utils/platform_utils.dart';
import '../mcp/mcp_token_storage.dart';
import 'mcp_config.dart';

/// Persists MCP server configurations to ~/.config/circuit-ide/mcp_servers.json
class McpConfigStorage {
  static String get _filePath =>
      p.join(PlatformUtils.configDir, 'mcp_servers.json');

  final _tokenStorage = McpTokenStorage();

  Future<List<McpServerConfig>> load() async {
    final file = File(_filePath);
    if (!await file.exists()) return [];

    try {
      final json = jsonDecode(await file.readAsString());
      final list = json['servers'] as List? ?? [];
      final configs = <McpServerConfig>[];
      var migrated = false;

      for (final e in list) {
        final map = e as Map<String, dynamic>;
        var config = McpServerConfig.fromJson(map);

        // Migrate plain-text Authorization headers into secure storage
        final authHeader = config.headers['Authorization'];
        if (authHeader != null && authHeader.isNotEmpty) {
          final token = authHeader.startsWith('Bearer ')
              ? authHeader.substring(7)
              : authHeader;
          // Determine the env var name based on server name
          final envVar = _authEnvVarForServer(config.name);
          await _tokenStorage.saveTokens(config.name, {envVar: token});
          // Strip the Authorization header
          final cleanHeaders = Map<String, String>.from(config.headers)
            ..remove('Authorization');
          config = config.copyWith(headers: cleanHeaders);
          migrated = true;
          Logger.info(
            'Migrated Authorization header for ${config.name} to secure storage',
            'McpConfigStorage',
          );
        }

        configs.add(config);
      }

      // Re-save without Authorization headers if we migrated
      if (migrated) {
        await save(configs);
      }

      return configs;
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

    // Strip Authorization headers before writing
    final sanitized = configs.map((c) {
      if (c.headers.containsKey('Authorization')) {
        final clean = Map<String, String>.from(c.headers)
          ..remove('Authorization');
        return c.copyWith(headers: clean).toJson();
      }
      return c.toJson();
    }).toList();

    // Preserve bot_agent config if it exists
    Map<String, dynamic>? botAgent;
    final file = File(_filePath);
    if (await file.exists()) {
      try {
        final existing = jsonDecode(await file.readAsString());
        botAgent = existing['bot_agent'] as Map<String, dynamic>?;
      } catch (_) {}
    }

    final json = <String, dynamic>{'servers': sanitized};
    if (botAgent != null) {
      json['bot_agent'] = botAgent;
    }

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    Logger.info(
      'Saved ${configs.length} MCP server configs',
      'McpConfigStorage',
    );
  }

  /// Load bot agent config from the JSON file.
  Future<Map<String, dynamic>?> loadBotConfig() async {
    final file = File(_filePath);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      return json['bot_agent'] as Map<String, dynamic>?;
    } catch (e) {
      Logger.error('Failed to load bot config', e);
      return null;
    }
  }

  /// Save bot agent config to the JSON file.
  Future<void> saveBotConfig(Map<String, dynamic> botConfig) async {
    final file = File(_filePath);
    Map<String, dynamic> json = {};
    if (await file.exists()) {
      try {
        json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }

    json['bot_agent'] = botConfig;

    final dir = Directory(p.dirname(_filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  /// Map server names to their primary auth env var for migration.
  String _authEnvVarForServer(String name) {
    switch (name.toLowerCase()) {
      case 'webex':
        return 'WEBEX_TOKEN';
      case 'github':
        return 'GITHUB_TOKEN';
      case 'jira':
        return 'JIRA_TOKEN';
      default:
        return 'AUTH_TOKEN';
    }
  }
}
