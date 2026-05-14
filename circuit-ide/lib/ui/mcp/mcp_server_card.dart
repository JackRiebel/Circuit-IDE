import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../services/mcp_process_manager.dart';
import '../../state/mcp_hub_provider.dart';
import '../../state/theme_provider.dart';
import 'server_token_dialog.dart';

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
    final hasScript = server.config.scriptPath != null;
    final hasEnvVars = server.config.requiredEnvVars.isNotEmpty;
    final isProcessRunning =
        server.processState == McpProcessState.running;
    final isProcessStarting =
        server.processState == McpProcessState.starting;

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

              // Process state chip (for servers with scriptPath)
              if (hasScript) ...[
                const SizedBox(width: Spacing.sm),
                _ProcessStateChip(state: server.processState, tokens: tokens),
              ],

              const SizedBox(width: Spacing.sm),

              // Launch/Stop button (for servers with scriptPath)
              if (hasScript) ...[
                _LaunchStopButton(
                  isRunning: isProcessRunning || isProcessStarting,
                  tokens: tokens,
                  onTap: () {
                    final notifier = ref.read(mcpHubProvider.notifier);
                    if (isProcessRunning || isProcessStarting) {
                      notifier.shutdownServer(server.config.name);
                    } else {
                      notifier.launchServer(server.config.name);
                    }
                  },
                ),
                const SizedBox(width: Spacing.sm),
              ],

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

          // URL + PID
          Row(
            children: [
              Expanded(
                child: Text(
                  server.config.url,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // Token status (for servers with requiredEnvVars)
          if (hasEnvVars) ...[
            const SizedBox(height: Spacing.sm),
            _TokenStatusRow(
              serverName: server.config.name,
              requiredEnvVars: server.config.requiredEnvVars,
              tokens: tokens,
            ),
          ],

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

class _ProcessStateChip extends StatelessWidget {
  final McpProcessState state;
  final dynamic tokens;

  const _ProcessStateChip({required this.state, required this.tokens});

  @override
  Widget build(BuildContext context) {
    if (state == McpProcessState.stopped) return const SizedBox.shrink();

    final (label, color) = switch (state) {
      McpProcessState.stopped => ('', tokens.textMuted as Color),
      McpProcessState.starting => ('Starting', tokens.warning as Color),
      McpProcessState.running => ('Running', tokens.success as Color),
      McpProcessState.error => ('Error', tokens.error as Color),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: FontSizes.xxs,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _LaunchStopButton extends StatelessWidget {
  final bool isRunning;
  final dynamic tokens;
  final VoidCallback onTap;

  const _LaunchStopButton({
    required this.isRunning,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: isRunning
                ? (tokens.error as Color).withValues(alpha: 0.3)
                : (tokens.success as Color).withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          isRunning ? 'Stop' : 'Launch',
          style: TextStyle(
            color: isRunning ? tokens.error : tokens.success,
            fontSize: FontSizes.xxs,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TokenStatusRow extends ConsumerWidget {
  final String serverName;
  final List<String> requiredEnvVars;
  final dynamic tokens;

  const _TokenStatusRow({
    required this.serverName,
    required this.requiredEnvVars,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => ServerTokenDialog(
            serverName: serverName,
            requiredEnvVars: requiredEnvVars,
          ),
        );
      },
      child: Row(
        children: [
          Icon(
            Icons.key,
            size: 10,
            color: tokens.textMuted,
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            'Tokens: ${requiredEnvVars.length} required',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xxs,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            'Configure',
            style: TextStyle(
              color: tokens.accent,
              fontSize: FontSizes.xxs,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
