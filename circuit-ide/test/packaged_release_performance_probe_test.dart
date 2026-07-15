import 'package:circuit_ide/services/packaged_release_performance_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frame timeline uses nearest-rank p95 without retaining frame data', () {
    final summary = PackagedReleaseFrameTimingSummary.fromSamples(const [
      PackagedReleaseFrameTimingSample(
        build: Duration(milliseconds: 1),
        raster: Duration(milliseconds: 2),
        total: Duration(milliseconds: 4),
      ),
      PackagedReleaseFrameTimingSample(
        build: Duration(milliseconds: 3),
        raster: Duration(milliseconds: 4),
        total: Duration(milliseconds: 8),
      ),
      PackagedReleaseFrameTimingSample(
        build: Duration(milliseconds: 2),
        raster: Duration(milliseconds: 3),
        total: Duration(milliseconds: 6),
      ),
      PackagedReleaseFrameTimingSample(
        build: Duration(milliseconds: 4),
        raster: Duration(milliseconds: 5),
        total: Duration(milliseconds: 10),
      ),
      PackagedReleaseFrameTimingSample(
        build: Duration(milliseconds: 5),
        raster: Duration(milliseconds: 6),
        total: Duration(milliseconds: 12),
      ),
    ]);

    expect(summary.sampleCount, 5);
    expect(summary.buildP95, const Duration(milliseconds: 5));
    expect(summary.rasterP95, const Duration(milliseconds: 6));
    expect(summary.totalP95, const Duration(milliseconds: 12));
  });

  test(
    'packaged release performance probe emits only bounded metric evidence',
    () async {
      final result = await PackagedReleasePerformanceProbe.run(
        dartMainElapsed: const Duration(milliseconds: 42),
        // Unit tests do not mount a production widget tree. The packaged
        // LaunchServices route supplies the real end-of-frame waiter.
        waitForFrame: () async {},
      );

      expect(result.passed, isTrue, reason: result.stage);
      expect(result.stage, 'ok');
      final report = result.toJson();
      expect(report['dartMainToFirstFrameMilliseconds'], 42);
      expect(report['projectBindMilliseconds'], isA<int>());
      expect(report['firstStreamFrameMilliseconds'], isA<int>());
      expect(report['streamTenThousandDeltaBurstMilliseconds'], isA<int>());
      expect(
        report['streamTenThousandDeltaStateUpdates'],
        lessThanOrEqualTo(4),
      );
      expect(report['taskSwitchMilliseconds'], isA<int>());
      expect(report['durableReloadMilliseconds'], isA<int>());
      expect(report['taskSummaryPage5000Milliseconds'], isA<int>());
      expect(report['threadSummaryPage1000Milliseconds'], isA<int>());
      expect(report['threadHydration1000Milliseconds'], isA<int>());
      expect(report['projectRecoveryAndMetadata500Milliseconds'], isA<int>());
      expect(report['semanticIndexRebuild1200Milliseconds'], isA<int>());
      expect(report['durableCheckpointPersistenceMilliseconds'], isA<int>());
      expect(report['residentSetBytes'], greaterThan(0));
      expect(report.containsKey('streamFrameTimingSampleCount'), isFalse);
      expect(
        report.containsKey('transcriptScrollFrameTimingSampleCount'),
        isFalse,
      );
      expect(
        result.toMachineLine(),
        startsWith(PackagedReleasePerformanceProbe.readyMarker),
      );
      expect(
        result.toMachineLine(),
        isNot(contains('Release performance fixture')),
      );
      expect(result.toMachineLine(), isNot(contains('/tmp/')));
    },
  );

  test(
    'packaged probe redacts unexpected exception details by phase',
    () async {
      final result = await PackagedReleasePerformanceProbe.run(
        dartMainElapsed: Duration.zero,
        onContainerReady: (_) async {
          throw StateError('do not retain this private failure message');
        },
      );

      expect(result.passed, isFalse);
      expect(result.stage, 'unexpected_mount_shell');
      expect(
        result.toMachineLine(),
        isNot(contains('private failure message')),
      );
    },
  );
}
