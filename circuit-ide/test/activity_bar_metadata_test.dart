import 'package:circuit_ide/ui/layout/activity_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Activity bar exposes only primary destinations by default', () {
    expect(ActivityBarItem.primary, [
      ActivityBarItem.explorer,
      ActivityBarItem.search,
      ActivityBarItem.git,
      ActivityBarItem.ai,
      ActivityBarItem.runTest,
    ]);

    expect(ActivityBarItem.security.isPrimary, isFalse);
    expect(ActivityBarItem.security.group, 'Verification');
    expect(ActivityBarItem.security.commandOnlyLabel, 'Security Scan');
  });

  test(
    'advanced and hidden activity items fail closed to visible AI surface',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(activeActivityItemProvider.notifier)
          .set(ActivityBarItem.mcp);

      expect(container.read(activeActivityItemProvider), ActivityBarItem.ai);

      container
          .read(activeActivityItemProvider.notifier)
          .set(ActivityBarItem.notebook);

      expect(container.read(activeActivityItemProvider), ActivityBarItem.ai);

      container
          .read(activeActivityItemProvider.notifier)
          .set(ActivityBarItem.tools);

      expect(container.read(activeActivityItemProvider), ActivityBarItem.ai);
    },
  );
}
