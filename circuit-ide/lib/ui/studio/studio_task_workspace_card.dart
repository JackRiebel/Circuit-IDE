import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/agent_workspace.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/theme_provider.dart';

/// Keeps worktree isolation and handoff controls independent from transcript
/// rendering so a workspace action cannot rebuild the message list.
class StudioTaskWorkspaceCard extends ConsumerWidget {
  final AgentTask task;

  const StudioTaskWorkspaceCard({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final isolated = task.hasUsableIsolatedWorktree;
    final root = task.effectiveWorkspaceRoot ?? task.workspaceRoot;
    final label = root == null ? 'No workspace bound' : p.basename(root);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 9),
      decoration: BoxDecoration(
        color: tokens.surfaceInset.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.outlineSoft),
      ),
      child: Row(
        children: [
          Icon(
            isolated
                ? StudioIcons.accountTreeOutlined
                : StudioIcons.computerOutlined,
            size: 16,
            color: isolated ? tokens.accent : tokens.textMuted,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isolated ? 'Isolated worktree' : 'Current workspace',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  isolated ? '${task.worktreeBranch} · $label' : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                  ),
                ),
              ],
            ),
          ),
          if (!isolated)
            TextButton.icon(
              onPressed: root == null ? null : () => _isolate(context, ref),
              icon: const Icon(StudioIcons.addToQueueOutlined, size: 15),
              label: const Text('Isolate'),
            )
          else ...[
            TextButton(
              onPressed: () => ref
                  .read(agentWorkspaceProvider.notifier)
                  .useCurrentWorkspace(task.id),
              child: const Text('Use local'),
            ),
            TextButton.icon(
              onPressed: () => _handoff(context, ref),
              icon: const Icon(StudioIcons.callMergeOutlined, size: 15),
              label: const Text('Review handoff'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _isolate(BuildContext context, WidgetRef ref) async {
    final updated = await ref
        .read(agentWorkspaceProvider.notifier)
        .createIsolatedWorktree(task.id);
    if (!context.mounted) return;
    final message = updated == null
        ? ref.read(agentWorkspaceProvider).error ??
              'Could not create an isolated worktree.'
        : 'Task is now running in ${updated.worktreeBranch}.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handoff(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(agentWorkspaceProvider.notifier);
    final preview = await controller.previewWorktreeHandoff(task.id);
    if (!context.mounted || preview == null) return;
    if (!preview.canApply) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(preview.blockedReason ?? preview.summary)),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apply isolated task result?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: StudioLayoutContract.taskDecisionDialogWidth,
            maxHeight: 480,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preview.summary),
                if (preview.changedPaths.isNotEmpty) ...[
                  const SizedBox(height: Spacing.sm),
                  Text('Files: ${preview.changedPaths.join(', ')}'),
                ],
                if (preview.diffPreview.trim().isNotEmpty) ...[
                  const SizedBox(height: Spacing.md),
                  SelectableText(
                    preview.diffPreview.length > 12000
                        ? '${preview.diffPreview.substring(0, 12000)}\n\n…diff preview truncated'
                        : preview.diffPreview,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: FontSizes.xs,
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.md),
                const Text(
                  'This creates a reviewed task commit when needed, then merges the task branch into a clean local workspace. The worktree is retained for audit.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apply handoff'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await controller.applyWorktreeHandoff(
      task.id,
      preview,
      confirmed: true,
    );
    if (!context.mounted || result == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.evidence)));
  }
}
