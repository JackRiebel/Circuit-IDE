import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS host owns the scoped-workspace channel and no agent route', () async {
    final source = await File('macos/Runner/AppDelegate.swift').readAsString();

    expect(source, contains('circuitcode/workspace_access'));
    expect(source, contains('createAndStartWorkspaceAccess'));
    expect(source, contains('resumeWorkspaceAccess'));
    expect(source, contains('stopWorkspaceAccess'));
    expect(source, contains('startAccessingSecurityScopedResource'));
    expect(source, contains('SecTaskCopyValueForEntitlement'));
    expect(source, contains('Workspace access was not granted.'));
    expect(source, isNot(contains('agent tool workspace_access')));
  });
}
