import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/mcp/bot_agent_config.dart';
import '../../core/constants/design_tokens.dart';
import '../../state/mcp_hub_provider.dart';
import '../../state/theme_provider.dart';
import 'bot_config_dialog.dart';

class BotAgentCard extends ConsumerWidget {
  final BotAgentStatus status;

  const BotAgentCard({super.key, required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final isRunning = status.state == BotAgentState.running;
    final isStarting = status.state == BotAgentState.starting;
    final hasError = status.state == BotAgentState.error;

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isRunning
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
              Icon(Icons.smart_toy, size: 16, color: tokens.accent),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  'Webex Bot Agent',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StateChip(state: status.state, tokens: tokens),
            ],
          ),
          const SizedBox(height: Spacing.md),

          // Config summary
          Text(
            'Port: ${status.config.port}  ·  Model: ${status.config.model}',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
            ),
          ),

          // Ngrok URL when running
          if (isRunning && status.publicUrl != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Webhook: ${status.publicUrl}',
              style: TextStyle(
                color: tokens.accent,
                fontSize: FontSizes.xs,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // PID when running
          if (isRunning && status.pid != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'PID ${status.pid}',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
              ),
            ),
          ],

          // Error message
          if (hasError && status.error != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              status.error!,
              style: TextStyle(
                color: tokens.error,
                fontSize: FontSizes.xxs,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          if (isStarting) ...[
            const SizedBox(height: Spacing.md),
            LinearProgressIndicator(
              backgroundColor: tokens.border,
              valueColor: AlwaysStoppedAnimation(tokens.accent),
            ),
          ],

          const SizedBox(height: Spacing.lg),

          // Actions
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(Radii.sm),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => const BotConfigDialog(),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.lg,
                    vertical: Spacing.sm,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Text(
                    'Configure',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (isRunning || isStarting)
                _ActionButton(
                  label: 'Stop',
                  color: tokens.error,
                  tokens: tokens,
                  onTap: () {
                    ref.read(mcpHubProvider.notifier).stopBotAgent();
                  },
                )
              else
                _ActionButton(
                  label: 'Start',
                  color: tokens.success,
                  tokens: tokens,
                  onTap: status.config.scriptPath != null
                      ? () {
                          ref.read(mcpHubProvider.notifier).launchBotAgent();
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final BotAgentState state;
  final dynamic tokens;

  const _StateChip({required this.state, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      BotAgentState.stopped => ('Stopped', tokens.textMuted as Color),
      BotAgentState.starting => ('Starting', tokens.warning as Color),
      BotAgentState.running => ('Running', tokens.success as Color),
      BotAgentState.error => ('Error', tokens.error as Color),
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

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final dynamic tokens;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.tokens,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: onTap != null ? color.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: onTap != null
                ? color.withValues(alpha: 0.3)
                : tokens.border as Color,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onTap != null ? color : tokens.textMuted as Color,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
