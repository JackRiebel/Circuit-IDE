import 'release_performance_series.dart';

class PackagedReleasePerformanceBaseline {
  static const schemaVersion = 1;

  final String hardwareModel;
  final String architecture;
  final int macosMajorVersion;
  final String fixtureRevision;
  final int minimumSampleCount;
  final Map<String, int> baselineP95;
  final Map<String, int> maximumP95;
  final Map<String, int> minimumP95;

  const PackagedReleasePerformanceBaseline({
    required this.hardwareModel,
    required this.architecture,
    required this.macosMajorVersion,
    required this.fixtureRevision,
    required this.minimumSampleCount,
    required this.baselineP95,
    required this.maximumP95,
    required this.minimumP95,
  });

  factory PackagedReleasePerformanceBaseline.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'Release performance baseline must be a map.',
      );
    }
    final map = Map<String, Object?>.from(value);
    if (map['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported release performance baseline.');
    }
    final reference = map['reference'];
    if (reference is! Map) {
      throw const FormatException(
        'Release performance baseline lacks reference.',
      );
    }
    final referenceMap = Map<String, Object?>.from(reference);
    final baseline = PackagedReleasePerformanceBaseline(
      hardwareModel: _requiredString(referenceMap, 'hardwareModel'),
      architecture: _requiredString(referenceMap, 'architecture'),
      macosMajorVersion: _requiredInt(referenceMap, 'macosMajorVersion'),
      fixtureRevision: _requiredString(referenceMap, 'fixtureRevision'),
      minimumSampleCount: _requiredInt(referenceMap, 'minimumSampleCount'),
      baselineP95: _metricMap(map['baselineP95'], 'baselineP95'),
      maximumP95: _metricMap(map['maximumP95'], 'maximumP95'),
      minimumP95: _metricMap(map['minimumP95'], 'minimumP95'),
    );
    baseline._validateDefinition();
    return baseline;
  }

  PackagedReleasePerformanceBaselineResult evaluate(
    Map<String, Object?> series,
  ) {
    final metadata = series['metadata'];
    if (metadata is! Map) {
      throw const FormatException('Release performance series lacks metadata.');
    }
    final metadataMap = Map<String, Object?>.from(metadata);
    final actualModel = _requiredString(metadataMap, 'hardwareModel');
    final actualArchitecture = _requiredString(metadataMap, 'architecture');
    final actualMacosVersion = _requiredString(metadataMap, 'macosVersion');
    final actualFixtureRevision = _requiredString(
      metadataMap,
      'fixtureRevision',
    );
    final actualMajor = _macosMajor(actualMacosVersion);
    if (actualModel != hardwareModel ||
        actualArchitecture != architecture ||
        actualMajor != macosMajorVersion ||
        actualFixtureRevision != fixtureRevision) {
      return PackagedReleasePerformanceBaselineResult.skipped(
        'Baseline requires $hardwareModel/$architecture macOS $macosMajorVersion with fixture revision $fixtureRevision; got $actualModel/$actualArchitecture macOS $actualMacosVersion with fixture revision $actualFixtureRevision.',
      );
    }

    final sampleCount = _requiredInt(series, 'sampleCount');
    final p95 = series['p95'];
    if (p95 is! Map) {
      throw const FormatException(
        'Release performance series lacks p95 metrics.',
      );
    }
    final p95Map = Map<String, Object?>.from(p95);
    final breaches = <String>[];
    if (sampleCount < minimumSampleCount) {
      breaches.add('sampleCount $sampleCount is below $minimumSampleCount');
    }
    for (final entry in maximumP95.entries) {
      final actual = _requiredInt(p95Map, entry.key);
      if (actual > entry.value) {
        breaches.add('${entry.key} p95 $actual exceeds ${entry.value}');
      }
    }
    for (final entry in minimumP95.entries) {
      final actual = _requiredInt(p95Map, entry.key);
      if (actual < entry.value) {
        breaches.add('${entry.key} p95 $actual is below ${entry.value}');
      }
    }
    return PackagedReleasePerformanceBaselineResult.applied(breaches);
  }

  static Map<String, int> _metricMap(Object? value, String label) {
    if (value is! Map || value.isEmpty) {
      throw FormatException('Release performance baseline $label is empty.');
    }
    final metrics = <String, int>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.key.trim().isEmpty) {
        throw FormatException(
          'Release performance baseline $label has an invalid metric name.',
        );
      }
      if (!packagedReleasePerformanceMetricNames.contains(entry.key)) {
        throw FormatException(
          'Release performance baseline $label has an unknown metric ${entry.key}.',
        );
      }
      metrics[entry.key] = _requiredInt({'value': entry.value}, 'value');
    }
    return Map.unmodifiable(metrics);
  }

  void _validateDefinition() {
    if (minimumSampleCount < 5) {
      throw const FormatException(
        'Release performance baseline must require at least five samples.',
      );
    }
    for (final entry in maximumP95.entries) {
      if (entry.value <= 0) {
        throw FormatException(
          'Release performance baseline maximum ${entry.key} must be positive.',
        );
      }
      final observed = baselineP95[entry.key];
      if (observed == null) {
        throw FormatException(
          'Release performance baseline lacks a baselineP95 observation for ${entry.key}.',
        );
      }
      if (observed > entry.value) {
        throw FormatException(
          'Release performance baseline observation ${entry.key} exceeds its maximum.',
        );
      }
    }
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Release performance value $key is invalid.');
    }
    return value;
  }

  static int _requiredInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value != value.round()) {
      throw FormatException('Release performance value $key is invalid.');
    }
    return value.toInt();
  }

  static int _macosMajor(String version) {
    final match = RegExp(r'^(\d+)').firstMatch(version);
    final major = int.tryParse(match?.group(1) ?? '');
    if (major == null || major < 1) {
      throw FormatException('macOS version $version is invalid.');
    }
    return major;
  }
}

class PackagedReleasePerformanceBaselineResult {
  final bool applicable;
  final bool passed;
  final String reason;
  final List<String> breaches;

  const PackagedReleasePerformanceBaselineResult._({
    required this.applicable,
    required this.passed,
    required this.reason,
    required this.breaches,
  });

  factory PackagedReleasePerformanceBaselineResult.skipped(String reason) =>
      PackagedReleasePerformanceBaselineResult._(
        applicable: false,
        passed: true,
        reason: reason,
        breaches: const [],
      );

  factory PackagedReleasePerformanceBaselineResult.applied(
    List<String> breaches,
  ) => PackagedReleasePerformanceBaselineResult._(
    applicable: true,
    passed: breaches.isEmpty,
    reason: breaches.isEmpty
        ? 'Hardware-scoped packaged Release baseline passed.'
        : 'Hardware-scoped packaged Release baseline breached.',
    breaches: List.unmodifiable(breaches),
  );

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'applicable': applicable,
    'passed': passed,
    'reason': reason,
    'breaches': breaches,
  };
}
