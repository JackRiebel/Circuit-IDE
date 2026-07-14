import 'package:flutter/foundation.dart';

import 'privacy_crash_reporter.dart';

/// Installs the narrow Flutter/runtime boundary for the local crash ledger.
///
/// A boundary writes synchronously because an unhandled platform error can end
/// the process before an asynchronous diagnostic task flushes. The reporter
/// remains opt-in, local-only, and redacts the record before any disk access.
class CrashReportingBoundary {
  final PrivacyCrashReporter reporter;
  final void Function(FlutterErrorDetails) presentFlutterError;

  CrashReportingBoundary({
    required this.reporter,
    void Function(FlutterErrorDetails)? presentFlutterError,
  }) : presentFlutterError = presentFlutterError ?? FlutterError.presentError;

  void install() {
    FlutterError.onError = handleFlutterError;
    PlatformDispatcher.instance.onError = handlePlatformError;
  }

  void handleFlutterError(FlutterErrorDetails details) {
    presentFlutterError(details);
    reporter.recordSync(
      error: details.exception,
      stackTrace: details.stack ?? StackTrace.current,
      source: 'flutter',
    );
  }

  bool handlePlatformError(Object error, StackTrace stackTrace) {
    reporter.recordSync(
      error: error,
      stackTrace: stackTrace,
      source: 'platform',
    );
    // Preserve the normal Flutter/platform unhandled-error path after the
    // privacy-safe local ledger has been flushed.
    return false;
  }
}
