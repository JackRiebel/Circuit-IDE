import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/workspace_session.dart';
import '../../services/project_directory_picker.dart';
import '../../state/settings_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/workspace_session_provider.dart';

/// Opens a user-selected project through the one Studio workspace-binding
/// path. It deliberately has no fallback directory: a cancelled native picker
/// leaves the current workspace untouched.
Future<bool> chooseStudioProjectRoot(
  WidgetRef ref, {
  String? initialDirectory,
}) async {
  final path = await ref
      .read(projectDirectoryPickerProvider)
      .chooseDirectory(initialDirectory: initialDirectory);
  if (path == null || path.trim().isEmpty) return false;

  final opened = await ref
      .read(workspaceSessionProvider.notifier)
      .openWorkspaceAndBindAgent(path, userSelected: true);
  if (!opened.success) return false;

  recordBoundStudioWorkspace(ref, requestedPath: path, binding: opened);
  return true;
}

/// Records and displays the exact root accepted by the workspace boundary.
///
/// Native macOS scope restoration can canonicalize a symlink or compatibility
/// path. Every caller must use that result for recents and Studio navigation
/// so the user never gets two entries for one approved directory.
String recordBoundStudioWorkspace(
  WidgetRef ref, {
  required String requestedPath,
  required WorkspaceBindingResult binding,
}) {
  assert(binding.success, 'Only a successfully bound workspace can be shown.');
  final workspacePath = binding.rootPath ?? requestedPath;
  ref
      .read(settingsProvider.notifier)
      .replaceRecentProjectPath(
        requestedPath: requestedPath,
        resolvedPath: workspacePath,
      );
  ref.read(studioShellProvider.notifier).openProject(workspacePath);
  return workspacePath;
}
