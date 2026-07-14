import 'dart:io';

import 'package:circuit_ide/agent/config/config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'macOS credential configuration uses the app-owned Keychain bridge',
    () async {
      if (!Platform.isMacOS) return;

      const channel = MethodChannel('circuitcode/secure_credentials');
      final calls = <MethodCall>[];
      final values = <String, String>{};
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        final key = arguments['key'] as String;
        switch (call.method) {
          case 'read':
            return values[key];
          case 'write':
            values[key] = arguments['value'] as String;
            return null;
          case 'delete':
            values.remove(key);
            return null;
        }
        throw MissingPluginException();
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      const store = FlutterSecureCredentialStore();
      await store.write(key: 'cisco_client_id', value: 'client-id');
      expect(await store.read(key: 'cisco_client_id'), 'client-id');
      await store.delete(key: 'cisco_client_id');

      expect(calls.map((call) => call.method), ['write', 'read', 'delete']);
      expect(values, isEmpty);
    },
  );
}
