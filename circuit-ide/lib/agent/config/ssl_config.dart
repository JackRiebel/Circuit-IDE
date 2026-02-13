import 'dart:io';

import '../../core/utils/logger.dart';

class SSLConfig {
  final bool verify;
  final String? caBundlePath;

  const SSLConfig({
    this.verify = true,
    this.caBundlePath,
  });

  static SSLConfig fromEnvironment() {
    final sslVerify = Platform.environment['CIRCUIT_SSL_VERIFY'];
    final caBundle = Platform.environment['CIRCUIT_CA_BUNDLE'];

    final verify = sslVerify == null ||
        !['false', '0', 'no'].contains(sslVerify.toLowerCase());

    if (!verify) {
      Logger.warning('SSL verification disabled via CIRCUIT_SSL_VERIFY');
    }

    return SSLConfig(
      verify: verify,
      caBundlePath: caBundle,
    );
  }

  HttpClient createHttpClient() {
    final client = HttpClient();
    if (!verify) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }
}
