import 'dart:io';

import 'package:flutter/services.dart';

import '../models/studio_browser.dart';

typedef BrowserVisualSnapshotInvoker = Future<Uint8List?> Function(String url);

/// Captures the currently visible macOS WebKit page only into bounded session
/// memory. The result is intentionally not written to disk and is never added
/// to model context; the browser drawer remains a user-controlled surface.
class BrowserVisualSnapshotService {
  static const _channel = MethodChannel('circuitcode/browser_snapshot');

  final bool supported;
  final BrowserVisualSnapshotInvoker _invoke;

  BrowserVisualSnapshotService({
    required this.supported,
    required BrowserVisualSnapshotInvoker invoke,
  }) : _invoke = invoke;

  factory BrowserVisualSnapshotService.platform() {
    return BrowserVisualSnapshotService(
      supported: Platform.isMacOS,
      invoke: (url) => _channel.invokeMethod<Uint8List>(
        'captureVisibleSnapshot',
        {'url': url},
      ),
    );
  }

  Future<Uint8List?> capture(String url) async {
    final uri = Uri.tryParse(url);
    if (!supported || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    try {
      final bytes = await _invoke(url);
      if (!_isBoundedPng(bytes)) return null;
      return Uint8List.fromList(bytes!);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  bool _isBoundedPng(Uint8List? bytes) {
    return BrowserPageSnapshot.isValidVisualPng(bytes);
  }
}
