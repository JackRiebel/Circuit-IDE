import 'dart:io';

import 'package:circuit_ide/services/provider_staging_probe.dart';
import 'package:circuit_ide/services/vision_staging_probe.dart';

/// Protected staging-only vision acceptance command. Its one JSON result is
/// redacted by construction and safe to retain as release evidence.
Future<void> main() async {
  try {
    final config = ProviderStagingProbeConfig.fromEnvironment(
      Platform.environment,
    );
    final result = await VisionStagingProbe(config: config).run();
    stdout.writeln('VISION_STAGING_PROBE=${result.toRedactedJsonLine()}');
  } on ProviderStagingProbeFailure catch (error) {
    stderr.writeln('Vision staging probe failed: ${error.message}');
    exitCode = 1;
  } catch (_) {
    stderr.writeln('Vision staging probe failed before validation completed.');
    exitCode = 1;
  }
}
