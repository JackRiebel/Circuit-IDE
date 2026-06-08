import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/project_profile_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import '../../state/work_item_provider.dart';
import 'studio_task_card.dart';

class StudioProjectView extends ConsumerWidget {
  const StudioProjectView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final profile = ref.watch(projectProfileProvider);
    final workspace = ref.watch(agentWorkspaceProvider);
    final projectName = rootPath == null ? 'Circuit-IDE' : p.basename(rootPath);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.xxxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                projectName,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.display,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Cisco Circuit project studio',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.base,
                ),
              ),
              const SizedBox(height: Spacing.xxxl),
              _ProjectSummaryCard(),
              const SizedBox(height: Spacing.xl),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      final task = ref
                          .read(agentWorkspaceProvider.notifier)
                          .startTask(
                            goal:
                                'Investigate this project and propose the safest next coding step.',
                            profile: AgentTaskProfile.investigate,
                          );
                      ref.read(studioShellProvider.notifier).openTask(task.id);
                    },
                    icon: const Icon(Icons.play_arrow_outlined, size: 16),
                    label: const Text('Start task'),
                  ),
                  const SizedBox(width: Spacing.md),
                  OutlinedButton.icon(
                    onPressed: () => ref
                        .read(studioShellProvider.notifier)
                        .openAdvancedEditor(),
                    icon: const Icon(Icons.code, size: 16),
                    label: const Text('Open Advanced Editor'),
                  ),
                  const SizedBox(width: Spacing.md),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(
                      ref.read(workItemProvider.notifier).runVerification(),
                    ),
                    icon: const Icon(Icons.playlist_add_check, size: 16),
                    label: const Text('Run checks'),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xxxl),
              Text(
                'Active tasks',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.lg,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: Spacing.md),
              if (workspace.tasks.isEmpty)
                _EmptyProjectBlock()
              else
                for (final task in workspace.tasks.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: StudioTaskCard(
                      task: task,
                      projectLabel: projectName,
                      onTap: () {
                        ref
                            .read(agentWorkspaceProvider.notifier)
                            .selectTask(task.id);
                        ref
                            .read(studioShellProvider.notifier)
                            .openTask(task.id);
                      },
                    ),
                  ),
              if (profile.error != null) ...[
                const SizedBox(height: Spacing.lg),
                Text(
                  profile.error!,
                  style: TextStyle(color: tokens.error, fontSize: FontSizes.sm),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectSummaryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final profile = ref.watch(projectProfileProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.studioPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Row(
        children: [
          _SummaryStat(label: 'Stack', value: profile.primaryType.label),
          _SummaryStat(
            label: 'Entrypoints',
            value: profile.entrypoints.length.toString(),
          ),
          _SummaryStat(label: 'Changes', value: '${profile.changedFiles}'),
          _SummaryStat(
            label: 'Ready',
            value: profile.readiness.name,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends ConsumerWidget {
  final String label;
  final String value;
  final bool last;

  const _SummaryStat({
    required this.label,
    required this.value,
    this.last = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Expanded(
      child: Container(
        padding: EdgeInsets.only(right: last ? 0 : Spacing.xl),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(right: BorderSide(color: tokens.studioDivider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: FontSizes.lg,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProjectBlock extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: tokens.studioCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Text(
        'No active Circuit tasks yet. Start with a plain-English request.',
        style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.base),
      ),
    );
  }
}
