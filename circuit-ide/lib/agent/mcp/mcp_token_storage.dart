import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/logger.dart';

/// Stores MCP server tokens securely in the OS keychain.
/// Keys follow the pattern: mcp_token_{serverName}_{ENV_VAR_NAME}
class McpTokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _prefix = 'mcp_token_';

  static String _key(String serverName, String envVar) =>
      '$_prefix${serverName}_$envVar';

  /// Save all tokens for a server.
  Future<void> saveTokens(String serverName, Map<String, String> tokens) async {
    try {
      for (final entry in tokens.entries) {
        await _storage.write(
          key: _key(serverName, entry.key),
          value: entry.value,
        );
      }
      Logger.info(
        'Saved ${tokens.length} tokens for $serverName',
        'McpTokenStorage',
      );
    } catch (e) {
      Logger.error('Failed to save tokens for $serverName', e);
    }
  }

  /// Replace the full token set for a server, deleting any required token whose
  /// new value is empty or omitted.
  Future<void> replaceTokens(
    String serverName,
    List<String> envVarNames,
    Map<String, String> tokens,
  ) async {
    try {
      for (final envVar in envVarNames) {
        final value = tokens[envVar]?.trim() ?? '';
        if (value.isEmpty) {
          await _storage.delete(key: _key(serverName, envVar));
        } else {
          await _storage.write(key: _key(serverName, envVar), value: value);
        }
      }
      Logger.info('Replaced token set for $serverName', 'McpTokenStorage');
    } catch (e) {
      Logger.error('Failed to replace tokens for $serverName', e);
    }
  }

  /// Load all tokens for a server given its required env var names.
  Future<Map<String, String>> loadTokens(
    String serverName,
    List<String> envVarNames,
  ) async {
    final tokens = <String, String>{};
    try {
      for (final envVar in envVarNames) {
        final value = await _storage.read(key: _key(serverName, envVar));
        if (value != null) {
          tokens[envVar] = value;
        }
      }
    } catch (e) {
      Logger.error('Failed to load tokens for $serverName', e);
    }
    return tokens;
  }

  /// Delete all tokens for a server.
  Future<void> deleteTokens(String serverName, List<String> envVarNames) async {
    try {
      for (final envVar in envVarNames) {
        await _storage.delete(key: _key(serverName, envVar));
      }
    } catch (e) {
      Logger.error('Failed to delete tokens for $serverName', e);
    }
  }

  /// Check whether all required tokens are stored.
  Future<bool> hasTokens(String serverName, List<String> envVarNames) async {
    try {
      for (final envVar in envVarNames) {
        final value = await _storage.read(key: _key(serverName, envVar));
        if (value == null || value.isEmpty) return false;
      }
      return envVarNames.isNotEmpty;
    } catch (e) {
      Logger.error('Failed to check tokens for $serverName', e);
      return false;
    }
  }
}
