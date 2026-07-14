import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/agent/config/config.dart';
import 'package:circuit_ide/core/constants/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'migrates legacy plaintext credentials to secure storage and scrubs disk',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'circuit-secure-config-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = _MemoryCredentialStore();
      final file = File(p.join(directory.path, AppConstants.configFileName));
      await file.writeAsString(
        jsonEncode({
          'client_id': 'client-id',
          'client_secret': 'client-secret',
          'app_key': 'app-key',
          'github_pat': 'github-token',
          'model': 'circuit-pro',
          'auto_approve': true,
        }),
      );

      final config = await AgentConfig.load(
        credentialStore: store,
        configDirectory: directory.path,
        environment: const {},
      );

      expect(config.ciscoClientId, 'client-id');
      expect(config.ciscoClientSecret, 'client-secret');
      expect(config.ciscoAppKey, 'app-key');
      expect(config.githubPat, 'github-token');
      final persisted =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(persisted['schemaVersion'], 2);
      expect(persisted['kind'], 'circuit.agent-settings');
      final payload = persisted['payload'] as Map<String, dynamic>;
      expect(payload['auto_approve'], isTrue);
      expect(payload.keys, isNot(contains('client_id')));
      expect(payload.keys, isNot(contains('client_secret')));
      expect(payload.keys, isNot(contains('app_key')));
      expect(payload.keys, isNot(contains('github_pat')));
      expect(
        await File('${file.path}.schema-v1.backup').readAsString(),
        contains('client-secret'),
      );
      expect(await file.readAsString(), isNot(contains('client-secret')));
      expect(store.values, {
        'cisco_client_id': 'client-id',
        'cisco_client_secret': 'client-secret',
        'cisco_app_key': 'app-key',
        'github_pat': 'github-token',
      });
    },
  );

  test(
    'keeps a legacy credential file intact when secure migration fails',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'circuit-secure-config-failure-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = _MemoryCredentialStore(failWrites: true);
      final file = File(p.join(directory.path, AppConstants.configFileName));
      await file.writeAsString(
        jsonEncode({'client_secret': 'keep-until-safe'}),
      );

      await AgentConfig.load(
        credentialStore: store,
        configDirectory: directory.path,
        environment: const {},
      );

      expect(await file.readAsString(), contains('keep-until-safe'));
      expect(store.values, isEmpty);
    },
  );

  test(
    'never falls back to writing credentials when secure storage fails',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'circuit-secure-save-failure-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(p.join(directory.path, AppConstants.configFileName));
      await file.writeAsString('{"model":"unchanged"}');

      final config = AgentConfig(
        ciscoClientSecret: 'must-not-reach-disk',
        credentialStore: _MemoryCredentialStore(failWrites: true),
        configDirectory: directory.path,
      );

      await expectLater(
        config.save(),
        throwsA(isA<SecureCredentialStorageException>()),
      );
      expect(await file.readAsString(), '{"model":"unchanged"}');
    },
  );

  test(
    'leaves future-version agent settings unchanged with a recovery error',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'circuit-future-config-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(p.join(directory.path, AppConstants.configFileName));
      const future =
          '{"schemaVersion":99,"kind":"circuit.agent-settings","payload":{"model":"future"}}';
      await file.writeAsString(future);

      final config = await AgentConfig.load(
        credentialStore: _MemoryCredentialStore(),
        configDirectory: directory.path,
        environment: const {},
      );

      await expectLater(
        config.save(),
        throwsA(
          isA<SecureCredentialStorageException>().having(
            (error) => error.message,
            'message',
            contains('newer schema'),
          ),
        ),
      );
      expect(await file.readAsString(), future);
    },
  );
}

class _MemoryCredentialStore implements SecureCredentialStore {
  final bool failWrites;
  final Map<String, String> values = {};

  _MemoryCredentialStore({this.failWrites = false});

  @override
  Future<void> delete({required String key}) async {
    if (failWrites) throw StateError('Keychain unavailable');
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    if (failWrites) throw StateError('Keychain unavailable');
    values[key] = value;
  }
}
