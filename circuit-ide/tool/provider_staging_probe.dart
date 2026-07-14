import 'dart:io';

import 'package:circuit_ide/services/provider_staging_probe.dart';

/// Runs only when a protected staging environment explicitly supplies the
/// required values. The output is one redacted JSON line suitable for a CI
/// artifact or a release-readiness evidence link.
Future<void> main() async {
  try {
    final config = ProviderStagingProbeConfig.fromEnvironment(
      Platform.environment,
    );
    final result = await ProviderStagingProbe(config: config).run();
    stdout.writeln('PROVIDER_STAGING_PROBE=${result.toRedactedJsonLine()}');
  } on ProviderStagingProbeFailure catch (error) {
    stderr.writeln('Provider staging probe failed: ${error.message}');
    exitCode = 1;
  } catch (_) {
    stderr.writeln(
      'Provider staging probe failed before validation completed.',
    );
    exitCode = 1;
  }
}
