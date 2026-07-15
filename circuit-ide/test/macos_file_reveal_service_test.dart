import 'package:circuit_ide/services/macos_file_reveal_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/file_reveal');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reveals only a non-empty path through the local native channel',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return true;
          });
      final service = MacosFileRevealService(
        channel: channel,
        isSupported: () => true,
      );

      expect(await service.reveal(' /tmp/brief.pdf '), isTrue);
      expect(received?.method, 'reveal');
      expect(received?.arguments, {'path': '/tmp/brief.pdf'});
      expect(await service.reveal('  '), isFalse);
    },
  );

  test('falls back safely when the local channel is unavailable', () async {
    final service = MacosFileRevealService(
      channel: channel,
      isSupported: () => true,
    );

    expect(await service.reveal('/tmp/brief.pdf'), isFalse);
    expect(
      await MacosFileRevealService(
        channel: channel,
        isSupported: () => false,
      ).reveal('/tmp/brief.pdf'),
      isFalse,
    );
  });
}
