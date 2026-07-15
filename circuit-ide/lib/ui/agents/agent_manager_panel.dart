import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_config_model.dart';
import '../../models/studio_shell.dart';
import '../../models/turn_intent.dart';
import '../../state/agent_manager_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'agent_config_dialog.dart';
import 'running_agent_card.dart';
import '../studio/studio_message_sender.dart';

class AgentManagerPanel extends ConsumerWidget {
  const AgentManagerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final managerState = ref.watch(agentManagerProvider);

    if (managerState.isLoading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
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
            trailing:
                managerState.running.values.any(
                  (i) => i.status == AgentRunStatus.running,
                )
                ? _SmallButton(
                    label: 'Cancel All',
                    icon: Icons.stop,
                    color: tokens.error,
                    onTap: () =>
                        ref.read(agentManagerProvider.notifier).cancelAll(),
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
                  .map(
                    (instance) => RunningAgentCard(
                      key: ValueKey(instance.instanceId),
                      instance: instance,
                    ),
                  )
                  .toList(),
            ),
          ),
          Divider(height: 1, color: tokens.border.withValues(alpha: 0.3)),
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
                      'Create an agent with a custom system prompt,\nbounded tools, and a model, then select it in Studio.',
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
                          borderRadius: BorderRadius.circular(Radii.md),
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

class _AgentConfigCard extends ConsumerWidget {
  final AgentConfigModel config;

  const _AgentConfigCard({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final risk = config.riskAssessment;
    final evaluation = config.evaluationReport;
    final requestedTools = config.allowedTools.toList()..sort();
    final requestedConnectors = config.allowedConnectors.toList()..sort();

    return Semantics(
      container: true,
      label:
          'Agent ${config.name}, ${config.enabled ? 'enabled' : 'disabled'}, ${risk.level} risk',
      child: Container(
        margin: const EdgeInsets.only(bottom: Spacing.md),
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: tokens.bgLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: tokens.border.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy_outlined, size: 14, color: tokens.accent),
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
                _LibraryPill(
                  label: config.enabled ? 'Enabled' : 'Disabled',
                  color: config.enabled ? tokens.success : tokens.textMuted,
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                _LibraryPill(
                  label: 'v${config.author.revision}',
                  color: tokens.textMuted,
                ),
                _LibraryPill(label: config.model, color: tokens.textMuted),
                _LibraryPill(
                  label: '${risk.level} risk',
                  color: _riskColor(tokens, risk.level),
                ),
                _LibraryPill(
                  label: evaluation.passedGate
                      ? 'Eval ${evaluation.passed}/${evaluation.total}'
                      : 'Eval blocked',
                  color: evaluation.passedGate ? tokens.success : tokens.error,
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
            const SizedBox(height: Spacing.md),
            _CapabilitySummary(
              label: 'Requested tools',
              values: requestedTools,
              emptyLabel: 'No tools requested',
              tokens: tokens,
            ),
            const SizedBox(height: Spacing.xs),
            _CapabilitySummary(
              label: 'Requested connectors',
              values: requestedConnectors,
              emptyLabel: 'None (connectors are unavailable to custom agents)',
              tokens: tokens,
            ),
            const SizedBox(height: Spacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: _riskColor(tokens, risk.level).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text(
                risk.reasons.join(' '),
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xxs,
                  height: 1.35,
                ),
              ),
            ),
            if (!evaluation.passedGate) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                evaluation.failures.first,
                style: TextStyle(color: tokens.error, fontSize: FontSizes.xxs),
              ),
            ],
            const SizedBox(height: Spacing.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                _ActionBtn(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  color: tokens.textMuted,
                  onTap: () => showAgentConfigDialog(context, existing: config),
                ),
                _ActionBtn(
                  icon: Icons.content_copy_outlined,
                  label: 'Clone',
                  color: tokens.textMuted,
                  onTap: () => _clone(context, ref),
                ),
                _ActionBtn(
                  icon: config.enabled
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  label: config.enabled ? 'Disable' : 'Enable',
                  color: config.enabled ? tokens.textMuted : tokens.success,
                  onTap: () => _changeEnabled(context, ref),
                ),
                _ActionBtn(
                  icon: Icons.science_outlined,
                  label: 'Test in Studio',
                  color: config.enabled ? tokens.accent : tokens.textDisabled,
                  onTap: () => _testInStudio(context, ref),
                ),
                _ActionBtn(
                  icon: Icons.open_in_new,
                  label: 'Use in Studio',
                  color: config.enabled ? tokens.success : tokens.textDisabled,
                  onTap: () => _useInStudio(context, ref),
                ),
                _ActionBtn(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: tokens.error,
                  onTap: () => ref
                      .read(agentManagerProvider.notifier)
                      .deleteConfig(config.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clone(BuildContext context, WidgetRef ref) async {
    final clone = await ref
        .read(agentManagerProvider.notifier)
        .cloneConfig(config.id);
    if (!context.mounted || clone == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${clone.name} was created disabled for review.')),
    );
  }

  Future<void> _changeEnabled(BuildContext context, WidgetRef ref) async {
    if (config.enabled) {
      final error = await ref
          .read(agentManagerProvider.notifier)
          .setConfigEnabled(config.id, false);
      if (!context.mounted) return;
      if (error == null &&
          ref.read(studioShellProvider).customAgentId == config.id) {
        ref.read(studioShellProvider.notifier).setCustomAgent(null);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? '${config.name} is disabled.')),
      );
      return;
    }

    final approved = await _confirmEnable(context, config);
    if (!approved || !context.mounted) return;
    final error = await ref
        .read(agentManagerProvider.notifier)
        .setConfigEnabled(config.id, true);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '${config.name} is enabled for Studio.')),
    );
  }

