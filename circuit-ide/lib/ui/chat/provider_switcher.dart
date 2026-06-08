import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/config/config.dart';
import '../../core/constants/design_tokens.dart';
import '../../core/utils/platform_utils.dart';
import '../../enums/ai_provider.dart';
import '../../enums/connection_status.dart';
import '../../state/chat_provider.dart';
import '../../state/connection_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/theme_provider.dart';

class ProviderSwitcher extends ConsumerWidget {
  const ProviderSwitcher({super.key});

  Future<void> _reconnect(WidgetRef ref) async {
    final service = ref.read(agentServiceProvider);
    final config = await AgentConfig.load();
    if (!config.hasCiscoCredentials) return;

    ref
        .read(connectionStatusProvider.notifier)
        .set(ConnectionStatus.connecting);
    ref.read(chatProvider.notifier).clearHistory();

    final workingDir =
        ref.read(fileTreeProvider).rootPath ?? PlatformUtils.scratchDir;
    final success = await service.connect(
      providerType: AIProviderType.cisco,
      credentials: {
        'client_id': config.ciscoClientId!,
        'client_secret': config.ciscoClientSecret!,
        'app_key': config.ciscoAppKey!,
      },
      workingDir: workingDir,
      model: ref.read(settingsProvider).ciscoModel,
    );

    ref
        .read(connectionStatusProvider.notifier)
        .set(success ? ConnectionStatus.connected : ConnectionStatus.error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final status = ref.watch(connectionStatusProvider);
    final isConnected = status == ConnectionStatus.connected;
    final isConnecting = status == ConnectionStatus.connecting;
    final statusColor = switch (status) {
      ConnectionStatus.connected => tokens.success,
      ConnectionStatus.connecting => tokens.warning,
      ConnectionStatus.error => tokens.error,
      _ => tokens.textMuted,
    };
    final statusLabel = switch (status) {
      ConnectionStatus.connected => 'Circuit connected',
      ConnectionStatus.connecting => 'Circuit connecting',
      ConnectionStatus.error => 'Circuit offline',
      _ => 'Circuit offline',
    };

    return Tooltip(
      message: isConnected
          ? 'Circuit Company AI is connected'
          : 'Reconnect Circuit Company AI',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: isConnecting ? null : () => _reconnect(ref),
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          decoration: BoxDecoration(
            color: tokens.bgDark,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: tokens.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isConnecting)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: statusColor,
                  ),
                )
              else
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 7),
              Text(
                statusLabel,
                style: TextStyle(
                  color: isConnected ? tokens.textPrimary : tokens.textMuted,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
