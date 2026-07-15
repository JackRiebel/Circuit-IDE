import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/context_pack.dart';
import '../../state/context_pack_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';

/// Read-only and preference-management projection of the current turn context.
///
/// Drawer navigation remains in [StudioRightDrawer]. This module owns the
/// context budget, retrieval evidence, and project-scoped include/exclude
/// controls so those state dependencies do not leak into the drawer facade.
class StudioContextDrawer extends ConsumerWidget {
  final AgentTask? task;

  const StudioContextDrawer({super.key, this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final thread = ref.watch(studioThreadProvider).threadForTaskView(task?.id);
    final pack = task == null || thread != null
        ? ref.watch(contextPackProvider)
        : null;
    final persistedRetrieval = thread?.latestContextRetrieval;
    final retrieval = pack?.retrievalResult ?? persistedRetrieval;
    final latestTurn = thread == null || thread.turns.isEmpty
        ? null
        : thread.turns.last;
    final intentRouting = latestTurn?.intentRouting;
    final canPersistContextPreference =
        ref.watch(fileTreeProvider).rootPath != null;
    ref.watch(contextPreferenceRevisionProvider);
    if (pack == null && retrieval == null) {
      return _ContextEmptyState(
        icon: StudioIcons.inventory2Outlined,
        title: 'No context yet',
        detail:
            'Context details appear here after Circuit builds a task context.',
        actionLabel: 'Start a task',
        onAction: () => ref.read(studioShellProvider.notifier).openHome(),
      );
    }

    final removedIds = pack?.removedItemIds.toSet() ?? const <String>{};
    final included =
        retrieval?.includedCandidates
            .where((candidate) => !removedIds.contains(candidate.id))
            .toList() ??
        const [];
    final includedIds = included.map((candidate) => candidate.id).toSet();
    final effectiveInstructionItems =
        pack?.instructionItems
            .where(
              (item) =>
                  !removedIds.contains(item.id) &&
                  includedIds.contains(item.id),
            )
            .toList(growable: false) ??
        const <ContextPackItem>[];
    final effectiveInstructionIds = effectiveInstructionItems
        .map((item) => item.id)
        .toSet();
    final primaryIncluded = included
        .where((candidate) => !effectiveInstructionIds.contains(candidate.id))
        .toList(growable: false);
    final omitted = retrieval?.omittedCandidates ?? const [];
    final visibleIds =
        pack?.visibleItems.map((item) => item.id).toSet() ?? const <String>{};
    final visibleItems = pack?.visibleItems ?? const <ContextPackItem>[];
    final removedItems =
        pack?.allItems
            .where((item) => removedIds.contains(item.id))
            .toList(growable: false) ??
        const <ContextPackItem>[];
    final includeNextPaths = canPersistContextPreference
        ? ref
              .read(contextPackProvider.notifier)
              .includeNextTimePathsForCurrentRoot()
        : const <String>{};
    final excludedPaths = canPersistContextPreference
        ? ref.read(contextPackProvider.notifier).excludedPathsForCurrentRoot()
        : const <String>{};

    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Text(
          'Context budget',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        if (pack != null)
          _ContextBudgetCard(pack: pack)
        else
          _ContextBudgetSnapshot(retrieval: retrieval!),
        if (intentRouting != null) ...[
          const SizedBox(height: Spacing.lg),
          const _ContextSectionTitle(title: 'Intent routing', count: 1),
          const SizedBox(height: Spacing.xs),
          _ContextItemRow(
            title:
                '${intentRouting.intent.name} · ${intentRouting.confidenceLabel}',
            subtitle: '${intentRouting.source.name}: ${intentRouting.reason}',
            score: null,
            removable: false,
          ),
        ],
        if (canPersistContextPreference &&
            (includeNextPaths.isNotEmpty || excludedPaths.isNotEmpty)) ...[
          const SizedBox(height: Spacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => ref
                  .read(contextPackProvider.notifier)
                  .resetProjectContextChoices(),
              child: const Text('Reset saved context choices'),
            ),
          ),
        ],
        if (retrieval?.warnings.isNotEmpty == true) ...[
          const SizedBox(height: Spacing.md),
          for (final warning in retrieval!.warnings)
            _ContextWarning(message: warning.message),
        ],
        if (effectiveInstructionItems.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          _ContextSectionTitle(
            title: 'Effective instructions',
            count: effectiveInstructionItems.length,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Runtime policy → global CIRCUIT.md → workspace and nearest-directory instructions → matched scoped rules. Later scoped guidance refines earlier guidance; CircuitCode policy always wins.',
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
          ),
          const SizedBox(height: Spacing.sm),
          for (final item in effectiveInstructionItems)
            _ContextItemRow(
              title: item.title,
              subtitle: _contextSubtitle(
                path: item.source,
                reason: item.retrievalReason ?? 'effective instruction',
                tokens: item.estimatedTokens,
              ),
              score: item.retrievalScore,
              removable: item.removable,
              onRemove: item.removable && pack != null
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .removeItem(item.id)
                  : null,
            ),
        ],
        const SizedBox(height: Spacing.lg),
        _ContextSectionTitle(
          title: 'Included',
          count: included.isEmpty
              ? visibleItems.length
              : primaryIncluded.length,
        ),
        const SizedBox(height: Spacing.sm),
        if (included.isEmpty)
          for (final item in visibleItems)
            _ContextItemRow(
              title: item.title,
              subtitle: _contextSubtitle(
                path: item.source,
                reason: item.sourceKind.name,
                tokens: item.estimatedTokens,
              ),
              score: null,
              removable: item.removable,
              onRemove: item.removable && pack != null
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .removeItem(item.id)
                  : null,
            )
        else
          for (final candidate in primaryIncluded)
            _ContextItemRow(
              title: candidate.title,
              subtitle: _contextSubtitle(
                path: candidate.path,
                reason: candidate.reason,
                tokens: candidate.estimatedTokens,
              ),
              score: candidate.score,
              removable: visibleIds.contains(candidate.id),
              onRemove: visibleIds.contains(candidate.id)
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .removeItem(candidate.id)
                  : null,
              actionLabel:
                  candidate.path != null &&
                      candidate.sourceKind == ContextPackSourceKind.editor &&
                      includeNextPaths.contains(candidate.path)
                  ? 'Remove next'
                  : candidate.path != null &&
                        candidate.sourceKind == ContextPackSourceKind.editor &&
                        canPersistContextPreference
                  ? 'Exclude project'
                  : null,
              onAction:
                  candidate.path != null &&
                      candidate.sourceKind == ContextPackSourceKind.editor &&
                      includeNextPaths.contains(candidate.path)
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .removeIncludeNextTime(candidate.path!)
                  : candidate.path != null &&
                        candidate.sourceKind == ContextPackSourceKind.editor &&
                        canPersistContextPreference
                  ? () => ref
                        .read(contextPackProvider.notifier)
                        .excludeForProject(candidate.path!)
                  : null,
            ),
        if (removedItems.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          _ContextSectionTitle(
            title: 'Removed from next send',
            count: removedItems.length,
          ),
          const SizedBox(height: Spacing.sm),
          for (final item in removedItems)
            _ContextItemRow(
              title: item.title,
              subtitle: _contextSubtitle(
                path: item.source,
                reason: 'Removed before send',
                tokens: item.estimatedTokens,
              ),
              score: null,
              removable: false,
              muted: true,
              actionLabel: 'Restore',
              onAction: pack == null
                  ? null
                  : () => ref
                        .read(contextPackProvider.notifier)
                        .restoreItem(item.id),
            ),
        ],
        if (omitted.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          _ContextSectionTitle(title: 'Omitted', count: omitted.length),
          const SizedBox(height: Spacing.sm),
          for (final candidate in omitted)
            _ContextItemRow(
              title: candidate.title,
              subtitle: _contextSubtitle(
                path: candidate.path,
                reason: candidate.reason,
                tokens: candidate.estimatedTokens,
              ),
              score: candidate.score,
              removable: false,
              muted: true,
              actionLabel:
                  candidate.path != null &&
                      canPersistContextPreference &&
                      includeNextPaths.contains(candidate.path)
                  ? 'Remove next'
                  : candidate.path != null &&
                        canPersistContextPreference &&
                        excludedPaths.contains(candidate.path)
                  ? 'Include again'
                  : candidate.path != null && canPersistContextPreference
                  ? 'Include next'
                  : null,
              onAction: candidate.path != null && canPersistContextPreference
                  ? includeNextPaths.contains(candidate.path)
                        ? () => ref
                              .read(contextPackProvider.notifier)
                              .removeIncludeNextTime(candidate.path!)
                        : excludedPaths.contains(candidate.path)
                        ? () => ref
                              .read(contextPackProvider.notifier)
                              .removeProjectExclusion(candidate.path!)
                        : () => ref
                              .read(contextPackProvider.notifier)
                              .includeNextTime(candidate.path!)
                  : null,
            ),
        ],
      ],
    );
  }
}