  Future<void> _useInStudio(BuildContext context, WidgetRef ref) async {
    if (!config.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enable and review this agent before selecting it in Studio.',
          ),
        ),
      );
      return;
    }
    ref.read(studioShellProvider.notifier).setCustomAgent(config.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${config.name} is selected for the next Studio request.',
        ),
      ),
    );
  }

  Future<void> _testInStudio(BuildContext context, WidgetRef ref) async {
    if (!config.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enable and review this agent before running a Studio test.',
          ),
        ),
      );
      return;
    }
    final request = await _showTestDialog(context, config);
    if (request == null || !context.mounted) return;
    final shell = ref.read(studioShellProvider.notifier);
    shell
      ..setCustomAgent(config.id)
      ..setPromptMode(_promptModeFor(request.intent))
      ..setPlanModeEnabled(request.intent == TurnIntent.plan);
    final result = await sendStudioMessage(
      ref,
      request.prompt,
      threadTitle: 'Agent test: ${config.name}',
    );
    if (!context.mounted) return;
    final message = switch (result.status) {
      StudioSendStatus.sent ||
      StudioSendStatus.completed => 'Studio test started for ${config.name}.',
      _ => result.error ?? 'Studio test could not start.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LibraryPill extends StatelessWidget {
  final String label;
  final Color color;

  const _LibraryPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: FontSizes.xxs,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }
}

class _CapabilitySummary extends StatelessWidget {
  final String label;
  final List<String> values;
  final String emptyLabel;
  final ThemeTokens tokens;

  const _CapabilitySummary({
    required this.label,
    required this.values,
    required this.emptyLabel,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final value = values.isEmpty ? emptyLabel : values.join(', ');
    return Text(
      '$label: $value',
      style: TextStyle(
        color: tokens.textMuted,
        fontSize: FontSizes.xxs,
        height: 1.3,
      ),
    );
  }
}

Color _riskColor(ThemeTokens tokens, String level) {
  return switch (level) {
    'High' => tokens.error,
    'Medium' => Colors.orange,
    'Blocked' => tokens.error,
    _ => tokens.success,
  };
}

class _AgentTestRequest {
  final TurnIntent intent;
  final String prompt;

