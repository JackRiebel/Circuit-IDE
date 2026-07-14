import 'package:circuit_ide/services/release_performance_series.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String sample({
    required int launch,
    required int residentSetBytes,
    bool passed = true,
    String stage = 'ok',
  }) {
    return '''
{"passed":$passed,"stage":"$stage","dartMainToFirstFrameMilliseconds":$launch,"projectBindMilliseconds":4,"firstStreamFrameMilliseconds":24,"streamTenThousandDeltaBurstMilliseconds":680,"streamTenThousandDeltaStateUpdates":1,"taskSwitchMilliseconds":1,"durableReloadMilliseconds":163,"taskSummaryPage5000Milliseconds":21,"threadSummaryPage1000Milliseconds":4,"threadHydration1000Milliseconds":42,"projectRecoveryAndMetadata500Milliseconds":2800,"semanticIndexRebuild1200Milliseconds":700,"durableCheckpointPersistenceMilliseconds":120,"residentSetBytes":$residentSetBytes,"streamFrameTimingSampleCount":8,"streamFrameBuildP95Milliseconds":5,"streamFrameRasterP95Milliseconds":4,"streamFrameTotalP95Milliseconds":11,"transcriptScrollFrameTimingSampleCount":12,"transcriptScrollFrameBuildP95Milliseconds":6,"transcriptScrollFrameRasterP95Milliseconds":5,"transcriptScrollFrameTotalP95Milliseconds":12}
''';
  }

  test(
    'aggregates five redacted packaged samples with median and nearest-rank p95',
    () {
      final series = PackagedReleasePerformanceSeries.parseLines([
        'PACKAGED_RELEASE_PERFORMANCE=${sample(launch: 60, residentSetBytes: 300)}',
        sample(launch: 20, residentSetBytes: 100),
        sample(launch: 50, residentSetBytes: 250),
        sample(launch: 30, residentSetBytes: 150),
        sample(launch: 40, residentSetBytes: 200),
      ]);

      final json = series.toJson();
      expect(json['schemaVersion'], 1);
      expect(json['sampleCount'], 5);
      expect((json['minimum'] as Map)['dartMainToFirstFrameMilliseconds'], 20);
      expect((json['median'] as Map)['dartMainToFirstFrameMilliseconds'], 40);
      expect((json['p95'] as Map)['dartMainToFirstFrameMilliseconds'], 60);
      expect((json['maximum'] as Map)['residentSetBytes'], 300);
      expect((json['samples'] as List), hasLength(5));
    },
  );

  test('rejects incomplete or unsuccessful packaged probe samples', () {
    expect(
      () => PackagedReleasePerformanceSeries.parseLines([
        sample(launch: 1, residentSetBytes: 1),
        sample(launch: 1, residentSetBytes: 1),
        sample(launch: 1, residentSetBytes: 1),
        sample(launch: 1, residentSetBytes: 1),
      ]),
      throwsFormatException,
    );
    expect(
      () => PackagedReleasePerformanceSample.parse(
        sample(launch: 1, residentSetBytes: 1, stage: 'failed'),
      ),
      throwsFormatException,
    );
  });
}
