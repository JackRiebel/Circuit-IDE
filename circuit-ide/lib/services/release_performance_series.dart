import 'dart:convert';

const packagedReleasePerformanceMetricNames = <String>[
  'dartMainToFirstFrameMilliseconds',
  'projectBindMilliseconds',
  'firstStreamFrameMilliseconds',
  'streamTenThousandDeltaBurstMilliseconds',
  'streamTenThousandDeltaStateUpdates',
  'taskSwitchMilliseconds',
  'durableReloadMilliseconds',
  'taskSummaryPage5000Milliseconds',
  'threadSummaryPage1000Milliseconds',
  'threadHydration1000Milliseconds',
  'projectRecoveryAndMetadata500Milliseconds',
  'semanticIndexRebuild1200Milliseconds',
  'durableCheckpointPersistenceMilliseconds',
  'residentSetBytes',
  'streamFrameTimingSampleCount',
  'streamFrameBuildP95Milliseconds',
  'streamFrameRasterP95Milliseconds',
  'streamFrameTotalP95Milliseconds',
  'transcriptScrollFrameTimingSampleCount',
  'transcriptScrollFrameBuildP95Milliseconds',
  'transcriptScrollFrameRasterP95Milliseconds',
  'transcriptScrollFrameTotalP95Milliseconds',
];

/// One redacted result from the packaged LaunchServices performance probe.
///
/// The parser intentionally accepts only the probe's fixed numeric schema so
/// that a release series cannot accidentally retain a prompt, workspace path,
/// or provider payload in its aggregate report.
class PackagedReleasePerformanceSample {
  final Map<String, int> metrics;

  const PackagedReleasePerformanceSample._(this.metrics);

  factory PackagedReleasePerformanceSample.parse(String input) {
    const prefix = 'PACKAGED_RELEASE_PERFORMANCE=';
    final payload = input.trim().startsWith(prefix)
        ? input.trim().substring(prefix.length)
        : input.trim();
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw const FormatException('Probe sample must be a JSON object.');
    }
    if (decoded['passed'] != true || decoded['stage'] != 'ok') {
      throw const FormatException(
        'Probe sample did not report a successful stage.',
      );
    }
    final metrics = <String, int>{};
    for (final name in packagedReleasePerformanceMetricNames) {
      final value = decoded[name];
      if (value is! num ||
          !value.isFinite ||
          value < 0 ||
          value != value.round()) {
        throw FormatException('Probe sample has invalid $name.');
      }
      metrics[name] = value.toInt();
    }
    return PackagedReleasePerformanceSample._(metrics);
  }
}

/// Redacted statistical summary for repeatable packaged Release evidence.
class PackagedReleasePerformanceSeries {
  final List<PackagedReleasePerformanceSample> samples;

  const PackagedReleasePerformanceSeries(this.samples)
    : assert(
        samples.length >= 5,
        'At least five release samples are required.',
      );

  factory PackagedReleasePerformanceSeries.parseLines(Iterable<String> lines) {
    final samples = [
      for (final line in lines)
        if (line.trim().isNotEmpty)
          PackagedReleasePerformanceSample.parse(line),
    ];
    if (samples.length < 5) {
      throw const FormatException(
        'At least five successful release samples are required.',
      );
    }
    return PackagedReleasePerformanceSeries(samples);
  }

  Map<String, Object> toJson() {
    return {
      'schemaVersion': 1,
      'sampleCount': samples.length,
      'minimum': _byMetric((values) => values.first),
      'median': _byMetric(_median),
      'p95': _byMetric(_p95),
      'maximum': _byMetric((values) => values.last),
      'samples': [for (final sample in samples) sample.metrics],
    };
  }

  Map<String, num> _byMetric(num Function(List<int>) reducer) {
    return {
      for (final name in packagedReleasePerformanceMetricNames)
        name: reducer(
          ([for (final sample in samples) sample.metrics[name]!])..sort(),
        ),
    };
  }

  static num _median(List<int> values) {
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2;
  }

  static int _p95(List<int> values) {
    final nearestRank = (values.length * 0.95).ceil();
    return values[nearestRank - 1];
  }
}
