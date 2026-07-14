import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/workspace_session.dart';
import '../../state/workspace_session_provider.dart';
import 'studio_workspace_opening.dart';

typedef StudioWorkspacePicker = Future<bool> Function(WidgetRef ref);

/// Keeps a denied or stale macOS workspace scope visible until it is resolved.
///
/// Workspace binding can be initiated by a recent-project row, Finder, or the
/// folder picker. Listening here gives every path the same accessible recovery
/// action instead of allowing a failed recent-project open to appear inert.
class StudioWorkspaceAccessFailure extends ConsumerStatefulWidget {
  final Widget child;
  final StudioWorkspacePicker chooseProject;

  const StudioWorkspaceAccessFailure({
    super.key,
    required this.child,
    this.chooseProject = chooseStudioProjectRoot,
  });

  @override
  ConsumerState<StudioWorkspaceAccessFailure> createState() =>
      _StudioWorkspaceAccessFailureState();
}

class _StudioWorkspaceAccessFailureState
    extends ConsumerState<StudioWorkspaceAccessFailure> {
  String? _visibleError;

  @override
  Widget build(BuildContext context) {
    ref.listen<WorkspaceSessionState>(
      workspaceSessionProvider,
      _handleWorkspaceSession,
    );
    final session = ref.read(workspaceSessionProvider);
    if (_visibleError == null &&
        session.status == WorkspaceSessionStatus.failed) {
      _handleWorkspaceSession(null, session);
    }
    return widget.child;
  }

  void _handleWorkspaceSession(
    WorkspaceSessionState? previous,
    WorkspaceSessionState next,
  ) {
    final error = next.status == WorkspaceSessionStatus.failed
        ? next.error?.trim()
        : null;
    if (error == null || error.isEmpty) {
      if (_visibleError == null) return;
      _visibleError = null;
      _removeBanner();
      return;
    }
    if (_visibleError == error) return;
    _visibleError = error;
    _showBanner(error);
  }

  void _showBanner(String error) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _visibleError != error) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..removeCurrentMaterialBanner()
        ..showMaterialBanner(
          MaterialBanner(
            content: Semantics(
              key: const ValueKey('workspace-access-failure-live-region'),
              container: true,
              liveRegion: true,
              label: 'Workspace access needs attention. $error',
              child: Text('Workspace access needs attention. $error'),
            ),
            actions: [
              TextButton(
                onPressed: () => widget.chooseProject(ref),
                child: const Text('Choose folder'),
              ),
            ],
          ),
        );
    });
  }

  void _removeBanner() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _visibleError != null) return;
      ScaffoldMessenger.maybeOf(context)?.removeCurrentMaterialBanner();
    });
  }
}
