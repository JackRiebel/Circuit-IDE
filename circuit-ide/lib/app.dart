import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/commands/core_command_registry.dart';
import 'models/studio_right_drawer.dart';
import 'models/studio_shell.dart';
import 'state/theme_provider.dart';
import 'state/command_palette_provider.dart';
import 'state/layout_provider.dart';
import 'state/project_profile_provider.dart';
import 'state/settings_provider.dart';
import 'state/studio_right_drawer_provider.dart';
import 'state/studio_shell_provider.dart';
import 'state/studio_thread_search_provider.dart';
import 'state/terminal_provider.dart';
import 'state/workspace_context_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_tokens.dart';
import 'ui/screens/ide_screen.dart';

class CircuitIDEApp extends ConsumerStatefulWidget {
  const CircuitIDEApp({super.key});

  @override
  ConsumerState<CircuitIDEApp> createState() => _CircuitIDEAppState();
}

class _CircuitIDEAppState extends ConsumerState<CircuitIDEApp> {
  bool _themeRestored = false;

  @override
  void initState() {
    super.initState();
    CoreCommandRegistry.register(ref);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
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
            const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
                ref.read(studioThreadSearchProvider.notifier).toggle(),
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
                ref.read(studioThreadSearchProvider.notifier).open(),
            const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
                ref.read(sidePanelVisibleProvider.notifier).toggle(),
            const SingleActivator(LogicalKeyboardKey.keyJ, meta: true): () {
              final studioMode = ref.read(studioShellProvider).mode;
              if (studioMode == StudioMode.advancedEditor) {
                ref.read(terminalProvider.notifier).toggle();
                return;
              }
              ref
                  .read(studioRightDrawerProvider.notifier)
                  .openMode(StudioDrawerMode.terminal);
            },
            const SingleActivator(
              LogicalKeyboardKey.keyL,
              meta: true,
              shift: true,
            ): () =>
                ref.read(chatPanelVisibleProvider.notifier).toggle(),
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
}
