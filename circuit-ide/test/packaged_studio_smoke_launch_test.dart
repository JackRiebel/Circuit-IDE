import 'package:circuit_ide/services/packaged_studio_smoke_launch.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'packaged smoke accepts only its explicit environment or launch switch',
    () {
      expect(
        hasPackagedStudioSmokeLaunchRequest(
          environment: const {'CIRCUITCODE_PACKAGED_SMOKE': '1'},
          executableArguments: const [],
        ),
        isTrue,
      );
      expect(
        hasPackagedStudioSmokeLaunchRequest(
          environment: const {},
          executableArguments: const [packagedStudioSmokeLaunchArgument],
        ),
        isTrue,
      );
      expect(
        hasPackagedStudioSmokeLaunchRequest(
          environment: const {'CIRCUITCODE_PACKAGED_SMOKE': '0'},
          executableArguments: const ['--circuitcode-packaged-smoke-extra'],
        ),
        isFalse,
      );
    },
  );

  test(
    'macOS launch signal is checked only when no local switch is present',
    () async {
      var nativeCalls = 0;
      final nativeRequested = await shouldRunPackagedStudioSmoke(
        environment: const {},
        executableArguments: const [],
        isMacOS: true,
        nativeRequest: () async {
          nativeCalls += 1;
          return true;
        },
      );
      final commandLineRequested = await shouldRunPackagedStudioSmoke(
        environment: const {},
        executableArguments: const [packagedStudioSmokeLaunchArgument],
        isMacOS: true,
        nativeRequest: () async {
          nativeCalls += 1;
          return false;
        },
      );

      expect(nativeRequested, isTrue);
      expect(commandLineRequested, isTrue);
      expect(nativeCalls, 1);
    },
  );

  test('retries only the transient native host-registration race', () async {
    var calls = 0;
    final requested = await shouldRunPackagedStudioSmoke(
      environment: const {},
      executableArguments: const [],
      isMacOS: true,
      nativeRequest: () async {
        calls += 1;
        if (calls == 1) throw MissingPluginException('host is starting');
        return true;
      },
    );

    expect(requested, isTrue);
    expect(calls, 2);
  });

  test(
    'packaged privacy crash audit requires its own explicit launch signal',
    () async {
      expect(
        hasPackagedPrivacyCrashAuditLaunchRequest(
          environment: const {'CIRCUITCODE_PACKAGED_PRIVACY_CRASH': '1'},
          executableArguments: const [],
        ),
        isTrue,
      );
      expect(
        hasPackagedPrivacyCrashAuditLaunchRequest(
          environment: const {},
          executableArguments: const [packagedPrivacyCrashAuditLaunchArgument],
        ),
        isTrue,
      );
      expect(
        await shouldRunPackagedPrivacyCrashAudit(
          environment: const {},
          executableArguments: const [],
          isMacOS: true,
          nativeRequest: () async => true,
        ),
        isTrue,
      );
      expect(
        await shouldRunPackagedPrivacyCrashAudit(
          environment: const {},
          executableArguments: const [],
          isMacOS: false,
        ),
        isFalse,
      );
    },
  );

  test(
    'packaged release performance probe requires its own launch signal',
    () async {
      expect(
        hasPackagedReleasePerformanceProbeLaunchRequest(
          environment: const {'CIRCUITCODE_PACKAGED_PERFORMANCE_PROBE': '1'},
          executableArguments: const [],
        ),
        isTrue,
      );
      expect(
        hasPackagedReleasePerformanceProbeLaunchRequest(
          environment: const {},
          executableArguments: const [
            packagedReleasePerformanceProbeLaunchArgument,
          ],
        ),
        isTrue,
      );
      expect(
        await shouldRunPackagedReleasePerformanceProbe(
          environment: const {},
          executableArguments: const [],
          isMacOS: true,
          nativeRequest: () async => true,
        ),
        isTrue,
      );
      expect(
        await shouldRunPackagedReleasePerformanceProbe(
          environment: const {},
          executableArguments: const [],
          isMacOS: false,
        ),
        isFalse,
      );
    },
  );
}
