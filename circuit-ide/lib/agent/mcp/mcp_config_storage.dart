import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';
import '../../core/utils/platform_utils.dart';
import '../../services/versioned_json_document.dart';
import '../mcp/mcp_token_storage.dart';
import 'mcp_config.dart';

/// Persists MCP server configurations to ~/.config/circuit-ide/mcp_servers.json
class McpConfigStorage {
  static const _schemaKind = 'circuit.mcp-server-configurations';
  static const _schemaVersion = 4;

  final String _filePath;
  final McpTokenStore _tokenStorage;

  McpConfigStorage({String? filePath, McpTokenStore? tokenStorage})
    : _filePath =
          filePath ?? p.join(PlatformUtils.configDir, 'mcp_servers.json'),
      _tokenStorage = tokenStorage ?? McpTokenStorage();

  Future<List<McpServerConfig>> load() async {
    final file = File(_filePath);
    if (!await file.exists()) return [];

    try {
      final contents = await file.readAsString();
      final document = VersionedJsonDocument.decode(
        jsonDecode(contents),
        expectedKind: _schemaKind,
        currentSchemaVersion: _schemaVersion,
      );
      final json = _payload(document);
      final list = json['servers'] as List? ?? [];
      final configs = <McpServerConfig>[];
      var migrated = document.schemaVersion < _schemaVersion;

      for (final e in list) {
        final map = e as Map<String, dynamic>;
        var config = McpServerConfig.fromJson(map);

        // Existing config files did not record affirmative approval. Preserve
        // their data, but never reconnect a legacy endpoint until its owner
        // deliberately enables it again in the current app.
        if (config.approvedAt == null && config.enabled) {
          config = config.copyWith(enabled: false);
          migrated = true;
        }
        if (config.consentedAt == null && config.enabled) {
          config = config.copyWith(enabled: false);
          migrated = true;
        }

        final protected = await protectSensitiveHeaders(config);
        if (protected != config) {
          config = protected;
          migrated = true;
        }

        configs.add(config);
      }

      // Re-save after a secure-header or schema migration. The exact source is
      // backed up before this atomic replacement.
      if (migrated) {
        await _migrate(file, contents, document.schemaVersion, configs, json);
      }

      return configs;
    } on UnsupportedRuntimeSchemaVersion {
      rethrow;
    } catch (e) {
      Logger.error('Failed to load MCP server configs', e);
      return [];
    }
  }

