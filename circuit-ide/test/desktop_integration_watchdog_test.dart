import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'strict desktop journey stops immediately after a foreground refusal',
    () async {
      if (!Platform.isMacOS) return;

      const command = r'''
flutter() {
  printf '%s\n' 'Failed to foreground app; open returned 1'
  sleep 30
}
export -f flutter
unset CIRCUIT_ALLOW_HEADLESS_DESKTOP_FALLBACK
start=$SECONDS
set +e
bash scripts/desktop_integration_suite.sh
status=$?
set -e
elapsed=$((SECONDS - start))
printf 'watchdog_status=%s elapsed_seconds=%s\n' "$status" "$elapsed"
if [[ "$status" -ne 1 || "$elapsed" -ge 5 ]]; then
  exit 1
fi
''';

      final result = await Process.run('/bin/bash', [
        '-c',
        command,
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('watchdog_status=1'));
      expect(result.stdout, contains(RegExp(r'elapsed_seconds=[0-4]\b')));
      expect(
        result.stderr,
        contains('Desktop integration journey did not foreground'),
      );
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
