import 'package:circuit_ide/services/packaged_privacy_crash_audit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'packaged privacy crash audit flushes only redacted boundary records',
    () async {
      final audit = await PackagedPrivacyCrashAudit.verify();
      addTearDown(() => audit.root.delete(recursive: true));

      expect(await audit.ledger.exists(), isTrue);
      final persisted = await audit.ledger.readAsString();
      expect(persisted, contains('"source":"flutter"'));
      expect(persisted, contains('"source":"platform"'));
      expect(persisted, contains('[PATH]'));
      expect(
        persisted,
        isNot(contains('private packaged crash customer content')),
      );
      expect(persisted, isNot(contains('packaged-crash-smoke-token')));
      final ready = PackagedPrivacyCrashAudit.readyLine(audit);
      expect(ready, startsWith('PACKAGED_PRIVACY_CRASH_AUDIT=READY pid='));
      expect(ready, contains(' ledger=${audit.ledger.path}'));
      expect(ready, isNot(contains('packaged-crash-smoke-token')));
    },
  );
}
