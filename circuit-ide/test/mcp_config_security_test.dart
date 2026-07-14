import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/agent/mcp/mcp_config.dart';
import 'package:circuit_ide/agent/mcp/mcp_config_storage.dart';
import 'package:circuit_ide/agent/mcp/mcp_token_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MCP config persists only non-secret header bindings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'circuit-mcp-config-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final tokens = _MemoryMcpTokenStore();
    final storage = McpConfigStorage(
      filePath: '${directory.path}/mcp_servers.json',
      tokenStorage: tokens,
    );
    const config = McpServerConfig(
      name: 'custom',
      url: 'https://mcp.example.test',
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer private-token',
        'X-API-Key': 'private-api-key',
      },
    );

    final saved = await storage.save([config]);
    final fileContents = await File(
      '${directory.path}/mcp_servers.json',
    ).readAsString();
    final document = jsonDecode(fileContents) as Map<String, dynamic>;
    expect(document['schemaVersion'], 4);
    expect(document['kind'], 'circuit.mcp-server-configurations');
    final payload = document['payload'] as Map<String, dynamic>;
    final persisted =
        (payload['servers'] as List).single as Map<String, dynamic>;
    final headers = persisted['headers'] as Map<String, dynamic>;
    final bindings = persisted['secureHeaderEnvVars'] as Map<String, dynamic>;

    expect(fileContents, isNot(contains('private-token')));
    expect(fileContents, isNot(contains('private-api-key')));
    expect(headers, {'Accept': 'application/json'});
    expect(bindings, {
      'Authorization': 'MCP_HEADER_AUTHORIZATION',
      'X-API-Key': 'MCP_HEADER_X_API_KEY',
    });
    expect(saved.single.secureHeaderEnvVars, bindings);
    expect(tokens.values['custom'], {
      'MCP_HEADER_AUTHORIZATION': 'Bearer private-token',
      'MCP_HEADER_X_API_KEY': 'private-api-key',
    });
  });

  test(
    'MCP header migration leaves plaintext on disk when Keychain rejects it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'circuit-mcp-failure-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/mcp_servers.json');
      await file.writeAsString(
        jsonEncode({
          'servers': [
            {
              'name': 'custom',
              'url': 'https://mcp.example.test',
              'headers': {'Authorization': 'Bearer preserve-me'},
            },
          ],
        }),
      );
      final storage = McpConfigStorage(
        filePath: file.path,
        tokenStorage: _MemoryMcpTokenStore(failWrites: true),
      );

      final loaded = await storage.load();

      expect(loaded, isEmpty);
      expect(await file.readAsString(), contains('preserve-me'));
    },
  );

  test(
    'legacy enabled MCP configs are disabled until explicitly re-approved',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'circuit-mcp-approval-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/mcp_servers.json');
      await file.writeAsString(
        jsonEncode({
          'kind': 'circuit.mcp-server-configurations',
          'schemaVersion': 2,
          'payload': {
            'servers': [
              {
                'name': 'legacy-enabled',
                'url': 'https://mcp.example.test',
                'enabled': true,
              },
            ],
          },
        }),
      );
      final storage = McpConfigStorage(
        filePath: file.path,
        tokenStorage: _MemoryMcpTokenStore(),
      );

      final configs = await storage.load();

      expect(configs, hasLength(1));
      expect(configs.single.enabled, isFalse);
      expect(configs.single.approvedAt, isNull);
      final migrated =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(migrated['schemaVersion'], 4);
      final server =
          ((migrated['payload'] as Map<String, dynamic>)['servers']
                      as List<dynamic>)
                  .single
              as Map<String, dynamic>;
      expect(server['enabled'], isFalse);
      expect(server.containsKey('approvedAt'), isFalse);
      expect(server.containsKey('consentedAt'), isFalse);
    },
  );
}

class _MemoryMcpTokenStore implements McpTokenStore {
  final bool failWrites;
  final Map<String, Map<String, String>> values = {};

  _MemoryMcpTokenStore({this.failWrites = false});

  @override
  Future<void> deleteTokens(String serverName, List<String> envVarNames) async {
    final serverTokens = values[serverName];
    if (serverTokens == null) return;
    for (final name in envVarNames) {
      serverTokens.remove(name);
    }
  }

  @override
  Future<bool> hasTokens(String serverName, List<String> envVarNames) async =>
      envVarNames.isNotEmpty &&
      envVarNames.every(
        (name) => values[serverName]?[name]?.isNotEmpty == true,
      );

  @override
  Future<Map<String, String>> loadTokens(
    String serverName,
    List<String> envVarNames,
  ) async => {
    for (final name in envVarNames)
      if (values[serverName]?[name] != null) name: values[serverName]![name]!,
  };

  @override
  Future<void> replaceTokens(
    String serverName,
    List<String> envVarNames,
    Map<String, String> tokens,
  ) async {
    if (failWrites) throw StateError('Keychain unavailable');
    final serverTokens = values.putIfAbsent(serverName, () => {});
    for (final name in envVarNames) {
      final value = tokens[name]?.trim() ?? '';
      if (value.isEmpty) {
        serverTokens.remove(name);
      } else {
        serverTokens[name] = value;
      }
    }
  }

  @override
  Future<void> saveTokens(String serverName, Map<String, String> tokens) async {
    if (failWrites) throw StateError('Keychain unavailable');
    values.putIfAbsent(serverName, () => {}).addAll(tokens);
  }
}
