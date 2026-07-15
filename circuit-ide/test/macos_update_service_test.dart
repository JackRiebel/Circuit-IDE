import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circuit_ide/services/macos_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('circuitcode/updates-test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('parses only the bounded native update status surface', () {
    final status = CircuitUpdateStatus.fromPlatform({
      'configured': true,
      'channel': 'beta',
      'automaticChecks': true,
      'automaticDownloads': true,
      'allowsAutomaticDownloads': true,
      'canCheck': true,
      'checkInProgress': false,
      'lastCheckEpochMillis': 1767225600000,
      'mutationActive': true,
      'installDeferred': true,
      'message': 'Waiting for Studio work.',
      // Native implementation must not expose a feed URL, signature, or
      // package location to Dart. Unknown fields are intentionally ignored.
      'feedUrl': 'https://untrusted.example/update.xml',
      'publicKey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    });

    expect(status.configured, isTrue);
    expect(status.channel, CircuitUpdateChannel.beta);
    expect(status.automaticChecks, isTrue);
    expect(status.lastCheckedAt, DateTime.utc(2026, 1, 1));
    expect(status.mutationActive, isTrue);
    expect(status.installDeferred, isTrue);
  });

  test(
    'routes only bounded preferences and mutation state to native Sparkle',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return {
              'configured': true,
              'channel': (call.arguments as Map?)?['channel'] ?? 'stable',
              'canCheck': true,
            };
          });
      final service = MacosUpdateService(
        channel: channel,
        isSupported: () => true,
      );

      await service.status();
      await service.setChannel(CircuitUpdateChannel.beta);
      await service.setAutomaticChecks(true);
      await service.setAutomaticDownloads(false);
      await service.setMutationActive(true);
      final status = await service.checkForUpdates();

      expect(status.configured, isTrue);
      expect(calls.map((call) => call.method), [
        'status',
        'setChannel',
        'setAutomaticChecks',
        'setAutomaticDownloads',
        'setMutationActive',
        'checkForUpdates',
      ]);
      expect(calls[1].arguments, {'channel': 'beta'});
      expect(calls[2].arguments, {'enabled': true});
      expect(calls[3].arguments, {'enabled': false});
      expect(calls[4].arguments, {'active': true});
      for (final call in calls) {
        expect(call.arguments.toString().toLowerCase(), isNot(contains('url')));
        expect(
          call.arguments.toString().toLowerCase(),
          isNot(contains('path')),
        );
        expect(call.arguments.toString().toLowerCase(), isNot(contains('key')));
      }
    },
  );

  test('fails closed when the signed update service is unavailable', () async {
    final service = MacosUpdateService(
      channel: channel,
      isSupported: () => true,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(
            code: 'not_configured',
            message: 'No signed appcast is embedded.',
          ),
        );

    final status = await service.checkForUpdates();

    expect(status.configured, isFalse);
    expect(status.canCheck, isFalse);
    expect(status.message, 'No signed appcast is embedded.');
  });

  test(
    'native update bridge enforces the automatic download prerequisite',
    () async {
      final source = await File(
        'macos/Runner/AppDelegate.swift',
      ).readAsString();

      expect(source, contains('updater.automaticallyDownloadsUpdates = false'));
      expect(
        source,
        contains('Automatic downloads require automatic update checks.'),
      );
    },
  );

  test('native updater accepts only canonical public appcast URLs', () async {
    final source = await File('macos/Runner/AppDelegate.swift').readAsString();

    expect(source, contains('let feed = URLComponents(string: feedUrl)'));
    expect(source, contains('feed.user == nil, feed.password == nil'));
    expect(source, contains('feed.query == nil, feed.fragment == nil'));
    expect(source, contains('bake credentials or per-request tokens'));
  });

  test(
    'release update verifier rejects credentialed and per-request appcast URLs',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-update-verifier-',
      );
      addTearDown(() => root.delete(recursive: true));
      final app = Directory('${root.path}/CircuitCode.app');
      final contents = Directory('${app.path}/Contents');
      await Directory(
        '${contents.path}/Frameworks/Sparkle.framework',
      ).create(recursive: true);
      final info = File('${contents.path}/Info.plist');
      final publicKey = base64Encode(List<int>.filled(32, 1));

      Future<ProcessResult> verify(String feedUrl) async {
        await info.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>SUFeedURL</key><string>$feedUrl</string>
  <key>SUPublicEDKey</key><string>$publicKey</string>
  <key>SUEnableAutomaticChecks</key><false/>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>CircuitDataSchemaVersion</key><string>1</string>
</dict></plist>''');
        return Process.run('bash', [
          'scripts/verify_update_release_configuration.sh',
          app.path,
        ]);
      }

      final valid = await verify(
        'https://updates.circuitcode.test/appcast.xml',
      );
      expect(valid.exitCode, 0, reason: valid.stderr);

      for (final invalid in [
        'https://release-token@updates.circuitcode.test/appcast.xml',
        'https://updates.circuitcode.test/appcast.xml?token=short-lived',
        'https://updates.circuitcode.test/appcast.xml#unstable',
      ]) {
        final rejected = await verify(invalid);
        expect(rejected.exitCode, isNot(0));
        expect(rejected.stderr, contains('canonical public HTTPS appcast URL'));
      }
    },
    skip: !Platform.isMacOS,
  );

  test(
    'retains configured status when a check is deferred by active Studio work',
    () async {
      final service = MacosUpdateService(
        channel: channel,
        isSupported: () => true,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw PlatformException(
              code: 'active_mutation',
              message: 'Finish active work first.',
              details: {
                'configured': true,
                'channel': 'stable',
                'canCheck': true,
                'mutationActive': true,
              },
            ),
          );

      final status = await service.checkForUpdates();

      expect(status.configured, isTrue);
      expect(status.mutationActive, isTrue);
      expect(status.message, 'Finish active work first.');
    },
  );
}
