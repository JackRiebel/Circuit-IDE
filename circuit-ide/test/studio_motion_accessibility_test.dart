import 'package:circuit_ide/core/constants/design_tokens.dart';
import 'package:circuit_ide/ui/studio/studio_chrome.dart';
import 'package:circuit_ide/ui/studio/studio_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Studio motion follows the platform reduced-motion setting', (
    tester,
  ) async {
    Duration? reducedDuration;
    Duration? normalDuration;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              reducedDuration = studioMotionDuration(
                context,
                AnimationDurations.panel,
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              normalDuration = studioMotionDuration(
                context,
                AnimationDurations.panel,
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(reducedDuration, Duration.zero);
    expect(normalDuration, AnimationDurations.panel);
  });

  testWidgets('Studio chrome actions keep a 24px minimum target', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: StudioChromeIconButton(
                tooltip: 'Compact action',
                icon: StudioIcons.add,
                onTap: _noOp,
                width: 18,
                height: 20,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(StudioChromeIconButton)),
      const Size(
        StudioChromeIconButton.minimumTargetSize,
        StudioChromeIconButton.minimumTargetSize,
      ),
    );
  });
}

void _noOp() {}
