import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/mcp_hub_provider.dart';
import '../../state/theme_provider.dart';

class McpServerCard extends ConsumerWidget {
  final McpServerStatus server;

  const McpServerCard({super.key, required this.server});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final isConnected =
        server.connectionState == McpConnectionState.connected;
    final isConnecting =
        server.connectionState == McpConnectionState.connecting;
    final hasError =
        server.connectionState == McpConnectionState.error;

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isConnected
              ? tokens.success.withValues(alpha: 0.3)
              : hasError
                  ? tokens.error.withValues(alpha: 0.3)
                  : tokens.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Status indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected
                      ? tokens.success
                      : isConnecting
                          ? tokens.warning
                          : hasError
                              ? tokens.error
                              : tokens.textMuted,
                ),
              ),
              const SizedBox(width: Spacing.md),

              // Server name
              Expanded(
                child: Text(
                  server.config.name,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Tool count badge
              if (isConnected && server.toolCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    '${server.toolCount} tools',
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: FontSizes.xxs,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

              const SizedBox(width: Spacing.md),

              // Toggle switch
              SizedBox(
                height: 20,
                child: Switch(
                  value: server.config.enabled,
                  activeThumbColor: tokens.accent,
                  onChanged: (enabled) {
                    ref
                        .read(mcpHubProvider.notifier)
                        .toggleServer(server.config.name, enabled);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: Spacing.sm),

          // URL
          Text(
            server.config.url,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
            ),
            overflow: TextOverflow.ellipsis,
          ),

          if (hasError && server.error != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              server.error!,
              style: TextStyle(
                color: tokens.error,
                fontSize: FontSizes.xxs,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          if (isConnecting) ...[
            const SizedBox(height: Spacing.md),
            LinearProgressIndicator(
              backgroundColor: tokens.border,
              valueColor: AlwaysStoppedAnimation(tokens.accent),
            ),
          ],
        ],
      ),
    );
  }
}
