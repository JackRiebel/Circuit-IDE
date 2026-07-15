import 'dart:io';

import 'package:flutter/foundation.dart';

import 'crash_reporting_boundary.dart';
import 'privacy_crash_reporter.dart';

/// Result retained briefly for the parent packaged-app harness to inspect.
class PackagedPrivacyCrashAuditResult {
  final Directory root;
  final File ledger;

  const PackagedPrivacyCrashAuditResult({
    required this.root,
    required this.ledger,
  });
}

/// A bounded, test-only crash boundary audit for a packaged macOS app.
///
/// It is reachable only through the native packaged-smoke launch argument.
/// No user-facing control or agent/tool route can invoke it. The audit creates
/// an opt-in temporary local ledger, verifies its redaction before termination,
/// prints only the temporary ledger path, flushes stdout, then aborts this app
/// process. The shell harness verifies the persisted ledger after that abort.
class PackagedPrivacyCrashAudit {
  static const readyMarker = 'PACKAGED_PRIVACY_CRASH_AUDIT=READY';
  static const failureMarker = 'PACKAGED_PRIVACY_CRASH_AUDIT=FAIL';
  static const _secret = 'packaged-crash-smoke-token';
  static const _prompt = 'private packaged crash customer content';

  /// The packaged smoke harness needs the exact process identity after
  /// LaunchServices drops command-line visibility. Keep this handoff limited
  /// to the process id and temporary redacted-ledger location; it never emits
  /// a prompt, token, stack, or exception value.
  static String readyLine(PackagedPrivacyCrashAuditResult audit) =>
      '$readyMarker pid=$pid ledger=${audit.ledger.path}';

  static Future<PackagedPrivacyCrashAuditResult> verify() async {
    final root = await Directory.systemTemp.createTemp(
      'circuit-packaged-privacy-crash-',
    );
    final reporter = PrivacyCrashReporter(
      isEnabled: () => true,
      directoryPath: root.path,
    );
    reporter.addBreadcrumb(
      CrashBreadcrumbEvent.turnFailed,
      metadata: {'prompt': _prompt, 'authorization': 'Bearer $_secret'},
    );
    final boundary = CrashReportingBoundary(
      reporter: reporter,
      presentFlutterError: (_) {},
    );
    final stack = StackTrace.fromString(
      '#0 packagedPrivacyCrash (/Users/example/private/project.dart:12:3) '
      'token=$_secret prompt=$_prompt',
    );
    boundary.handleFlutterError(
      FlutterErrorDetails(
        exception: StateError('prompt=$_prompt'),
        stack: stack,
      ),
    );
    _require(
      !boundary.handlePlatformError(
        StateError('authorization=Bearer $_secret'),
        stack,
      ),
      'platform_propagation',
    );

    final ledger = File(reporter.filePath);
    final persisted = await ledger.readAsString();
    _require(persisted.contains('"source":"flutter"'), 'flutter_record');
    _require(persisted.contains('"source":"platform"'), 'platform_record');
    _require(persisted.contains('[PATH]'), 'path_redaction');
    _require(
      !persisted.contains(_prompt) && !persisted.contains(_secret),
      'secret_redaction',
    );
    _require((await reporter.load()).length == 2, 'record_count');
    return PackagedPrivacyCrashAuditResult(root: root, ledger: ledger);
  }

  /// Runs the audit and deliberately terminates only this packaged test app.
  ///
  /// This method must never be called from product UI/runtime code. Its launch
  /// route is private to `verify_packaged_app_launch.sh` and uses `SIGABRT` so
  /// the parent can prove that the synchronous ledger flush survived a real
  /// process termination rather than an orderly app exit.
  static Future<void> verifyThenAbort() async {
    try {
      final audit = await verify();
      stdout.writeln(readyLine(audit));
      await stdout.flush();
      if (!Process.killPid(pid, ProcessSignal.sigabrt)) {
        exit(70);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      exit(70);
    } catch (error) {
      stdout.writeln('$failureMarker stage=${_stage(error)}');
      await stdout.flush();
      exit(1);
    }
  }

  static String _stage(Object error) =>
      error is _PackagedPrivacyAuditFailure ? error.stage : 'unexpected';

  static void _require(bool condition, String stage) {
    if (!condition) throw _PackagedPrivacyAuditFailure(stage);
  }
}

class _PackagedPrivacyAuditFailure implements Exception {
  final String stage;

  const _PackagedPrivacyAuditFailure(this.stage);
}
