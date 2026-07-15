import 'dart:async';

import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/services/macos_update_service.dart';
import 'package:circuit_ide/state/macos_update_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/ui/studio/studio_update_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'synchronizes active Studio work with the native update gate outside Settings',
    () async {
      final updates = _RecordingMacosUpdateService();
      final container = ProviderContainer(
        overrides: [macosUpdateServiceProvider.overrideWithValue(updates)],
      );
      addTearDown(container.dispose);

      // CircuitIDEApp mounts this listener. No Settings panel is involved.
      container.read(macosUpdateMutationSyncProvider);
      await _drainMicrotasks();
      expect(updates.mutationStates, [false]);

      final threads = container.read(studioThreadProvider.notifier);
      final thread = threads.createBlankThread();
      threads.markPhase(
        thread.id,
        status: StudioThreadStatus.streaming,
        phase: StudioSendPhase.streaming,
      );
      await _drainMicrotasks();
      expect(updates.mutationStates, [false, true]);

      threads.markPhase(
        thread.id,
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
      );
      await _drainMicrotasks();
      expect(updates.mutationStates, [false, true, false]);
    },
  );

  test(
    'serializes rapid mutation gate transitions before native delivery',
    () async {
      final updates = _DelayedMacosUpdateService();
      final container = ProviderContainer(
        overrides: [macosUpdateServiceProvider.overrideWithValue(updates)],
      );
      addTearDown(container.dispose);

      container.read(macosUpdateMutationSyncProvider);
      await _drainMicrotasks();
      expect(updates.mutationStates, [false]);

      final threads = container.read(studioThreadProvider.notifier);
      final thread = threads.createBlankThread();
      threads.markPhase(
        thread.id,
        status: StudioThreadStatus.streaming,
        phase: StudioSendPhase.streaming,
      );
      await _drainMicrotasks();
      expect(
        updates.mutationStates,
        [false],
        reason: 'The active update waits behind the unresolved inactive call.',
      );

      updates.completeNext();
      await _drainMicrotasks();
      expect(updates.mutationStates, [false, true]);

      threads.markPhase(
        thread.id,
        status: StudioThreadStatus.done,
        phase: StudioSendPhase.completed,
      );
      await _drainMicrotasks();
      expect(
        updates.mutationStates,
        [false, true],
        reason: 'The terminal inactive update waits behind the active call.',
      );

      updates.completeNext();
      await _drainMicrotasks();
      expect(updates.mutationStates, [false, true, false]);
      updates.completeNext();
      await _drainMicrotasks();
    },
  );

  testWidgets('disables Check now immediately while Studio work is active', (
    tester,
  ) async {
    final updates = _RecordingMacosUpdateService();
    final container = ProviderContainer(
      overrides: [macosUpdateServiceProvider.overrideWithValue(updates)],
    );
    addTearDown(container.dispose);
    await _drainMicrotasks();

    final threads = container.read(studioThreadProvider.notifier);
    final thread = threads.createBlankThread();
    threads.markPhase(
      thread.id,
      status: StudioThreadStatus.waitingForApproval,
      phase: StudioSendPhase.waitingForApproval,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: StudioUpdateSettingsPanel()),
        ),
      ),
    );
    await tester.pump();

    final checkNow = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Check now'),
    );
    expect(checkNow.onPressed, isNull);
    expect(
      find.textContaining('Updates wait until active Studio work'),
      findsOneWidget,
    );
    // Marking a thread queues its normal durable-persistence debounce. Advance
    // the fake clock so the widget test leaves no intentional timer behind.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('names update controls and exposes their enabled toggle state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final updates = _RecordingMacosUpdateService();
    final container = ProviderContainer(
      overrides: [macosUpdateServiceProvider.overrideWithValue(updates)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: StudioUpdateSettingsPanel()),
        ),
      ),
    );
    await tester.pump();

    final automaticChecks = find.bySemanticsLabel(
      'Check for signed app updates automatically',
    );
    expect(automaticChecks, findsOneWidget);
    expect(
      tester.getSemantics(automaticChecks),
      isSemantics(
        label: 'Check for signed app updates automatically',
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    final automaticDownloads = find.bySemanticsLabel(
      'Download signed app updates automatically',
    );
    expect(automaticDownloads, findsOneWidget);
    expect(
      tester.getSemantics(automaticDownloads),
      isSemantics(
        label: 'Download signed app updates automatically',
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );

    final releaseChannelMenu = tester
        .widget<PopupMenuButton<CircuitUpdateChannel>>(
          find.byType(PopupMenuButton<CircuitUpdateChannel>),
        );
    expect(
      releaseChannelMenu.tooltip,
      'Release channel: Stable. Choose update channel',
    );
    semantics.dispose();
  });
}

Future<void> _drainMicrotasks() => Future<void>.value();

class _RecordingMacosUpdateService extends MacosUpdateService {
  final List<bool> mutationStates = [];

  _RecordingMacosUpdateService() : super(isSupported: () => true);

  @override
  Future<CircuitUpdateStatus> status() async =>
      const CircuitUpdateStatus(configured: true, canCheck: true);

  @override
  Future<CircuitUpdateStatus> setMutationActive(bool active) async {
    mutationStates.add(active);
    return CircuitUpdateStatus(configured: true, mutationActive: active);
  }
}

class _DelayedMacosUpdateService extends _RecordingMacosUpdateService {
  final List<Completer<CircuitUpdateStatus>> _pending = [];
  var _nextToComplete = 0;

  @override
  Future<CircuitUpdateStatus> setMutationActive(bool active) {
    mutationStates.add(active);
    final completion = Completer<CircuitUpdateStatus>();
    _pending.add(completion);
    return completion.future;
  }

  void completeNext() {
    final completion = _pending[_nextToComplete++];
    completion.complete(
      CircuitUpdateStatus(
        configured: true,
        mutationActive: mutationStates[_nextToComplete - 1],
      ),
    );
  }
}
