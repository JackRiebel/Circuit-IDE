import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/services/plugin_service.dart';
import 'package:circuit_ide/services/versioned_json_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const signerId = 'test-publisher';
  final signerKey = utf8.encode('test-publisher-key');

  test(
    'signed package lifecycle installs, disables updates, rolls back, and uninstalls',
    () async {
      final root = await Directory.systemTemp.createTemp('plugin-service-');
      addTearDown(() => root.delete(recursive: true));
      final sourceV1 = Directory('${root.path}/source-v1');
      final sourceV2 = Directory('${root.path}/source-v2');
      final packages = '${root.path}/packages';
      await _writeSignedPlugin(
        sourceV1,
        version: '1.0.0',
        signerKey: signerKey,
      );
      await _writeSignedPlugin(
        sourceV2,
        version: '1.1.0',
        signerKey: signerKey,
      );
      final service = PluginService(
        pluginPackagesDir: packages,
        trustedPublisherKeys: {signerId: signerKey},
      );

      final first = await service.installFromDirectory(sourceV1.path);

      expect(first.manifest.version, '1.0.0');
      expect(first.enabled, isFalse);
      await service.setEnabled('review-pack', true);
      expect(service.plugins.single.enabled, isTrue);

      final updated = await service.installFromDirectory(sourceV2.path);

      expect(updated.manifest.version, '1.1.0');
      expect(updated.enabled, isFalse);
      expect(
        await Directory(packages)
            .list()
            .where((entity) => entity is Directory)
            .any((entity) => entity.path.contains('review-pack.backup-')),
        isTrue,
      );

      await service.rollback('review-pack');

      expect(service.plugins.single.manifest.version, '1.0.0');
      expect(service.plugins.single.enabled, isTrue);
      await service.uninstall('review-pack');
      expect(await Directory('$packages/review-pack').exists(), isFalse);
      expect(
        await Directory(packages)
            .list()
            .where((entity) => entity is Directory)
            .any((entity) => entity.path.contains('review-pack.backup-')),
        isFalse,
      );
    },
  );

  test('tampered and untrusted packages never install', () async {
    final root = await Directory.systemTemp.createTemp('plugin-tamper-');
    addTearDown(() => root.delete(recursive: true));
    final source = Directory('${root.path}/source');
    await _writeSignedPlugin(source, version: '1.0.0', signerKey: signerKey);
    final manifestFile = File('${source.path}/manifest.json');
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final payload = manifest['payload'] as Map<String, dynamic>;
    payload['description'] = 'tampered after signing';
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    final service = PluginService(
      pluginPackagesDir: '${root.path}/packages',
      trustedPublisherKeys: {signerId: signerKey},
    );

    await expectLater(
      service.installFromDirectory(source.path),
      throwsA(isA<PluginSignatureException>()),
    );
    expect(
      await Directory('${root.path}/packages/review-pack').exists(),
      isFalse,
    );
  });

  test('legacy unsigned packages migrate to a quarantined manifest', () async {
    final root = await Directory.systemTemp.createTemp('plugin-legacy-');
    addTearDown(() => root.delete(recursive: true));
    final plugin = Directory('${root.path}/packages/legacy-pack');
    await plugin.create(recursive: true);
    final manifestFile = File('${plugin.path}/manifest.json');
    const legacy =
        '{"id":"legacy-pack","name":"Legacy pack","version":"1.0.0"}';
    await manifestFile.writeAsString(legacy);
    final service = PluginService(
      pluginPackagesDir: '${root.path}/packages',
      trustedPublisherKeys: {signerId: signerKey},
    );

    await service.loadPlugins();

    expect(service.plugins, isEmpty);
    expect(
      await File('${manifestFile.path}.schema-v1.backup').readAsString(),
      legacy,
    );
    final migrated =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    expect(migrated['kind'], PluginManifest.kind);
    expect(migrated['schemaVersion'], PluginManifest.schemaVersion);
    expect(
      (migrated['payload'] as Map<String, dynamic>)['signature']['algorithm'],
      'untrusted-legacy',
    );
  });
}

Future<void> _writeSignedPlugin(
  Directory directory, {
  required String version,
  required List<int> signerKey,
}) async {
  await directory.create(recursive: true);
  const files = [
    'agents/reviewer.agent.json',
    'skills/review.md',
    'connectors/review.json',
    'mcp/review.json',
    'commands/review.json',
    'artifacts/review.json',
    'hooks/on-install.json',
  ];
  for (final path in files) {
    final file = File('${directory.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString('{"path":"$path"}');
  }
  final payload = <String, dynamic>{
    'id': 'review-pack',
    'name': 'Review pack',
    'version': version,
    'description': 'A signed package for review workflows.',
    'author': 'Test Publisher',
    'components': {
      'agents': ['agents/reviewer.agent.json'],
      'skills': ['skills/review.md'],
      'connectors': ['connectors/review.json'],
      'mcpServers': ['mcp/review.json'],
      'commands': ['commands/review.json'],
      'artifactTemplates': ['artifacts/review.json'],
      'hooks': ['hooks/on-install.json'],
    },
  };
  final signature = PluginSignature(
    algorithm: PluginSignature.algorithmHmacSha256,
    signerId: 'test-publisher',
    value: PluginPackageSigner.signPayload(payload, signerKey),
  );
  payload['signature'] = signature.toJson();
  final document = VersionedJsonDocument(
    kind: PluginManifest.kind,
    schemaVersion: PluginManifest.schemaVersion,
    payload: payload,
  );
  await File(
    '${directory.path}/manifest.json',
  ).writeAsString(document.encode(pretty: true));
}
