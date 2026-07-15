import 'package:circuit_ide/state/studio_right_drawer_provider.dart';
import 'package:circuit_ide/state/studio_shell_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'keyboard focus returns to the persistent Progress control when the work panel remounts',
    (tester) async {
      final originalPersistDebounce =
          StudioThreadController.debugPersistDebounceOverride;
      StudioThreadController.debugPersistDebounceOverride = Duration.zero;
      addTearDown(
        () => StudioThreadController.debugPersistDebounceOverride =
            originalPersistDebounce,
      );
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Keyboard focus task');
      container.read(studioShellProvider.notifier).openThread(thread.id);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: StudioShell()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Collapse panel'));
      await tester.pumpAndSettle();
      expect(container.read(studioRightDrawerProvider).collapsed, isTrue);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'studio-progress-toggle',
      );

      await tester.tap(find.byTooltip('Expand right panel'));
      await tester.pumpAndSettle();
      expect(container.read(studioRightDrawerProvider).collapsed, isFalse);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'studio-progress-toggle',
      );
    },
  );
}