  Future<List<McpServerConfig>> save(List<McpServerConfig> configs) async {
    final dir = Directory(p.dirname(_filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final protected = <McpServerConfig>[];
    for (final config in configs) {
      protected.add(await protectSensitiveHeaders(config));
    }
    final sanitized = protected.map((config) => config.toJson()).toList();

    // Preserve the optional bot-agent configuration when editing servers.
    Map<String, dynamic> existing = const {};
    String? originalContents;
    int? previousSchemaVersion;
    final file = File(_filePath);
    if (await file.exists()) {
      originalContents = await file.readAsString();
      final document = VersionedJsonDocument.decode(
        jsonDecode(originalContents),
        expectedKind: _schemaKind,
        currentSchemaVersion: _schemaVersion,
      );
      existing = _payload(document);
      if (document.schemaVersion < _schemaVersion) {
        previousSchemaVersion = document.schemaVersion;
      }
    }

    final json = <String, dynamic>{'servers': sanitized};
    final botAgent = existing['bot_agent'];
    if (botAgent is Map) {
      json['bot_agent'] = Map<String, dynamic>.from(botAgent);
    }

    if (previousSchemaVersion != null && originalContents != null) {
      await _migrate(
        file,
        originalContents,
        previousSchemaVersion,
        protected,
        existing,
      );
    } else {
      await _write(file, json);
    }
    Logger.info(
      'Saved ${protected.length} MCP server configs',
      'McpConfigStorage',
    );
    return protected;
  }

  /// Load bot agent config from the JSON file.
  Future<Map<String, dynamic>?> loadBotConfig() async {
    final file = File(_filePath);
    if (!await file.exists()) return null;
    try {
      final contents = await file.readAsString();
      final document = VersionedJsonDocument.decode(
        jsonDecode(contents),
        expectedKind: _schemaKind,
        currentSchemaVersion: _schemaVersion,
      );
      final json = _payload(document);
      return json['bot_agent'] as Map<String, dynamic>?;
    } on UnsupportedRuntimeSchemaVersion {
      rethrow;
    } catch (e) {
      Logger.error('Failed to load bot config', e);
      return null;
    }
  }

  /// Save bot agent config to the JSON file.
  Future<void> saveBotConfig(Map<String, dynamic> botConfig) async {
    final file = File(_filePath);
    Map<String, dynamic> json = {};
    String? originalContents;
    int? previousSchemaVersion;
    if (await file.exists()) {
      originalContents = await file.readAsString();
      final document = VersionedJsonDocument.decode(
        jsonDecode(originalContents),
        expectedKind: _schemaKind,
        currentSchemaVersion: _schemaVersion,
      );
      json = _payload(document);
      if (document.schemaVersion < _schemaVersion) {
        previousSchemaVersion = document.schemaVersion;
      }
    }

    json['bot_agent'] = botConfig;

    final dir = Directory(p.dirname(_filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (previousSchemaVersion != null && originalContents != null) {
      await migrateVersionedJsonFile(
        file: file,
        originalContents: originalContents,
        migratedContents: _encode(json),
        previousSchemaVersion: previousSchemaVersion,
      );
    } else {
      await _write(file, json);
    }
  }

  Map<String, dynamic> _payload(VersionedJsonDocument document) {
    final payload = document.payload;
    if (payload is! Map) {
      throw const FormatException(
        'MCP configuration payload is not an object.',
      );
    }
    return Map<String, dynamic>.from(payload);
  }

  Future<void> _migrate(
    File file,
    String originalContents,
    int previousSchemaVersion,
    List<McpServerConfig> configs,
    Map<String, dynamic> existing,
  ) async {
    final payload = <String, dynamic>{
      'servers': configs.map((config) => config.toJson()).toList(),
      if (existing['bot_agent'] is Map)
        'bot_agent': Map<String, dynamic>.from(existing['bot_agent'] as Map),
    };
    await migrateVersionedJsonFile(
      file: file,
      originalContents: originalContents,
      migratedContents: _encode(payload),
      previousSchemaVersion: previousSchemaVersion,
    );
  }

  Future<void> _write(File file, Map<String, dynamic> payload) {
    return writeVersionedJsonAtomically(file, _encode(payload));
  }

  String _encode(Map<String, dynamic> payload) {
    return VersionedJsonDocument(
      kind: _schemaKind,
      schemaVersion: _schemaVersion,
      payload: payload,
    ).encode(pretty: true);
  }

  /// Moves sensitive custom header values into Keychain and leaves a stable,
  /// non-secret mapping behind for the HTTP transport to rehydrate at runtime.
  Future<McpServerConfig> protectSensitiveHeaders(
    McpServerConfig config,
  ) async {
    final sensitive = config.headers.entries
        .where(
          (entry) => _isSensitiveHeader(entry.key) && entry.value.isNotEmpty,
        )
        .toList(growable: false);
    if (sensitive.isEmpty) return config;

    final headers = Map<String, String>.from(config.headers);
    final bindings = Map<String, String>.from(config.secureHeaderEnvVars);
    final tokens = <String, String>{};
    for (final entry in sensitive) {
      final tokenKey = bindings.putIfAbsent(
        entry.key,
        () => _headerTokenKey(entry.key),
      );
      tokens[tokenKey] = entry.value;
      headers.remove(entry.key);
    }

    // Do not scrub the file until Keychain accepts every value.
    await _tokenStorage.saveTokens(config.name, tokens);
    return config.copyWith(headers: headers, secureHeaderEnvVars: bindings);
  }

  bool _isSensitiveHeader(String headerName) {
    final normalized = headerName.trim().toLowerCase();
    return normalized == 'authorization' ||
        normalized == 'proxy-authorization' ||
        normalized == 'cookie' ||
        normalized == 'set-cookie' ||
        normalized == 'x-api-key' ||
        normalized == 'api-key' ||
        normalized == 'x-auth-token' ||
        RegExp(
          r'(?:token|secret|credential|api[-_]?key)$',
        ).hasMatch(normalized);
  }

  String _headerTokenKey(String headerName) {
    final normalized = headerName
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'MCP_HEADER_$normalized';
  }
}
