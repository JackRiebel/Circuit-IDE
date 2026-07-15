import 'dart:io';

import 'package:flutter/services.dart';

/// Reveals a user-selected local file in Finder without granting an agent or
/// browser surface access to arbitrary desktop controls.
class MacosFileRevealService {
  final MethodChannel _channel;
  final bool Function() _isSupported;

  const MacosFileRevealService({
    MethodChannel channel = const MethodChannel('circuitcode/file_reveal'),
    bool Function()? isSupported,
  }) : _channel = channel,
       _isSupported = isSupported ?? _supportsMacos;

  static const platform = MacosFileRevealService();

  Future<bool> reveal(String path) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty || !_isSupported()) return false;
    try {
      return await _channel.invokeMethod<bool>('reveal', {
            'path': normalizedPath,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static bool _supportsMacos() => Platform.isMacOS;
}
