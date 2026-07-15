import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/services/release_performance_baseline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baselineJson = {
    'schemaVersion': 1,
    'reference': {
      'hardwareModel': 'Mac16,7',
      'architecture': 'arm64',
      'macosMajorVersion': 26,
      'fixtureRevision': 'fixture-a',
      'minimumSampleCount': 5,
    },
    'baselineP95': {
      'dartMainToFirstFrameMilliseconds': 100,
      'streamFrameTotalP95Milliseconds': 10,
    },
    'maximumP95': {
      'dartMainToFirstFrameMilliseconds': 2500,
      'streamFrameTotalP95Milliseconds': 17,
    },
    'minimumP95': {'streamFrameTimingSampleCount': 5},
  };

  Map<String, Object?> series({
    String hardwareModel = 'Mac16,7',
    int launchP95 = 100,
    int streamFrames = 12,
  }) => {
    'sampleCount': 5,
    'metadata': {
      'hardwareModel': hardwareModel,
      'architecture': 'arm64',
      'macosVersion': '26.5.2',
      'fixtureRevision': 'fixture-a',
    },
    'p95': {
      'dartMainToFirstFrameMilliseconds': launchP95,
      'streamFrameTotalP95Milliseconds': 10,
      'streamFrameTimingSampleCount': streamFrames,
    },
  };

  test('applies matching hardware-scoped packaged performance limits', () {
    final baseline = PackagedReleasePerformanceBaseline.fromJson(baselineJson);
    final result = baseline.evaluate(series());

    expect(result.applicable, isTrue);
    expect(result.passed, isTrue);
    expect(result.breaches, isEmpty);
  });

  test(
    'skips a baseline on a different machine instead of comparing noise',
    () {
      final baseline = PackagedReleasePerformanceBaseline.fromJson(
        baselineJson,
      );
      final result = baseline.evaluate(series(hardwareModel: 'Mac15,4'));

      expect(result.applicable, isFalse);
      expect(result.passed, isTrue);
      expect(result.reason, contains('Mac16,7'));
    },
  );

  test('reports a matching-machine p95 or sample-count regression', () {
    final baseline = PackagedReleasePerformanceBaseline.fromJson(baselineJson);
    final result = baseline.evaluate(series(launchP95: 2600, streamFrames: 4));

    expect(result.applicable, isTrue);
    expect(result.passed, isFalse);
    expect(
      result.breaches,
      contains('dartMainToFirstFrameMilliseconds p95 2600 exceeds 2500'),
    );
    expect(
      result.breaches,
      contains('streamFrameTimingSampleCount p95 4 is below 5'),
    );
  });

  test(
    'rejects incomplete, impossible, or unknown retained baseline metrics',
    () {
      final incomplete = {
        ...baselineJson,
        'baselineP95': {'dartMainToFirstFrameMilliseconds': 100},
      };
      final impossible = {
        ...baselineJson,
        'baselineP95': {
          'dartMainToFirstFrameMilliseconds': 2600,
          'streamFrameTotalP95Milliseconds': 10,
        },
      };
      final unknown = {
        ...baselineJson,
        'maximumP95': {
          'dartMainToFirstFrameMilliseconds': 2500,
          'unknownMetric': 17,
        },
      };

      expect(
        () => PackagedReleasePerformanceBaseline.fromJson(incomplete),
        throwsFormatException,
      );
      expect(
        () => PackagedReleasePerformanceBaseline.fromJson(impossible),
        throwsFormatException,
      );
      expect(
        () => PackagedReleasePerformanceBaseline.fromJson(unknown),
        throwsFormatException,
      );
    },
  );

  test('checked-in reference baseline parses with explicit limits', () {
    final fixture = jsonDecode(
      File(
        'test/fixtures/release_performance_baseline_macos_arm64.json',
      ).readAsStringSync(),
    );
    final baseline = PackagedReleasePerformanceBaseline.fromJson(fixture);

    expect(baseline.hardwareModel, 'Mac16,7');
    expect(
      baseline.baselineP95['projectRecoveryAndMetadata500Milliseconds'],
      191,
    );
    expect(
      baseline.maximumP95['projectRecoveryAndMetadata500Milliseconds'],
      5000,
    );
    expect(baseline.maximumP95['streamFrameTotalP95Milliseconds'], 17);
    expect(baseline.minimumP95['streamFrameTimingSampleCount'], 5);
  });

  test(
    'release-series collector uses a macOS-valid temporary summary template',
    () {
      final script = File(
        'scripts/verify_release_performance_series.sh',
      ).readAsStringSync();

      expect(script, contains('circuit-release-performance-summary.XXXXXX")'));
      expect(
        script,
        isNot(contains('circuit-release-performance-summary.XXXXXX.json')),
      );
    },
  );
}
