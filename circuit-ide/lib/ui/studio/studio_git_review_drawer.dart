import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/git_models.dart';
import '../../state/git_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';
import 'studio_file_sources_drawer.dart';
import 'studio_virtualized_text_document.dart';

/// Read-only fallback for repository changes when a task patch is unavailable.
class StudioGitReviewDrawer extends ConsumerWidget {
  final String? selectedPath;
  final bool selectedStaged;
  final void Function(String path, bool staged) onSelect;

  const StudioGitReviewDrawer({
    super.key,
    required this.selectedPath,
    required this.selectedStaged,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final git = ref.watch(gitProvider).status;
    final changes = <_ReviewChange>[
      for (final change in git.staged)
        _ReviewChange(change: change, staged: true),
      for (final change in git.unstaged)
        _ReviewChange(change: change, staged: false),
      for (final change in git.untracked)
        _ReviewChange(change: change, staged: false),
    ];
    if (changes.isEmpty) {
      return _GitReviewEmptyState(
        icon: StudioIcons.differenceOutlined,
        title: 'No changes',
        detail: 'Repo changes and AI patch reviews appear here.',
        actionLabel: 'Start a task',
        onAction: () => ref.read(studioShellProvider.notifier).openHome(),
      );
    }
    final selected =
        changes
            .where((change) => change.change.path == selectedPath)
            .firstOrNull ??
        changes.first;
    final staged = selectedPath == null ? selected.staged : selectedStaged;
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Repository changes',
                style: TextStyle(
                  color: ref.watch(themeProvider).textSecondary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => ref.read(gitProvider.notifier).refresh(),
              icon: const Icon(StudioIcons.refresh, size: 14),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        for (final change in changes)
          _GitChangeRow(
            change: change,
            selected: change.change.path == selected.change.path,
            onTap: () => onSelect(change.change.path, change.staged),
          ),
        const SizedBox(height: Spacing.lg),
        _GitReviewNotice(path: selected.change.path),
        const SizedBox(height: Spacing.md),
        FutureBuilder<String>(
          future: ref
              .read(gitProvider.notifier)
              .getDiff(path: selected.change.path, staged: staged),
          builder: (context, snapshot) {
            return _GitDiffDocumentView(
              title: selected.change.path,
              text: snapshot.data ?? 'Loading diff...',
              embedded: true,
            );
          },
        ),
      ],
    );
  }
}

class _ReviewChange {
  final GitFileChange change;
  final bool staged;

  const _ReviewChange({required this.change, required this.staged});
}

class _GitChangeRow extends ConsumerWidget {
  final _ReviewChange change;
  final bool selected;
  final VoidCallback onTap;

  const _GitChangeRow({
    required this.change,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StudioDrawerListRow(
      icon: change.staged
          ? StudioIcons.checkBox
          : StudioIcons.checkBoxOutlineBlank,
      title: change.change.path,
      subtitle:
          '${change.change.type.label}${change.staged ? ' · staged' : ''}',
      selected: selected,
      onTap: onTap,
    );
  }
}

class _GitReviewNotice extends ConsumerWidget {
  final String path;

  const _GitReviewNotice({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.studioHover.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.studioDivider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Flexible(
            child: Text(
              'Review only',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GitReviewEmptyState extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;

  const _GitReviewEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: tokens.surfaceInset.withValues(alpha: 0.54),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: tokens.studioDivider.withValues(alpha: 0.62),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: tokens.textMuted, size: 20),
              const SizedBox(height: Spacing.sm),
              Text(
                title,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: Spacing.md),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GitDiffDocumentView extends ConsumerWidget {
  final String title;
  final String text;
  final bool embedded;

  const _GitDiffDocumentView({
    required this.title,
    required this.text,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final view = Container(
      decoration: BoxDecoration(
        color: tokens.surfaceInset.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.68)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.sm,
              Spacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: tokens.bgDark.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Icon(
                    StudioIcons.differenceOutlined,
                    color: tokens.textMuted,
                    size: 13,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xs,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.studioControl.withValues(alpha: 0.44),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    'Read only',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                StudioChromeIconButton(
                  tooltip: 'Copy',
                  onTap: () => Clipboard.setData(ClipboardData(text: text)),
                  icon: StudioIcons.copy,
                  width: 26,
                  height: 24,
                  iconSize: 14,
                ),
              ],
            ),
          ),
          Divider(
            color: tokens.studioDivider.withValues(alpha: 0.72),
            height: 1,
          ),
          Expanded(
            child: RepaintBoundary(
              child: StudioVirtualizedTextDocumentBody(
                text: text,
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.lg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (embedded) return SizedBox(height: 280, child: view);
    return Padding(padding: const EdgeInsets.all(Spacing.md), child: view);
  }
}