  const _AgentTestRequest({required this.intent, required this.prompt});
}

Future<bool> _confirmEnable(
  BuildContext context,
  AgentConfigModel config,
) async {
  final risk = config.riskAssessment;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Enable ${config.name}?'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Requested tools: ${config.allowedTools.isEmpty ? 'None' : (config.allowedTools.toList()..sort()).join(', ')}',
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Requested connectors: ${config.allowedConnectors.isEmpty ? 'None' : (config.allowedConnectors.toList()..sort()).join(', ')}',
                ),
                const SizedBox(height: Spacing.sm),
                Text('${risk.level} risk: ${risk.reasons.join(' ')}'),
                const SizedBox(height: Spacing.sm),
                Text(
                  config.evaluationReport.passedGate
                      ? 'Activation evaluation: ${config.evaluationReport.passed}/${config.evaluationReport.total} fixtures pass at the required threshold.'
                      : 'Activation evaluation is blocked: ${config.evaluationReport.failures.first}',
                ),
                const SizedBox(height: Spacing.sm),
                const Text(
                  'Every tool action remains subject to Studio approval and policy checks.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enable after review'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<_AgentTestRequest?> _showTestDialog(
  BuildContext context,
  AgentConfigModel config,
) async {
  final intents = config.allowedIntents.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (intents.isEmpty) return null;
  final controller = TextEditingController(text: _testPromptFor(intents.first));
  return showDialog<_AgentTestRequest>(
    context: context,
    builder: (dialogContext) {
      var selectedIntent = intents.first;
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Test ${config.name} in Studio'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This starts a normal request-local Studio turn. Tool and patch approvals remain on.',
                ),
                const SizedBox(height: Spacing.md),
                DropdownButton<TurnIntent>(
                  value: selectedIntent,
                  isExpanded: true,
                  items: intents
                      .map(
                        (intent) => DropdownMenuItem(
                          value: intent,
                          child: Text(_intentLabel(intent)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (intent) {
                    if (intent == null) return;
                    setDialogState(() {
                      selectedIntent = intent;
                      controller.text = _testPromptFor(intent);
                    });
                  },
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Test prompt'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final prompt = controller.text.trim();
                if (prompt.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  _AgentTestRequest(intent: selectedIntent, prompt: prompt),
                );
              },
              child: const Text('Run Studio test'),
            ),
          ],
        ),
      );
    },
  ).whenComplete(controller.dispose);
}

String _testPromptFor(TurnIntent intent) {
  return switch (intent) {
    TurnIntent.chat => 'Hello',
    TurnIntent.ask =>
      'Explain your declared purpose, capability limits, and expected output. Do not modify files.',
    TurnIntent.plan =>
      'Create a reviewable plan for a small change. Do not modify files.',
    TurnIntent.code =>
      'Add a clearly labeled test-only TODO to a draft patch and return the patch proposal for review.',
    TurnIntent.review =>
      'Review the current changes. Do not modify files; return evidence and unresolved risks.',
    TurnIntent.verify =>
      'Run the configured verification checks and report the results. Do not modify files.',
  };
}

StudioPromptMode _promptModeFor(TurnIntent intent) {
  return switch (intent) {
    TurnIntent.review => StudioPromptMode.review,
    TurnIntent.code => StudioPromptMode.code,
    _ => StudioPromptMode.ask,
  };
}

String _intentLabel(TurnIntent intent) {
  return switch (intent) {
    TurnIntent.chat => 'Chat',
    TurnIntent.ask => 'Ask',
    TurnIntent.plan => 'Plan',
    TurnIntent.code => 'Code',
    TurnIntent.review => 'Review',
    TurnIntent.verify => 'Verify',
  };
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
