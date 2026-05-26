import 'package:circuit_ide/ui/layout/activity_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Activity bar exposes only primary destinations by default', () {
    expect(ActivityBarItem.primary, [
      ActivityBarItem.explorer,
      ActivityBarItem.search,
      ActivityBarItem.git,
      ActivityBarItem.ai,
      ActivityBarItem.runTest,
      ActivityBarItem.tools,
    ]);

    expect(ActivityBarItem.security.isPrimary, isFalse);
    expect(ActivityBarItem.security.group, 'Verification');
    expect(ActivityBarItem.security.commandOnlyLabel, 'Security Scan');
  });
}
