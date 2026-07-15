import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'core/commands/core_command_registry.dart';
import 'models/studio_right_drawer.dart';
import 'state/theme_provider.dart';
import 'state/agent_turn_runtime_provider.dart';
import 'state/command_palette_provider.dart';
import 'state/macos_update_provider.dart';
import 'state/project_profile_provider.dart';
import 'state/settings_provider.dart';
import 'state/studio_right_drawer_provider.dart';
import 'state/studio_shell_provider.dart';
import 'state/studio_thread_provider.dart';
import 'state/studio_thread_search_provider.dart';
import 'state/workspace_session_provider.dart';
import 'state/workspace_context_provider.dart';
import 'services/macos_file_open_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_tokens.dart';
import 'ui/screens/ide_screen.dart';
import 'ui/studio/studio_workspace_opening.dart';

class CircuitIDEApp extends ConsumerStatefulWidget {
  const CircuitIDEApp({super.key});

  @override
  ConsumerState<CircuitIDEApp> createState() => _CircuitIDEAppState();
}

class _CircuitIDEAppState extends ConsumerState<CircuitIDEApp>
    with WidgetsBindingObserver {
  bool _themeRestored = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Riverpod 3 rejects provider writes while the initial widget tree is
    // mounting. Command registration and the first accessibility sync both
    // update providers, so schedule them after the production shell exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      CoreCommandRegistry.register(ref);
      _syncHighContrast();
    });
    unawaited(_startMacosFileOpenHandling());
  }

  @override
  void didChangeAccessibilityFeatures() {
    _syncHighContrast();
  }

  @override
  void dispose() {
    unawaited(MacosFileOpenService.platform.dispose());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _startMacosFileOpenHandling() async {
    if (!Platform.isMacOS) return;
    await MacosFileOpenService.platform.start(_handleMacosFileOpen);
  }

  Future<void> _handleMacosFileOpen(MacosFileOpenRequest request) async {
    if (!mounted) return;
    final workspacePath = request.isDirectory
        ? request.path
        : p.dirname(request.path);
    if (workspacePath.trim().isEmpty) return;
    final opened = await ref
        .read(workspaceSessionProvider.notifier)
        .openWorkspaceAndBindAgent(workspacePath, userSelected: true);
    if (!mounted || !opened.success) return;
    recordBoundStudioWorkspace(
      ref,
      requestedPath: workspacePath,
      binding: opened,
    );
    if (!request.isDirectory) {
      ref.read(studioRightDrawerProvider.notifier).openFile(request.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    // This service-level listener must stay mounted outside Settings so an
    // automatic Sparkle update cannot interrupt an active Studio task.
    ref.watch(macosUpdateMutationSyncProvider);
    ref.watch(workspaceContextProvider);
    ref.watch(projectProfileProvider);
    final theme = AppTheme.fromTokens(tokens);

    // Restore theme from persisted settings once
    ref.listen(settingsProvider, (prev, next) {
      if (!_themeRestored && next.themeName.isNotEmpty) {
        _themeRestored = true;
        final savedTheme = ThemeTokens.fromName(next.themeName);
        if (savedTheme.name != tokens.name) {
          ref.read(themeProvider.notifier).setTheme(savedTheme);
        }
      }
    });

    return MaterialApp(
      title: 'CircuitCode',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        backgroundColor: tokens.bgDark,
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(
              LogicalKeyboardKey.keyP,
              meta: true,
              shift: true,
            ): () =>
                ref.read(commandPaletteProvider.notifier).toggle(),
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                ref.read(commandPaletteProvider.notifier).toggle(),
            const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
                _startNewChat,
            const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
                ref.read(studioThreadSearchProvider.notifier).toggle(),
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
                ref.read(studioThreadSearchProvider.notifier).open(),
            const SingleActivator(LogicalKeyboardKey.keyJ, meta: true): () =>
                ref
                    .read(studioRightDrawerProvider.notifier)
                    .openMode(StudioDrawerMode.terminal),
            const SingleActivator(
              LogicalKeyboardKey.keyD,
              meta: true,
              shift: true,
            ): _openRepositoryDiff,
            const SingleActivator(
              LogicalKeyboardKey.keyO,
              meta: true,
              shift: true,
            ): () =>
                ref.read(studioShellProvider.notifier).togglePlanMode(),
            const SingleActivator(
              LogicalKeyboardKey.arrowRight,
              meta: true,
              alt: true,
            ): () => ref
                .read(studioShellProvider.notifier)
                .toggleRightProgressPanel(),
            const SingleActivator(
              LogicalKeyboardKey.keyA,
              meta: true,
              shift: true,
            ): _archiveSelectedThread,
            const SingleActivator(LogicalKeyboardKey.escape):
                _cancelSelectedRequest,
            const SingleActivator(
              LogicalKeyboardKey.keyG,
              control: true,
              shift: true,
            ): () =>
                ref.read(studioShellProvider.notifier).openReview(),
            const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () =>
                _openDrawer(StudioDrawerMode.files),
            const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
              alt: true,
            ): _openSideChat,
            const SingleActivator(
              LogicalKeyboardKey.keyM,
              meta: true,
              shift: true,
            ): () =>
                ref.read(workspaceContextProvider.notifier).refresh(),
          },
          child: const Focus(autofocus: true, child: IDEScreen()),
        ),
      ),
    );
  }

  void _openDrawer(StudioDrawerMode mode) {
    ref.read(studioShellProvider.notifier).showRightProgressPanel();
    ref.read(studioRightDrawerProvider.notifier).openMode(mode);
  }

  void _syncHighContrast() {
    ref
        .read(themeProvider.notifier)
        .setHighContrast(
          WidgetsBinding
              .instance
              .platformDispatcher
              .accessibilityFeatures
              .highContrast,
        );
  }

  void _startNewChat() {
    ref.read(studioShellProvider.notifier).openHome();
  }

  void _openRepositoryDiff() {
    ref.read(studioShellProvider.notifier).showRightProgressPanel();
    ref.read(studioRightDrawerProvider.notifier).openRepositoryDiff();
  }

  void _cancelSelectedRequest() {
    final requestId = ref.read(studioThreadProvider).selectedThread?.requestId;
    if (requestId == null || requestId.trim().isEmpty) return;
    ref.read(agentTurnRuntimeProvider.notifier).cancel(requestId);
  }

  void _archiveSelectedThread() {
    final threadId = ref.read(studioThreadProvider).selectedThreadId;
    if (threadId == null || threadId.trim().isEmpty) return;
    ref.read(studioThreadProvider.notifier).archiveThread(threadId);
    ref.read(studioShellProvider.notifier).openHome();
  }

  void _openSideChat() {
    final threadId = ref.read(studioThreadProvider).selectedThreadId;
    final shell = ref.read(studioShellProvider.notifier);
    if (threadId == null) {
      shell.openHome();
    } else {
      shell.openThread(threadId);
    }
  }
}
