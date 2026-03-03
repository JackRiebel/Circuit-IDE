import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/mcp_hub_provider.dart';
import '../../state/theme_provider.dart';
import 'add_mcp_server_dialog.dart';
import 'mcp_server_card.dart';

class McpHubPanel extends ConsumerWidget {
  const McpHubPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final hubState = ref.watch(mcpHubProvider);

    if (hubState.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: tokens.accent),
      );
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
                  '${hubState.connectedCount} connected  ·  ${hubState.totalToolCount} tools',
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

        // Server list
        Expanded(
          child: hubState.servers.isEmpty
              ? _EmptyState(tokens: tokens)
              : ListView.builder(
                  padding: const EdgeInsets.all(Spacing.lg),
                  itemCount: hubState.servers.length,
                  itemBuilder: (context, index) {
                    final server = hubState.servers[index];
                    return Dismissible(
                      key: ValueKey(server.config.name),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: Spacing.xl),
                        color: tokens.error.withValues(alpha: 0.1),
                        child: Icon(Icons.delete, color: tokens.error, size: 16),
                      ),
                      onDismissed: (_) {
                        ref
                            .read(mcpHubProvider.notifier)
                            .removeServer(server.config.name);
                      },
                      child: McpServerCard(server: server),
                    );
                  },
                ),
        ),
      ],
    );
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
          Icon(
            Icons.extension_outlined,
            size: 32,
            color: tokens.textMuted,
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'No MCP servers configured',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.sm,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Add a server to extend AI capabilities',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
            ),
          ),
        ],
      ),
    );
  }
}
