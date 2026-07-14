import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/mcp_hub_provider.dart';
import '../../state/theme_provider.dart';
import 'add_mcp_server_dialog.dart';
import 'bot_agent_card.dart';
import 'bot_config_dialog.dart';
import 'mcp_server_card.dart';

class McpHubPanel extends ConsumerWidget {
  const McpHubPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final hubState = ref.watch(mcpHubProvider);

    if (hubState.isLoading) {
      return Center(child: CircularProgressIndicator(color: tokens.accent));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: tokens.border.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.extension, size: 14, color: tokens.accent),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  _buildSummary(hubState),
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xs,
                  ),
                ),
              ),
              _AddButton(tokens: tokens),
            ],
          ),
        ),

        // Server list + Bot section
        Expanded(
          child: hubState.servers.isEmpty && hubState.botAgent == null
              ? _EmptyState(tokens: tokens)
              : ListView(
                  padding: const EdgeInsets.all(Spacing.lg),
                  children: [
                    // Server cards
                    ...hubState.servers.map(
                      (server) => Dismissible(
                        key: ValueKey(server.config.name),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: Spacing.xl),
                          color: tokens.error.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.delete,
                            color: tokens.error,
                            size: 16,
                          ),
                        ),
                        onDismissed: (_) {
                          ref
                              .read(mcpHubProvider.notifier)
                              .removeServer(server.config.name);
                        },
                        child: McpServerCard(server: server),
                      ),
                    ),

                    // Bot Agent section divider
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                      child: Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: tokens.border.withValues(alpha: 0.3),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.lg,
                            ),
                            child: Text(
                              'BOT AGENT',
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: FontSizes.xxs,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: tokens.border.withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bot Agent card or setup placeholder
                    if (hubState.botAgent != null)
                      BotAgentCard(status: hubState.botAgent!)
                    else
                      _BotAgentSetup(tokens: tokens),
                  ],
                ),
        ),
      ],
    );
  }

  String _buildSummary(McpHubState hubState) {
    final parts = <String>[
      '${hubState.connectedCount} connected',
      '${hubState.totalToolCount} tools',
    ];
    if (hubState.runningCount > 0) {
      parts.add('${hubState.runningCount} running');
    }
    return parts.join('  ·  ');
  }
}

class _AddButton extends StatelessWidget {
  final dynamic tokens;
  const _AddButton({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => const AddMcpServerDialog(),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 12, color: tokens.textSecondary),
            const SizedBox(width: Spacing.sm),
            Text(
              'Add',
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final dynamic tokens;
  const _EmptyState({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_outlined, size: 32, color: tokens.textMuted),
          const SizedBox(height: Spacing.lg),
          Text(
            'No MCP servers configured',
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Add a server to extend AI capabilities',
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
          ),
        ],
      ),
    );
  }
}

class _BotAgentSetup extends StatelessWidget {
  final dynamic tokens;
  const _BotAgentSetup({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.border, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Icon(Icons.smart_toy_outlined, size: 24, color: tokens.textMuted),
          const SizedBox(height: Spacing.md),
          Text(
            'No bot agent configured',
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.sm),
          ),
          const SizedBox(height: Spacing.lg),
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
                vertical: Spacing.md,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: tokens.accent),
              ),
              child: Text(
                'Set Up Bot Agent',
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
