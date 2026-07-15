import 'package:circuit_ide/services/macos_file_open_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/file_open');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'drains launch-time native open requests in their original order',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'drainOpenRequests');
            return [
              {'path': '/tmp/project', 'isDirectory': true},
              {'path': '/tmp/project/lib/main.dart', 'isDirectory': false},
            ];
          });
      final received = <MacosFileOpenRequest>[];
      final service = MacosFileOpenService(
        channel: channel,
        isSupported: () => true,
      );

      await service.start(received.add);

      expect(received, hasLength(2));
      expect(received.first.path, '/tmp/project');
      expect(received.first.isDirectory, isTrue);
      expect(received.last.path, '/tmp/project/lib/main.dart');
      expect(received.last.isDirectory, isFalse);
      await service.dispose();
    },
  );

  test('delivers later open events and ignores malformed payloads', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'drainOpenRequests');
          return const <Object?>[];
        });
    final received = <MacosFileOpenRequest>[];
    final service = MacosFileOpenService(
      channel: channel,
      isSupported: () => true,
    );
    await service.start(received.add);

    await service.handleNativeCall(
      const MethodCall('open', {
        'path': '/tmp/project/README.md',
        'isDirectory': false,
      }),
    );
    await service.handleNativeCall(const MethodCall('open', {'path': ' '}));
    await service.handleNativeCall(const MethodCall('unsupported'));

    expect(received, hasLength(1));
    expect(received.single.path, '/tmp/project/README.md');
    expect(received.single.isDirectory, isFalse);
    await service.dispose();
  });

  test('retries only a late native channel registration', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          attempts += 1;
          expect(call.method, 'drainOpenRequests');
          if (attempts == 1) throw MissingPluginException('host is starting');
          return const <Object?>[];
        });
    final service = MacosFileOpenService(
      channel: channel,
      isSupported: () => true,
    );

    await service.start((_) {});

    expect(attempts, 2);
    await service.dispose();
  });

  test('does not install a channel receiver outside macOS', () async {
    final service = MacosFileOpenService(
      channel: channel,
      isSupported: () => false,
    );
    await service.start((_) {});
    await service.handleNativeCall(
      const MethodCall('open', {'path': '/tmp/project', 'isDirectory': true}),
    );
    await service.dispose();
  });
}
