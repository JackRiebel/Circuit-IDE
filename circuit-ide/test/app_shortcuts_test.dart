import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App shortcuts do not expose legacy side or chat panels in Studio', () {
    final source = File('lib/app.dart').readAsStringSync();

    expect(source, contains('LogicalKeyboardKey.keyJ'));
    expect(source, contains('StudioDrawerMode.terminal'));
    expect(source, contains('LogicalKeyboardKey.keyN'));
    expect(source, contains('LogicalKeyboardKey.keyD'));
    expect(source, contains('LogicalKeyboardKey.keyO'));
    expect(source, contains('LogicalKeyboardKey.keyA'));
    expect(source, contains('LogicalKeyboardKey.arrowRight'));
    expect(source, contains('LogicalKeyboardKey.escape'));
    expect(source, contains('LogicalKeyboardKey.keyP'));
    expect(source, contains('StudioDrawerMode.files'));
    expect(source, contains('LogicalKeyboardKey.keyS'));
    expect(source, contains('openRepositoryDiff()'));
    expect(source, contains('archiveThread(threadId)'));
    expect(source, contains('agentTurnRuntimeProvider.notifier).cancel'));
    expect(source, contains('_openSideChat'));
    expect(source, contains('LogicalKeyboardKey.keyG'));
    expect(source, contains('openReview()'));
    expect(source, isNot(contains('LogicalKeyboardKey.keyB')));
    expect(source, isNot(contains('LogicalKeyboardKey.keyL')));
    expect(source, isNot(contains('LogicalKeyboardKey.keyT')));
    expect(source, isNot(contains('StudioDrawerMode.browser')));
    expect(source, isNot(contains('sidePanelVisibleProvider.notifier')));
    expect(source, isNot(contains('chatPanelVisibleProvider.notifier')));
  });
}
