import 'package:circuit_ide/services/packaged_studio_smoke.dart';
import 'package:circuit_ide/agent/config/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'packaged Studio smoke completes a bounded local task lifecycle',
    () async {
      final result = await PackagedStudioSmoke.run();

      expect(result.passed, isTrue, reason: result.stage);
      expect(result.stage, 'ok');
    },
  );

  test(
    'packaged Studio smoke invokes its shell hook before the lifecycle',
    () async {
      var mounted = false;
      final result = await PackagedStudioSmoke.run(
        onContainerReady: (_) async {
          mounted = true;
        },
      );

      expect(mounted, isTrue);
      expect(result.passed, isTrue, reason: result.stage);
    },
  );

  test(
    'packaged Studio smoke verifies and removes its secure credential probe',
    () async {
      final store = _MemoryCredentialStore();

      final result = await PackagedStudioSmoke.run(
        secureCredentialStore: store,
        verifySecureCredentialPersistence: true,
      );

      expect(result.passed, isTrue);
      expect(store.values, isEmpty);
    },
  );
}

class _MemoryCredentialStore implements SecureCredentialStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
