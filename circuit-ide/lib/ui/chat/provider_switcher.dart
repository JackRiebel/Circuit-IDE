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

  Future<void> _switchProvider(WidgetRef ref, AIProviderType target) async {
    final settings = ref.read(settingsProvider);
    if (settings.activeProvider == target) return;

    // Save the preference
    ref.read(settingsProvider.notifier).setActiveProvider(target);

    // Disconnect current provider
    final service = ref.read(agentServiceProvider);
    service.disconnect();
    ref
        .read(connectionStatusProvider.notifier)
        .set(ConnectionStatus.disconnected);

    // Clear chat history
    ref.read(chatProvider.notifier).clearHistory();

    // Reconnect with saved credentials for the new provider
    try {
      final config = await AgentConfig.load();
      final workingDir = ref.read(fileTreeProvider).rootPath ?? PlatformUtils.scratchDir;

      Map<String, String>? credentials;
      String? model;

      if (target == AIProviderType.cisco && config.hasCiscoCredentials) {
        credentials = {
          'client_id': config.ciscoClientId!,
          'client_secret': config.ciscoClientSecret!,
          'app_key': config.ciscoAppKey!,
        };
        model = settings.ciscoModel;
      } else if (target == AIProviderType.anthropic &&
          config.hasAnthropicCredentials) {
        credentials = {
          'api_key': config.anthropicApiKey!,
        };
        model = settings.anthropicModel;
      }

      if (credentials == null) return;

      ref
          .read(connectionStatusProvider.notifier)
          .set(ConnectionStatus.connecting);

      final success = await service.connect(
        providerType: target,
        credentials: credentials,
        workingDir: workingDir,
        model: model,
      );

      ref.read(connectionStatusProvider.notifier).set(
            success
                ? ConnectionStatus.connected
                : ConnectionStatus.error,
          );
    } catch (_) {
      ref
          .read(connectionStatusProvider.notifier)
          .set(ConnectionStatus.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final active = settings.activeProvider;

    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: tokens.bgDark,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProviderTab(
            label: 'Circuit',
            isActive: active == AIProviderType.cisco,
            color: tokens.circuitColor,
            onTap: () => _switchProvider(ref, AIProviderType.cisco),
          ),
          _ProviderTab(
            label: 'Claude',
            isActive: active == AIProviderType.anthropic,
            color: tokens.claudeColor,
            onTap: () => _switchProvider(ref, AIProviderType.anthropic),
          ),
        ],
      ),
    );
  }
}

class _ProviderTab extends StatefulWidget {
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _ProviderTab({
    required this.label,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ProviderTab> createState() => _ProviderTabState();
}

class _ProviderTabState extends State<_ProviderTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AnimationDurations.fast,
          curve: AnimationCurves.snappy,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.color.withValues(alpha: 0.15)
                : _isHovered
                    ? widget.color.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.isActive
                    ? widget.color
                    : _isHovered
                        ? widget.color.withValues(alpha: 0.7)
                        : widget.color.withValues(alpha: 0.4),
                fontSize: FontSizes.xs,
                fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
