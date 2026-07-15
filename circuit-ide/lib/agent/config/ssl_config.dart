import 'dart:io';

import '../../core/utils/logger.dart';

class SSLConfig {
  /// This is deliberately always true. The constructor retains the legacy
  /// named parameter so older callers continue to compile, but no runtime
  /// configuration is allowed to opt an outbound client into accepting an
  /// invalid certificate.
  final bool verify;
  final String? caBundlePath;

  const SSLConfig({bool verify = true, this.caBundlePath}) : verify = true;

  static SSLConfig fromEnvironment({Map<String, String>? environment}) {
    final values = environment ?? Platform.environment;
    final sslVerify = values['CIRCUIT_SSL_VERIFY'];
    final caBundle = values['CIRCUIT_CA_BUNDLE'];

    if (sslVerify != null &&
        ['false', '0', 'no'].contains(sslVerify.toLowerCase())) {
      Logger.warning(
        'Ignoring CIRCUIT_SSL_VERIFY: certificate verification is always required.',
      );
    }

    return SSLConfig(caBundlePath: caBundle);
  }

  /// TLS verification uses the platform trust store. Callers that need a
  /// private CA must use a reviewed platform-managed trust configuration;
  /// this app never installs a global accept-all callback.
  HttpClient createHttpClient() => HttpClient();
}
