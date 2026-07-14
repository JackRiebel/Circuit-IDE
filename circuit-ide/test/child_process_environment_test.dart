import 'package:circuit_ide/agent/security/child_process_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('child processes receive only an allowlisted base environment', () {
    final environment = ChildProcessEnvironment.build(
      baseEnvironment: const {
        'PATH': '/usr/bin',
        'HOME': '/tmp/circuit-home',
        'LANG': 'en_US.UTF-8',
        'CIRCUIT_CLIENT_SECRET': 'ambient-secret',
        'OPENAI_API_KEY': 'ambient-api-key',
        'UNRELATED_INTERNAL_FLAG': 'must-not-leak',
      },
      injected: const {
        'GITHUB_TOKEN': 'connector-grant',
        'LD_PRELOAD': '/tmp/unsafe.dylib',
      },
      fixed: const {'PORT': '8042'},
    );

    expect(environment['PATH'], '/usr/bin');
    expect(environment['HOME'], '/tmp/circuit-home');
    expect(environment['GITHUB_TOKEN'], 'connector-grant');
    expect(environment['PORT'], '8042');
    expect(environment['TERM'], 'dumb');
    expect(environment, isNot(contains('CIRCUIT_CLIENT_SECRET')));
    expect(environment, isNot(contains('OPENAI_API_KEY')));
    expect(environment, isNot(contains('UNRELATED_INTERNAL_FLAG')));
    expect(environment, isNot(contains('LD_PRELOAD')));
  });

  test('redacts connector tokens and common secret-shaped child output', () {
    final output = ChildProcessEnvironment.redactOutput(
      'token=connector-grant\npassword: exposed\nplain connector-grant',
      const ['connector-grant'],
    );

    expect(output, isNot(contains('connector-grant')));
    expect(output, isNot(contains('exposed')));
    expect(output, contains('[REDACTED]'));
  });
}
