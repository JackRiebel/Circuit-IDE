import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/macos_update_service.dart';
import 'studio_thread_provider.dart';

final macosUpdateServiceProvider = Provider<MacosUpdateService>(
  (ref) => MacosUpdateService.platform,
);

final macosUpdateStatusProvider =
    NotifierProvider<MacosUpdateController, AsyncValue<CircuitUpdateStatus>>(
      MacosUpdateController.new,
    );

/// Keeps Sparkle's native relaunch gate aligned with Studio work even when the
/// Settings screen has never been opened. A completed or cancelled thread
/// clears the gate; every active request, approval, or command keeps it set.
///
/// This provider is mounted by [CircuitIDEApp], rather than by the Settings
/// panel. That placement matters for automatic update checks: they can run
/// without a user ever navigating to Settings.
final macosUpdateMutationSyncProvider = Provider<void>((ref) {
  final service = ref.read(macosUpdateServiceProvider);
  var active = _hasActiveStudioMutation(ref.read(studioThreadProvider));
  var pendingSync = Future<void>.value();

  void sync(bool next) {
    // Preserve every transition in order. A delayed platform reply must not
    // let a stale inactive update overtake newer active Studio work and clear
    // Sparkle's native relaunch gate. Errors remain fail-closed because an
    // updater is never initialized without signed bundle configuration.
    pendingSync = pendingSync.then((_) async {
      try {
        await service.setMutationActive(next);
      } catch (_) {}
    });
  }

  ref.listen<bool>(studioThreadProvider.select(_hasActiveStudioMutation), (
    previous,
    next,
  ) {
    if (next == active) return;
    active = next;
    sync(next);
  });
  sync(active);
});

bool _hasActiveStudioMutation(StudioThreadState state) =>
    state.threads.any((thread) => thread.isActive);

class MacosUpdateController extends Notifier<AsyncValue<CircuitUpdateStatus>> {
  @override
  AsyncValue<CircuitUpdateStatus> build() {
    unawaited(refresh());
    return const AsyncLoading();
  }

  MacosUpdateService get _service => ref.read(macosUpdateServiceProvider);

  Future<void> refresh() => _apply(_service.status());

  Future<void> setChannel(CircuitUpdateChannel channel) =>
      _apply(_service.setChannel(channel));

  Future<void> setAutomaticChecks(bool enabled) =>
      _apply(_service.setAutomaticChecks(enabled));

  Future<void> setAutomaticDownloads(bool enabled) =>
      _apply(_service.setAutomaticDownloads(enabled));

  /// Active Studio work is a conservative mutation boundary: updates wait for
  /// all active requests, not only the narrow patch/command instant.
  Future<void> setMutationActive(bool active) =>
      _apply(_service.setMutationActive(active), retainCurrent: true);

  Future<void> checkForUpdates() => _apply(_service.checkForUpdates());

  Future<void> _apply(
    Future<CircuitUpdateStatus> next, {
    bool retainCurrent = false,
  }) async {
    if (!retainCurrent) state = const AsyncLoading();
    state = AsyncData(await next);
  }
}
