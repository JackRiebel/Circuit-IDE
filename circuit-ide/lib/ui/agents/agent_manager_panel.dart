import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/agent_manager_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'agent_config_dialog.dart';
import 'agent_run_dialog.dart';
import 'running_agent_card.dart';

class AgentManagerPanel extends ConsumerWidget {
  const AgentManagerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final managerState = ref.watch(agentManagerProvider);

    if (managerState.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: tokens.accent,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Running agents section
        if (managerState.running.isNotEmpty) ...[
          _SectionHeader(
            title: 'RUNNING',
            tokens: tokens,
            trailing: managerState.running.values
                    .any((i) => i.status == AgentRunStatus.running)
                ? _SmallButton(
                    label: 'Cancel All',
                    icon: Icons.stop,
                    color: tokens.error,
                    onTap: () => ref
                        .read(agentManagerProvider.notifier)
                        .cancelAll(),
                  )
                : null,
          ),
          Expanded(
            flex: managerState.configs.isEmpty ? 1 : 0,
            child: ListView(
              shrinkWrap: managerState.configs.isNotEmpty,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.sm,
              ),
              children: managerState.running.values
                  .map((instance) => RunningAgentCard(
                        key: ValueKey(instance.instanceId),
                        instance: instance,
                      ))
                  .toList(),
            ),
          ),
          Divider(
            height: 1,
            color: tokens.border.withValues(alpha: 0.3),
          ),
        ],

        // Agent templates section
        _SectionHeader(
          title: 'AGENTS',
          tokens: tokens,
          trailing: _SmallButton(
            label: 'New',
            icon: Icons.add,
            color: tokens.accent,
            onTap: () => showAgentConfigDialog(context),
          ),
        ),

        if (managerState.configs.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 32,
                      color: tokens.textDisabled,
                    ),
                    const SizedBox(height: Spacing.lg),
                    Text(
                      'No agents configured',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.sm,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'Create an agent with a custom system prompt,\ntools, and model to run tasks in parallel.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.textDisabled,
                        fontSize: FontSizes.xs,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                    ElevatedButton.icon(
                      onPressed: () => showAgentConfigDialog(context),
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text('Create Agent'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tokens.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(Radii.md),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.sm,
              ),
              itemCount: managerState.configs.length,
              itemBuilder: (context, index) {
                final config = managerState.configs[index];
                return _AgentConfigCard(config: config);
              },
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeTokens tokens;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.tokens,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xxs,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SmallButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: Spacing.sm),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: FontSizes.xxs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentConfigCard extends ConsumerStatefulWidget {
  final dynamic config;

  const _AgentConfigCard({required this.config});

  @override
  ConsumerState<_AgentConfigCard> createState() =>
      _AgentConfigCardState();
}

class _AgentConfigCardState extends ConsumerState<_AgentConfigCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final config = widget.config;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: Spacing.md),
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: _isHovered
              ? tokens.bgLighter
              : tokens.bgLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: _isHovered
                ? tokens.border
                : tokens.border.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  size: 14,
                  color: tokens.accent,
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    config.name,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.bgDark,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    config.model,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xxs,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ),
              ],
            ),
            if (config.description.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                config.description,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Action buttons (visible on hover)
            if (_isHovered) ...[
              const SizedBox(height: Spacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ActionBtn(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    color: tokens.textMuted,
                    onTap: () => showAgentConfigDialog(
                      context,
                      existing: config,
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  _ActionBtn(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    color: tokens.error,
                    onTap: () => ref
                        .read(agentManagerProvider.notifier)
                        .deleteConfig(config.id),
                  ),
                  const SizedBox(width: Spacing.md),
                  _ActionBtn(
                    icon: Icons.play_arrow,
                    label: 'Run',
                    color: tokens.success,
                    onTap: () => showAgentRunDialog(
                      context,
                      config: config,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: Spacing.sm),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: FontSizes.xxs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
