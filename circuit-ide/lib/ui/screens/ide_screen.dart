import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/config/config.dart';
import '../../core/utils/logger.dart';
import '../../enums/ai_provider.dart';
import '../../enums/connection_status.dart';
import '../../state/connection_provider.dart';
import '../command_palette/command_palette.dart';
import '../studio/studio_shell.dart';
import '../../state/command_palette_provider.dart';

class IDEScreen extends ConsumerStatefulWidget {
  const IDEScreen({super.key});

  @override
  ConsumerState<IDEScreen> createState() => _IDEScreenState();
}

class _IDEScreenState extends ConsumerState<IDEScreen> {
  @override
  void initState() {
    super.initState();
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    try {
      final config = await AgentConfig.load();
      if (!mounted) return;

      if (!config.hasCiscoCredentials) return;

      ref
          .read(connectionStatusProvider.notifier)
          .set(ConnectionStatus.connecting);

      final success = await ref
          .read(studioAgentConnectionProvider.notifier)
          .connect(
            providerType: AIProviderType.cisco,
            credentials: {
              'client_id': config.ciscoClientId!,
              'client_secret': config.ciscoClientSecret!,
              'app_key': config.ciscoAppKey!,
            },
          );

      if (!mounted) return;

      ref
          .read(connectionStatusProvider.notifier)
          .set(
            success
                ? ConnectionStatus.connected
                : ConnectionStatus.disconnected,
          );
    } catch (e) {
      Logger.error('Auto-connect failed', e);
      if (!mounted) return;
      ref.read(connectionStatusProvider.notifier).set(ConnectionStatus.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paletteState = ref.watch(commandPaletteProvider);

    return Stack(
      children: [
        const StudioShell(),
        if (paletteState.isOpen) const CommandPalette(),
      ],
    );
  }
}
