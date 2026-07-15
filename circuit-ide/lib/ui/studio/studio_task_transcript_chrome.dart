import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/studio_thread.dart';
import '../../models/studio_turn.dart';
import '../../state/agent_turn_runtime_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';

class StudioTaskTranscriptItemFrame extends StatelessWidget {
  final Widget child;

  const StudioTaskTranscriptItemFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: StudioLayoutContract.reviewWidth,
        ),
        child: child,
      ),
    );
  }
}

class StudioTaskTranscriptStatusHeader extends ConsumerWidget {
  final String label;
  final bool active;

  const StudioTaskTranscriptStatusHeader({
    super.key,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final showChevron = label.startsWith('Worked for');
    return Semantics(
      container: true,
      label: 'Task status: $label',
      liveRegion: active,
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: tokens.textMuted.withValues(alpha: active ? 0.9 : 0.74),
              fontSize: FontSizes.xs,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 3),
            Icon(
              StudioIcons.chevronRight,
              size: 13,
              color: tokens.textMuted.withValues(alpha: 0.54),
            ),
          ],
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Container(
              height: 1,
              color: tokens.studioDivider.withValues(alpha: 0.54),
            ),
          ),
        ],
      ),
    );
  }
}

class StudioConversationCompactionCard extends ConsumerWidget {
  final String? threadId;
  final StudioConversationCompaction compaction;

  const StudioConversationCompactionCard({
    super.key,
    required this.threadId,
    required this.compaction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final sourceLabel =
        '${compaction.sourceTurnIds.length} source turn${compaction.sourceTurnIds.length == 1 ? '' : 's'}';
    return Semantics(
      container: true,
      label:
          'Conversation compaction for $sourceLabel. ${compaction.restored ? 'Source turns restored to model history.' : 'Read-only summary is active.'}',
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: StudioLayoutContract.proseWidth,
        ),
        decoration: BoxDecoration(
          color: tokens.studioActivityRow.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.56),
          ),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(
            Spacing.md,
            0,
            Spacing.md,
            Spacing.sm,
          ),
          leading: Icon(
            StudioIcons.historyToggleOffOutlined,
            color: tokens.textMuted,
            size: 17,
          ),
          title: Text(
            compaction.restored
                ? 'Historical turns restored'
                : 'Older conversation compacted',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.sm,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '$sourceLabel · ~${compaction.sourceTokenEstimate} source tokens',
            style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                compaction.summary,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Sources: ${compaction.sourceTurnIds.join(', ')}',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
              ),
            ),
            if (!compaction.restored && threadId != null) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => ref
                      .read(studioThreadProvider.notifier)
                      .restoreConversationCompaction(threadId!, compaction.id),
                  icon: const Icon(StudioIcons.restore, size: 15),
                  label: const Text('Restore source turns to model history'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StudioTurnApprovalCard extends ConsumerWidget {
  final StudioTurnEvent event;

  const StudioTurnApprovalCard({super.key, required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final approvalId = event.approvalId;
    final isPending = event.approvalState == ApprovalRequestState.pending;
    final statusLabel = switch (event.approvalState) {
      ApprovalRequestState.approved => 'Approved',
      ApprovalRequestState.rejected => 'Rejected',
      ApprovalRequestState.expired => 'Expired',
      ApprovalRequestState.pending || null => 'Approval needed',
    };
    final toolLabel =
        event.toolName?.replaceAll('_', ' ') ?? 'protected action';
    return Semantics(
      container: true,
      label:
          '$statusLabel: $toolLabel. ${event.approvalPreview ?? event.detail}',
      liveRegion: isPending,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.lg),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: StudioLayoutContract.reviewWidth,
          ),
          decoration: BoxDecoration(
            color: tokens.studioActivityRow.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isPending
                  ? tokens.warning.withValues(alpha: 0.22)
                  : tokens.studioDivider.withValues(alpha: 0.44),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 10, 10, 6),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tokens.bgDark.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        isPending
                            ? StudioIcons.shieldOutlined
                            : StudioIcons.taskAltOutlined,
                        color: isPending ? tokens.warning : tokens.textMuted,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: FontSizes.sm,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isPending)
                      Text(
                        'Review required',
                        style: TextStyle(
                          color: tokens.warning,
                          fontSize: FontSizes.xs,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Text(
                  event.toolName == null
                      ? 'Circuit wants approval for a protected action.'
                      : 'Circuit wants to use ${event.toolName!.replaceAll('_', ' ')}.',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.24,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surfaceInset.withValues(alpha: 0.54),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: tokens.studioDivider.withValues(alpha: 0.46),
                    ),
                  ),
                  child: SelectableText(
                    event.approvalPreview ?? event.detail,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      height: 1.36,
                      fontFamily: EditorDefaults.studioMonospaceFontFamily,
                    ),
                  ),
                ),
              ),
              if (event.approvalWarnings.isNotEmpty) ...[
                const SizedBox(height: Spacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final warning in event.approvalWarnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            warning,
                            style: TextStyle(
                              color: tokens.error,
                              fontSize: FontSizes.xs,
                              height: 1.25,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: tokens.surfacePanel.withValues(alpha: 0.13),
                  border: Border(
                    top: BorderSide(
                      color: tokens.studioDivider.withValues(alpha: 0.42),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(13, 6, 10, 6),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  runSpacing: Spacing.sm,
                  spacing: Spacing.sm,
                  children: [
                    TextButton(
                      style: _approvalTextActionStyle(tokens),
                      onPressed: isPending && approvalId != null
                          ? () => ref
                                .read(agentTurnRuntimeProvider.notifier)
                                .rejectApproval(approvalId)
                          : null,
                      child: const Text('Reject'),
                    ),
                    OutlinedButton.icon(
                      style: _approvalSecondaryActionStyle(tokens),
                      onPressed: isPending && approvalId != null
                          ? () => ref
                                .read(agentTurnRuntimeProvider.notifier)
                                .approveForTurn(approvalId)
                          : null,
                      icon: const Icon(StudioIcons.taskAltOutlined, size: 14),
                      label: const Text('Approve for this turn'),
                    ),
                    FilledButton(
                      style: _approvalPrimaryActionStyle(tokens),
                      onPressed: isPending && approvalId != null
                          ? () => ref
                                .read(agentTurnRuntimeProvider.notifier)
                                .approveOnce(approvalId)
                          : null,
                      child: const Text('Approve once'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ButtonStyle _approvalPrimaryActionStyle(ThemeTokens tokens) {
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    visualDensity: VisualDensity.compact,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

ButtonStyle _approvalSecondaryActionStyle(ThemeTokens tokens) {
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    visualDensity: VisualDensity.compact,
    foregroundColor: tokens.textSecondary,
    side: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.58)),
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}

ButtonStyle _approvalTextActionStyle(ThemeTokens tokens) {
  return TextButton.styleFrom(
    minimumSize: const Size(0, 24),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    visualDensity: VisualDensity.compact,
    foregroundColor: tokens.textSecondary,
    textStyle: const TextStyle(
      fontSize: FontSizes.xs,
      fontWeight: FontWeight.w600,
      height: 1.0,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
  );
}
