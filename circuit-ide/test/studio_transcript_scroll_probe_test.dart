import 'package:circuit_ide/services/studio_transcript_scroll_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(StudioTranscriptScrollProbe.endPackagedProbe);

  test('scroll driver is inert outside the private packaged probe', () async {
    var driveCalls = 0;
    var prepareCalls = 0;
    final owner = Object();
    StudioTranscriptScrollProbe.register(
      owner: owner,
      prepare: () async {
        prepareCalls++;
        return true;
      },
      driver: ({required stepCount}) async {
        driveCalls++;
        return true;
      },
    );

    expect(await StudioTranscriptScrollProbe.prepare(), isFalse);
    expect(await StudioTranscriptScrollProbe.drive(), isFalse);
    expect(prepareCalls, 0);
    expect(driveCalls, 0);
  });

  test(
    'only the active transcript owner can drive the packaged trace',
    () async {
      final firstOwner = Object();
      final activeOwner = Object();
      StudioTranscriptScrollProbe.beginPackagedProbe();
      StudioTranscriptScrollProbe.register(
        owner: firstOwner,
        prepare: () async => false,
        driver: ({required stepCount}) async => false,
      );
      StudioTranscriptScrollProbe.register(
        owner: activeOwner,
        prepare: () async => true,
        driver: ({required stepCount}) async => stepCount == 6,
      );
      StudioTranscriptScrollProbe.unregister(firstOwner);

      expect(StudioTranscriptScrollProbe.isReady, isTrue);
      expect(await StudioTranscriptScrollProbe.prepare(), isTrue);
      expect(await StudioTranscriptScrollProbe.drive(stepCount: 6), isTrue);
      StudioTranscriptScrollProbe.unregister(activeOwner);
      expect(StudioTranscriptScrollProbe.isReady, isFalse);
    },
  );
}
