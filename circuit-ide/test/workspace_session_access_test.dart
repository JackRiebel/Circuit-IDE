import 'dart:io';

import 'package:circuit_ide/services/macos_workspace_access.dart';
import 'package:circuit_ide/state/workspace_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'workspace binding uses a user grant only for a freshly selected path',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-workspace-scope-',
      );
      addTearDown(() => root.delete(recursive: true));
      final access = _RecordingWorkspaceAccess();
      final container = ProviderContainer(
        overrides: [macosWorkspaceAccessProvider.overrideWithValue(access)],
      );
      addTearDown(container.dispose);

      final selected = await container
          .read(workspaceSessionProvider.notifier)
          .openWorkspaceAndBindAgent(root.path, userSelected: true);
      final resumed = await container
          .read(workspaceSessionProvider.notifier)
          .openWorkspaceAndBindAgent(root.path);

      expect(selected.success, isTrue);
      expect(resumed.success, isTrue);
      expect(access.userSelectedPaths, [root.path]);
      expect(access.resumedPaths, [root.path]);
    },
  );
}

class _RecordingWorkspaceAccess implements MacosWorkspaceAccess {
  final userSelectedPaths = <String>[];
  final resumedPaths = <String>[];

  @override
  Future<MacosWorkspaceAccessResult> grantUserSelectedWorkspace(
    String path,
  ) async {
    userSelectedPaths.add(path);
    return MacosWorkspaceAccessResult.allowed(path);
  }

  @override
  Future<void> revokeWorkspace(String path) async {}

  @override
  Future<MacosWorkspaceAccessResult> resumeWorkspace(String path) async {
    resumedPaths.add(path);
    return MacosWorkspaceAccessResult.allowed(path);
  }
}
