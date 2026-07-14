import 'package:circuit_ide/agent/config/ssl_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy SSL verification switches fail closed', () {
    final config = SSLConfig.fromEnvironment(
      environment: const {
        'CIRCUIT_SSL_VERIFY': 'false',
        'CIRCUIT_CA_BUNDLE': '/fixtures/private-ca.pem',
      },
    );

    expect(config.verify, isTrue);
    expect(config.caBundlePath, '/fixtures/private-ca.pem');
  });

  test(
    'an explicit legacy request cannot disable certificate verification',
    () {
      const config = SSLConfig(verify: false);

      expect(config.verify, isTrue);
      config.createHttpClient().close(force: true);
    },
  );
}
