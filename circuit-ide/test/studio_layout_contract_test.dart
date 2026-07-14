import 'package:circuit_ide/core/constants/studio_layout_contract.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/theme_provider.dart';
import 'package:circuit_ide/theme/theme_tokens.dart';
import 'package:circuit_ide/ui/studio/studio_left_rail.dart';
import 'package:circuit_ide/ui/studio/studio_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'support/studio_golden_harness.dart';

void main() {
  const viewports = [
    _StudioViewport('minimum_desktop', Size(1366, 768)),
    _StudioViewport('comfortable_desktop', Size(1440, 900)),
    _StudioViewport('wide_desktop', Size(1728, 1080)),
  ];

  test('Studio layout contract defines supported desktop geometry', () {
    expect(StudioLayoutContract.minimumDesktopWidth, 1366);
    expect(StudioLayoutContract.minimumDesktopHeight, 768);
    expect(
      StudioLayoutContract.comfortableDesktopWidth,
      greaterThanOrEqualTo(StudioLayoutContract.minimumDesktopWidth),
    );
    expect(StudioLayoutContract.leftRailWidth, 236);
    expect(StudioLayoutContract.topBarHeight, 43);
    expect(
      StudioLayoutContract.standardDrawerWidth,
      greaterThan(StudioLayoutContract.collapsedDrawerWidth),
    );
    expect(
      StudioLayoutContract.reviewWidth,
      greaterThan(StudioLayoutContract.proseWidth),
    );
  });

  for (final viewport in viewports) {
    testWidgets(
      'Studio shell keeps critical controls visible at ${viewport.id}',
      (tester) async {
        VisibilityDetectorController.instance.updateInterval = Duration.zero;
        await tester.binding.setSurfaceSize(viewport.size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final thread = container
            .read(studioThreadProvider.notifier)
            .createBlankThread(
              title: 'Long desktop task title that must leave controls usable',
            );
        container.read(studioShellProvider.notifier).openThread(thread.id);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: studioGoldenHarness(const StudioShell()),
          ),
        );
        await tester.pumpAndSettle();

        for (final tooltip in const [
          'Open in',
          'Command palette (⌘K)',
          'Hide Progress panel (⌥⌘→)',
          'Thread options',
          'Collapse panel',
        ]) {
          _expectOnScreen(tester, find.byTooltip(tooltip), viewport.size);
        }
        expect(
          tester.getSize(find.byType(StudioLeftRail)).width,
          StudioLayoutContract.leftRailWidth,
        );
        await expectLater(
          find.byType(StudioShell),
          matchesGoldenFile('goldens/studio_shell_${viewport.id}.png'),
        );
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }

  testWidgets('Studio shell retains stable chrome while resizing desktop', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.binding.setSurfaceSize(
      const Size(
        StudioLayoutContract.comfortableDesktopWidth,
        StudioLayoutContract.comfortableDesktopHeight,
      ),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Resize-safe task');
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(const StudioShell()),
      ),
    );
    await tester.pumpAndSettle();
    final initialRailWidth = tester.getSize(find.byType(StudioLeftRail)).width;
    final initialOpenInHeight = tester
        .getRect(find.byTooltip('Open in'))
        .height;

    await tester.binding.setSurfaceSize(
      const Size(
        StudioLayoutContract.minimumDesktopWidth,
        StudioLayoutContract.minimumDesktopHeight,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(StudioLeftRail)).width, initialRailWidth);
    expect(
      tester.getRect(find.byTooltip('Open in')).height,
      initialOpenInHeight,
    );
    _expectOnScreen(
      tester,
      find.byTooltip('Command palette (⌘K)'),
      const Size(
        StudioLayoutContract.minimumDesktopWidth,
        StudioLayoutContract.minimumDesktopHeight,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Studio shell keeps its desktop controls usable at 200% text', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    const viewport = Size(
      StudioLayoutContract.comfortableDesktopWidth,
      StudioLayoutContract.comfortableDesktopHeight,
    );
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(
          title: 'Text scale reflow keeps Studio chrome usable',
        );
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(
          const StudioShell(),
          textScaler: const TextScaler.linear(2),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(StudioShell),
      matchesGoldenFile('goldens/studio_shell_200_text_scale.png'),
    );
    expect(tester.takeException(), isNull);
    for (final tooltip in const [
      'Open in',
      'Command palette (⌘K)',
      'Hide Progress panel (⌥⌘→)',
      'Thread options',
      'Collapse panel',
    ]) {
      _expectOnScreen(tester, find.byTooltip(tooltip), viewport);
    }
    expect(
      find.text('Text scale reflow keeps Studio chrome usable'),
      findsAtLeastNWidgets(1),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Studio shell retains its high-contrast hierarchy', (
    tester,
  ) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    const viewport = Size(
      StudioLayoutContract.comfortableDesktopWidth,
      StudioLayoutContract.comfortableDesktopHeight,
    );
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(themeProvider.notifier).setHighContrast(true);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'High-contrast Studio review');
    container.read(studioShellProvider.notifier).openThread(thread.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: studioGoldenHarness(
          const StudioShell(),
          tokens: ThemeTokens.dark.highContrastVariant,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(themeProvider).highContrast, isTrue);
    await expectLater(
      find.byType(StudioShell),
      matchesGoldenFile('goldens/studio_shell_high_contrast.png'),
    );
    for (final tooltip in const [
      'Open in',
      'Command palette (⌘K)',
      'Hide Progress panel (⌥⌘→)',
      'Thread options',
      'Collapse panel',
    ]) {
      _expectOnScreen(tester, find.byTooltip(tooltip), viewport);
    }
    await tester.pump(const Duration(seconds: 1));
  });
}

void _expectOnScreen(WidgetTester tester, Finder finder, Size viewport) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

class _StudioViewport {
  final String id;
  final Size size;

  const _StudioViewport(this.id, this.size);
}