String _contextSubtitle({
  required String? path,
  required String reason,
  required int tokens,
}) {
  return [
    if (path != null && path.trim().isNotEmpty) path,
    reason,
    '~$tokens tokens',
  ].join(' · ');
}

class _ContextBudgetCard extends ConsumerWidget {
  final ContextPack pack;

  const _ContextBudgetCard({required this.pack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = pack.retrievalResult?.budget;
    final used = pack.estimatedTokens;
    final available = budget?.availableForContext;
    final label = available == null
        ? '~$used tokens'
        : '~$used / ~$available context tokens';
    final percent = available == null || available == 0
        ? 0.0
        : (used / available).clamp(0.0, 1.0);
    return _ContextBudgetSurface(label: label, percent: percent);
  }
}

class _ContextBudgetSnapshot extends ConsumerWidget {
  final ContextRetrievalResult retrieval;

  const _ContextBudgetSnapshot({required this.retrieval});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = retrieval.budget;
    final label =
        '~${budget.usedTokens} / ~${budget.availableForContext} context tokens · saved with turn';
    final percent = budget.availableForContext == 0
        ? 0.0
        : (budget.usedTokens / budget.availableForContext).clamp(0.0, 1.0);
    return _ContextBudgetSurface(label: label, percent: percent);
  }
}

