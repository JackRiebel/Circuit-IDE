import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../enums/message_role.dart';
import '../../state/agent_manager_provider.dart';
import '../../state/theme_provider.dart';

class RunningAgentCard extends ConsumerStatefulWidget {
  final AgentInstance instance;

  const RunningAgentCard({super.key, required this.instance});

  @override
  ConsumerState<RunningAgentCard> createState() => _RunningAgentCardState();
}

class _RunningAgentCardState extends ConsumerState<RunningAgentCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final instance = widget.instance;

    final statusColor = switch (instance.status) {
      AgentRunStatus.running => tokens.accent,
      AgentRunStatus.completed => tokens.success,
      AgentRunStatus.error => tokens.error,
      AgentRunStatus.cancelled => tokens.textMuted,
    };

    final statusIcon = switch (instance.status) {
      AgentRunStatus.running => Icons.sync,
      AgentRunStatus.completed => Icons.check_circle,
      AgentRunStatus.error => Icons.error,
      AgentRunStatus.cancelled => Icons.cancel,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — always visible
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(Radii.lg),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  // Status indicator
                  if (instance.status == AgentRunStatus.running)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: statusColor,
                      ),
                    )
                  else
                    Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: Spacing.md),

                  // Name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          instance.name,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FontSizes.sm,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          instance.task,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: FontSizes.xs,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Actions
                  if (instance.status == AgentRunStatus.running)
                    _IconBtn(
                      icon: Icons.stop,
                      color: tokens.error,
                      tooltip: 'Cancel',
                      onTap: () => ref
                          .read(agentManagerProvider.notifier)
                          .cancelAgent(instance.instanceId),
                    ),
                  if (instance.status != AgentRunStatus.running)
                    _IconBtn(
                      icon: Icons.close,
                      color: tokens.textMuted,
                      tooltip: 'Remove',
                      onTap: () => ref
                          .read(agentManagerProvider.notifier)
                          .removeAgent(instance.instanceId),
                    ),
                  const SizedBox(width: Spacing.sm),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // Error message
          if (instance.error != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: tokens.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(
                  instance.error!,
                  style: TextStyle(color: tokens.error, fontSize: FontSizes.xs),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],

          // Streaming content preview
          if (instance.status == AgentRunStatus.running &&
              instance.streamingContent.isNotEmpty &&
              !_expanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Text(
                instance.streamingContent.length > 100
                    ? '${instance.streamingContent.substring(instance.streamingContent.length - 100)}...'
                    : instance.streamingContent,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  fontFamily: 'JetBrains Mono',
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],

          // Expanded message log
          if (_expanded) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 250),
              margin: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              decoration: BoxDecoration(
                color: tokens.codeBlockBg,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: tokens.border.withValues(alpha: 0.3)),
              ),
              child:
                  instance.messages.isEmpty && instance.streamingContent.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Spacing.xl),
                      child: Center(
                        child: Text(
                          instance.status == AgentRunStatus.running
                              ? 'Thinking...'
                              : 'No messages',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: FontSizes.xs,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(Spacing.md),
                      children: [
                        ...instance.messages.map(
                          (msg) => _MessageLine(message: msg),
                        ),
                        if (instance.streamingContent.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: Spacing.sm),
                            child: Text(
                              instance.streamingContent,
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: FontSizes.xs,
                                fontFamily: 'JetBrains Mono',
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: Spacing.lg),
          ],
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

class _MessageLine extends ConsumerWidget {
  final dynamic message;

  const _MessageLine({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    final role = message.role as MessageRole;
    final content = message.content as String;

    final roleLabel = switch (role) {
      MessageRole.user => 'You',
      MessageRole.assistant => 'Agent',
      MessageRole.tool => 'Tool',
      MessageRole.system => 'System',
    };

    final roleColor = switch (role) {
      MessageRole.user => tokens.accent,
      MessageRole.assistant => tokens.success,
      MessageRole.tool => tokens.warning,
      MessageRole.system => tokens.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$roleLabel: ',
              style: TextStyle(
                color: roleColor,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrains Mono',
              ),
            ),
            TextSpan(
              text: content.length > 200
                  ? '${content.substring(0, 200)}...'
                  : content,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontFamily: 'JetBrains Mono',
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
