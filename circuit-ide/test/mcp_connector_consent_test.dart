import 'dart:io';

import 'package:circuit_ide/agent/mcp/mcp_config.dart';
import 'package:circuit_ide/agent/mcp/mcp_config_storage.dart';
import 'package:circuit_ide/agent/mcp/mcp_token_storage.dart';
import 'package:circuit_ide/state/mcp_hub_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'connector revocation disables access and removes every Keychain token',
    () async {
      final root = await Directory.systemTemp.createTemp('mcp-consent-');
      addTearDown(() => root.delete(recursive: true));
      final tokens = _MemoryMcpTokenStore();
      final storage = McpConfigStorage(
        filePath: '${root.path}/mcp_servers.json',
        tokenStorage: tokens,
      );
      final config = McpServerConfig(
        name: 'github',
        url: 'http://127.0.0.1:0/mcp',
        connectorKind: McpConnectorKind.github,
        requestedScopes: McpConnectorKind.github.defaultScopes,
        dataAccessSummary: McpConnectorKind.github.defaultDataAccessSummary,
        requiredEnvVars: const ['GITHUB_TOKEN'],
        enabled: false,
        approvedAt: DateTime(2026, 7, 11),
        consentedAt: DateTime(2026, 7, 11),
      );
      await storage.save([config]);
      await tokens.saveTokens('github', {'GITHUB_TOKEN': 'private-value'});
      final container = ProviderContainer(
        overrides: [
          mcpHubProvider.overrideWith(
            () => McpHubNotifier(storage: storage, tokenStorage: tokens),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(mcpHubProvider.notifier);
      await notifier.loadAndConnect();

      await notifier.revokeServerConsent('github');

      final revoked = (await storage.load()).single;
      expect(revoked.enabled, isFalse);
      expect(revoked.approvedAt, isNull);
      expect(revoked.consentedAt, isNull);
      expect(
        await tokens.loadTokens('github', const ['GITHUB_TOKEN']),
        isEmpty,
      );
    },
  );

  test(
    'connector profiles declare user-visible scopes and access boundaries',
    () {
      expect(McpConnectorKind.webex.defaultScopes, contains('rooms:read'));
      expect(McpConnectorKind.jira.defaultDataAccessSummary, contains('Jira'));
      expect(
        McpConnectorKind.github.defaultDataAccessSummary,
        contains('GitHub'),
      );
    },
  );
}

class _MemoryMcpTokenStore implements McpTokenStore {
  final Map<String, Map<String, String>> values = {};

  @override
  Future<void> deleteTokens(String serverName, List<String> envVarNames) async {
    for (final envVar in envVarNames) {
      values[serverName]?.remove(envVar);
    }
  }

  @override
  Future<bool> hasTokens(String serverName, List<String> envVarNames) async =>
      envVarNames.isNotEmpty &&
      envVarNames.every(
        (envVar) => values[serverName]?[envVar]?.isNotEmpty == true,
      );

  @override
  Future<Map<String, String>> loadTokens(
    String serverName,
    List<String> envVarNames,
  ) async => {
    for (final envVar in envVarNames)
      if (values[serverName]?[envVar] != null)
        envVar: values[serverName]![envVar]!,
  };

  @override
  Future<void> replaceTokens(
    String serverName,
    List<String> envVarNames,
    Map<String, String> tokens,
  ) async {
    await deleteTokens(serverName, envVarNames);
    await saveTokens(serverName, tokens);
  }

  @override
  Future<void> saveTokens(String serverName, Map<String, String> tokens) async {
    values.putIfAbsent(serverName, () => {}).addAll(tokens);
  }
}
