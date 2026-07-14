import 'package:circuit_ide/services/packaged_studio_smoke.dart';
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
}