class _ContextBudgetSurface extends ConsumerWidget {
  final String label;
  final double percent;

  const _ContextBudgetSurface({required this.label, required this.percent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioPanel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.sm,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: percent,
              backgroundColor: tokens.surfaceInset,
              color: percent > 0.92 ? tokens.warning : tokens.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextSectionTitle extends ConsumerWidget {
  final String title;
  final int count;

  const _ContextSectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xs,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ContextWarning extends ConsumerWidget {
  final String message;

  const _ContextWarning({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            StudioIcons.warningAmberRounded,
            size: 14,
            color: tokens.warning,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: tokens.warning, fontSize: FontSizes.xs),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextItemRow extends ConsumerWidget {
  final String title;
  final String subtitle;
  final int? score;
  final bool removable;
  final bool muted;
  final VoidCallback? onRemove;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ContextItemRow({
    required this.title,
    required this.subtitle,
    required this.score,
    required this.removable,
    this.muted = false,
    this.onRemove,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final color = muted ? tokens.textMuted : tokens.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
      decoration: BoxDecoration(
        color: tokens.studioHover.withValues(alpha: muted ? 0.16 : 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.42)),
      ),
      child: Row(
        children: [
          Icon(
            muted
                ? StudioIcons.removeCircleOutline
                : StudioIcons.checkCircleOutline,
            color: muted ? tokens.textMuted : tokens.success,
            size: 14,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (score != null)
            Padding(
              padding: const EdgeInsets.only(left: Spacing.sm),
              child: Text(
                '$score',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (removable)
            StudioChromeIconButton(
              tooltip: 'Remove from next send',
              onTap: onRemove,
              icon: StudioIcons.close,
              width: 22,
              height: 22,
              iconSize: 14,
            ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: tokens.textSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xs,
                  vertical: 0,
                ),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
                textStyle: const TextStyle(
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _ContextEmptyState extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ContextEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon,
                color: tokens.textMuted.withValues(alpha: 0.72),
                size: 14,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.28,
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: Spacing.xs),
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: tokens.textSecondary,
                        textStyle: const TextStyle(
                          fontSize: FontSizes.xs,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
