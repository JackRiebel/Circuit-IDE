import 'dart:io';

import 'package:flutter/services.dart';

/// Non-user-facing launch switch used only by the packaged-app smoke harness.
///
/// A command-line switch lets the macOS harness start the app through
/// LaunchServices, instead of running its GUI executable directly from a shell.
const packagedStudioSmokeLaunchArgument = '--circuitcode-packaged-smoke';
const packagedPrivacyCrashAuditLaunchArgument =
    '--circuitcode-packaged-privacy-crash';
const packagedReleasePerformanceProbeLaunchArgument =
    '--circuitcode-packaged-performance-probe';
const _packagedStudioSmokeChannel = MethodChannel('circuitcode/packaged_smoke');
const _nativeLaunchRequestAttempts = 6;
const _nativeLaunchRequestRetryDelay = Duration(milliseconds: 50);

bool hasPackagedStudioSmokeLaunchRequest({
  Map<String, String>? environment,
  List<String>? executableArguments,
}) {
  final resolvedEnvironment = environment ?? Platform.environment;
  final resolvedArguments = executableArguments ?? Platform.executableArguments;
  return resolvedEnvironment['CIRCUITCODE_PACKAGED_SMOKE'] == '1' ||
      resolvedArguments.contains(packagedStudioSmokeLaunchArgument);
}

Future<bool> shouldRunPackagedStudioSmoke({
  Map<String, String>? environment,
  List<String>? executableArguments,
  bool? isMacOS,
  Future<bool?> Function()? nativeRequest,
}) async {
  if (hasPackagedStudioSmokeLaunchRequest(
    environment: environment,
    executableArguments: executableArguments,
  )) {
    return true;
  }
  if (!(isMacOS ?? Platform.isMacOS)) return false;
  return _requestNativeLaunchFlag(nativeRequest ?? _nativeSmokeLaunchRequested);
}

Future<bool?> _nativeSmokeLaunchRequested() =>
    _packagedStudioSmokeChannel.invokeMethod<bool>('isRequested');

bool hasPackagedPrivacyCrashAuditLaunchRequest({
  Map<String, String>? environment,
  List<String>? executableArguments,
}) {
  final resolvedEnvironment = environment ?? Platform.environment;
  final resolvedArguments = executableArguments ?? Platform.executableArguments;
  return resolvedEnvironment['CIRCUITCODE_PACKAGED_PRIVACY_CRASH'] == '1' ||
      resolvedArguments.contains(packagedPrivacyCrashAuditLaunchArgument);
}

Future<bool> shouldRunPackagedPrivacyCrashAudit({
  Map<String, String>? environment,
  List<String>? executableArguments,
  bool? isMacOS,
  Future<bool?> Function()? nativeRequest,
}) async {
  if (hasPackagedPrivacyCrashAuditLaunchRequest(
    environment: environment,
    executableArguments: executableArguments,
  )) {
    return true;
  }
  if (!(isMacOS ?? Platform.isMacOS)) return false;
  return _requestNativeLaunchFlag(
    nativeRequest ?? _nativePrivacyCrashAuditRequested,
  );
}

/// Dart can start before AppKit finishes publishing this app-owned channel.
/// Retry only that bounded missing-plugin race. Other platform failures remain
/// fail-closed, and neither route is exposed outside the packaged test harness.
Future<bool> _requestNativeLaunchFlag(
  Future<bool?> Function() nativeRequest,
) async {
  for (var attempt = 0; attempt < _nativeLaunchRequestAttempts; attempt++) {
    try {
      return await nativeRequest() ?? false;
    } on MissingPluginException {
      if (attempt == _nativeLaunchRequestAttempts - 1) return false;
      await Future<void>.delayed(_nativeLaunchRequestRetryDelay);
    } on PlatformException {
      return false;
    }
  }
  return false;
}

Future<bool?> _nativePrivacyCrashAuditRequested() =>
    _packagedStudioSmokeChannel.invokeMethod<bool>('isPrivacyCrashRequested');

bool hasPackagedReleasePerformanceProbeLaunchRequest({
  Map<String, String>? environment,
  List<String>? executableArguments,
}) {
  final resolvedEnvironment = environment ?? Platform.environment;
  final resolvedArguments = executableArguments ?? Platform.executableArguments;
  return resolvedEnvironment['CIRCUITCODE_PACKAGED_PERFORMANCE_PROBE'] == '1' ||
      resolvedArguments.contains(packagedReleasePerformanceProbeLaunchArgument);
}

Future<bool> shouldRunPackagedReleasePerformanceProbe({
  Map<String, String>? environment,
  List<String>? executableArguments,
  bool? isMacOS,
  Future<bool?> Function()? nativeRequest,
}) async {
  if (hasPackagedReleasePerformanceProbeLaunchRequest(
    environment: environment,
    executableArguments: executableArguments,
  )) {
    return true;
  }
  if (!(isMacOS ?? Platform.isMacOS)) return false;
  return _requestNativeLaunchFlag(
    nativeRequest ?? _nativeReleasePerformanceProbeRequested,
  );
}

Future<bool?> _nativeReleasePerformanceProbeRequested() =>
    _packagedStudioSmokeChannel.invokeMethod<bool>(
      'isPerformanceProbeRequested',
    );
