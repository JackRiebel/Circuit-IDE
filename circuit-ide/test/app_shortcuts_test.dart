import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App shortcuts do not expose legacy side or chat panels in Studio', () {
    final source = File('lib/app.dart').readAsStringSync();

    expect(source, contains('LogicalKeyboardKey.keyJ'));
    expect(source, contains('StudioDrawerMode.terminal'));
    expect(source, isNot(contains('LogicalKeyboardKey.keyB')));
    expect(source, isNot(contains('LogicalKeyboardKey.keyL')));
    expect(source, isNot(contains('sidePanelVisibleProvider.notifier')));
    expect(source, isNot(contains('chatPanelVisibleProvider.notifier')));
  });
}
