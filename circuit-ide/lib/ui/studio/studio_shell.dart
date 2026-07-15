import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/studio_shell.dart';
import '../../state/agent_turn_runtime_provider.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/studio_request_lifecycle_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_background_task_dispatch.dart';
import 'studio_focus_restoration.dart';
import 'studio_home.dart';
import 'studio_left_rail.dart';
import 'studio_review_panel.dart';
import 'studio_settings_view.dart';
import 'studio_task_view.dart';
import 'studio_top_bar.dart';
import 'studio_workspace_access_failure.dart';

export 'studio_background_task_dispatch.dart' show backgroundTaskPromptMode;

// ADR-0007: Studio renders durable turn projections plus ephemeral view state.
class StudioShell extends ConsumerStatefulWidget {
  const StudioShell({super.key});

  @override
  ConsumerState<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends ConsumerState<StudioShell> {
  late final FocusNode _progressToggleFocusNode;

  @override
  void initState() {
    super.initState();
    _progressToggleFocusNode = FocusNode(debugLabel: 'studio-progress-toggle');
  }

  @override
  void dispose() {
    _progressToggleFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(agentWorkspaceProvider, (previous, next) {
      cancelStoppedBackgroundTasks(ref, previous, next);
      scheduleBackgroundTaskDispatch(ref, context);
      final notice = taskCompletionNotice(previous, next);
      if (notice == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(notice.message),
              action: SnackBarAction(
                label: 'Open task',
                onPressed: () => ref
                    .read(studioShellProvider.notifier)
                    .openTask(notice.taskId),
              ),
            ),
          );
      });
    });
    ref.listen(studioRequestLifecycleProvider, (previous, next) {
      scheduleBackgroundTaskDispatch(ref, context);
    });
    ref.listen(agentTurnRuntimeProvider, (previous, next) {
      if (previous?.hasActiveStudioRequest == true &&
          !next.hasActiveStudioRequest) {
        scheduleBackgroundTaskDispatch(ref, context);
      }
    });
    final tokens = ref.watch(themeProvider);
    final mode = ref.watch(studioShellProvider.select((state) => state.mode));

    return StudioWorkspaceAccessFailure(
      child: StudioFocusRestoration(
        progressToggleFocusNode: _progressToggleFocusNode,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Row(
            children: [
              const FocusTraversalOrder(
                order: NumericFocusOrder(0),
                child: StudioLeftRail(),
              ),
              Expanded(
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: tokens.studioCanvas,
                      border: Border(
                        left: BorderSide(
                          color: tokens.studioDivider.withValues(alpha: 0.34),
                        ),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        const StudioTopBar(),
                        Expanded(child: _StudioBody(mode: mode)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudioBody extends StatelessWidget {
  final StudioMode mode;

  const _StudioBody({required this.mode});

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      StudioMode.home => const StudioHome(),
      StudioMode.project => const StudioHome(),
      StudioMode.task => const StudioTaskView(),
      StudioMode.review => const StudioReviewPanel(),
      StudioMode.settings => const StudioSettingsView(),
    };
  }
}
