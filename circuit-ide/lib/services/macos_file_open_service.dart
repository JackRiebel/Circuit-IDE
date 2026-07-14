import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// A user-initiated macOS document-open event.
///
/// Native code accepts only existing local files or directories and never
/// exposes this channel to agent, browser, or MCP tools. Dart binds a folder
/// as the workspace; a file is opened only after its containing folder is
/// bound through the normal Studio workspace route.
class MacosFileOpenRequest {
  final String path;
  final bool isDirectory;

  const MacosFileOpenRequest({required this.path, required this.isDirectory});

  static MacosFileOpenRequest? fromPlatformValue(Object? value) {
    if (value is! Map) return null;
    final path = value['path']?.toString().trim() ?? '';
    final isDirectory = value['isDirectory'];
    if (path.isEmpty || isDirectory is! bool) return null;
    return MacosFileOpenRequest(path: path, isDirectory: isDirectory);
  }
}

typedef MacosFileOpenHandler =
    FutureOr<void> Function(MacosFileOpenRequest request);

/// Bridges the standard macOS Open menu/Finder delivery into Studio.
///
/// The native side queues events received before Flutter attaches. Calling
/// [start] installs the receiver first, then drains that bounded launch queue
/// so a Finder-open event is never lost during app initialization.
class MacosFileOpenService {
  static const _drainAttempts = 6;
  static const _drainRetryDelay = Duration(milliseconds: 50);

  final MethodChannel _channel;
  final bool Function() _isSupported;
  MacosFileOpenHandler? _handler;
  Future<void> _deliveryQueue = Future<void>.value();

  MacosFileOpenService({
    MethodChannel channel = const MethodChannel('circuitcode/file_open'),
    bool Function()? isSupported,
  }) : _channel = channel,
       _isSupported = isSupported ?? _supportsMacos;

  static final platform = MacosFileOpenService();

  Future<void> start(MacosFileOpenHandler handler) async {
    if (!_isSupported()) return;
    _handler = handler;
    _channel.setMethodCallHandler(handleNativeCall);
    final queued = await _drainOpenRequests();
    for (final request in queued ?? const <Object?>[]) {
      await _deliver(MacosFileOpenRequest.fromPlatformValue(request));
    }
  }

  Future<void> dispose() async {
    _handler = null;
    _channel.setMethodCallHandler(null);
  }

  Future<Object?> handleNativeCall(MethodCall call) async {
    if (call.method != 'open') return null;
    await _deliver(MacosFileOpenRequest.fromPlatformValue(call.arguments));
    return null;
  }

  /// A packaged Flutter host can publish its app-owned channel immediately
  /// after the Dart isolate starts. Retry only the missing-plugin startup
  /// race; real platform errors remain visible instead of being hidden.
  Future<List<Object?>?> _drainOpenRequests() async {
    for (var attempt = 0; attempt < _drainAttempts; attempt++) {
      try {
        return await _channel.invokeMethod<List<Object?>>('drainOpenRequests');
      } on MissingPluginException {
        if (attempt == _drainAttempts - 1) return null;
        await Future<void>.delayed(_drainRetryDelay);
      }
    }
    return null;
  }

  Future<void> _deliver(MacosFileOpenRequest? request) {
    if (request == null || _handler == null) return Future<void>.value();
    _deliveryQueue = _deliveryQueue.then((_) async {
      final handler = _handler;
      if (handler == null) return;
      await handler(request);
    });
    return _deliveryQueue;
  }

  static bool _supportsMacos() => Platform.isMacOS;
}
