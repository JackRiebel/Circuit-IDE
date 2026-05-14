import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  if (Platform.isMacOS) {
    await windowManager.setPreventClose(true);
    windowManager.addListener(_MacWindowLifecycle());
  }

  const windowOptions = WindowOptions(
    size: Size(1400, 900),
    minimumSize: Size(800, 500),
    center: true,
    title: 'CircuitCode',
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Color(0xFF1E1E1E),
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: CircuitIDEApp()));
}

class _MacWindowLifecycle extends WindowListener {
  @override
  Future<void> onWindowClose() async {
    if (!Platform.isMacOS) return;
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }
}
