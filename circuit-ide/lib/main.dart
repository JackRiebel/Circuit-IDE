import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/crash_reporting_boundary.dart';
import 'services/packaged_studio_smoke.dart';
import 'services/packaged_studio_smoke_launch.dart';
import 'services/packaged_release_performance_probe.dart';
import 'services/packaged_privacy_crash_audit.dart';
import 'services/privacy_crash_reporter.dart';
import 'state/settings_provider.dart';

void main() async {
  final dartMainStopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  if (await shouldRunPackagedPrivacyCrashAudit()) {
    await PackagedPrivacyCrashAudit.verifyThenAbort();
    return;
  }
  if (await shouldRunPackagedStudioSmoke()) {
    final result = await PackagedStudioSmoke.run(
      onContainerReady: _mountStudioShellForPackagedSmoke,
      verifySecureCredentialPersistence: true,
    );
    stdout.writeln(
      'PACKAGED_STUDIO_SMOKE=${result.passed ? 'PASS' : 'FAIL'}:${result.stage}',
    );
    exit(result.passed ? 0 : 1);
  }
  if (await shouldRunPackagedReleasePerformanceProbe()) {
    final result = await PackagedReleasePerformanceProbe.run(
      dartMainElapsed: dartMainStopwatch.elapsed,
      onContainerReady: _mountStudioShellForPackagedSmoke,
    );
    stdout.writeln(result.toMachineLine());
    exit(result.passed ? 0 : 1);
  }
  final container = ProviderContainer();
  _installCrashReporting(container);
  await _configureStudioWindow();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CircuitIDEApp(),
    ),
  );
}

Future<void> _mountStudioShellForPackagedSmoke(
  ProviderContainer container,
) async {
  _installCrashReporting(container);
  // The harness separately proves that a normal LaunchServices instance stays
  // visible. Its lifecycle instance only needs a real Flutter frame, so avoid
  // waiting on foreground-window presentation when CI launches it in the
  // background.
  await _configureStudioWindow(waitUntilVisible: false);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CircuitIDEApp(),
    ),
  );
  await WidgetsBinding.instance.endOfFrame.timeout(const Duration(seconds: 5));
}

void _installCrashReporting(ProviderContainer container) {
  final crashReporter = PrivacyCrashReporter(
    isEnabled: () => container.read(settingsProvider).crashReportingEnabled,
  );
  crashReporter.addBreadcrumb(
    CrashBreadcrumbEvent.appStarted,
    metadata: {'platform': Platform.operatingSystem},
  );
  CrashReportingBoundary(reporter: crashReporter).install();
}

Future<void> _configureStudioWindow({bool waitUntilVisible = true}) async {
  await windowManager.ensureInitialized();
  if (Platform.isMacOS) {
    await windowManager.setPreventClose(true);
    windowManager.addListener(_MacWindowLifecycle());
  }

  const windowOptions = WindowOptions(
    size: Size(1400, 900),
    minimumSize: Size(800, 500),
    center: true,
    title: 'CircuitCode',
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Color(0xFF1E1E1E),
  );

  if (waitUntilVisible) {
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

class _MacWindowLifecycle extends WindowListener {
  @override
  Future<void> onWindowClose() async {
    if (!Platform.isMacOS) return;
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }
}
