import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/reviewed_edit.dart';
import '../../state/patch_proposal_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';
import 'studio_git_review_drawer.dart';
import 'studio_patch_review_actions.dart';
import 'studio_patch_review_lookup.dart';
import 'studio_virtualized_text_document.dart';

/// Patch selection, diff projection, and review actions for the Diff drawer.
///
/// Drawer mode selection stays in [StudioRightDrawer], while this module owns
/// all patch-review state and interactions.
class StudioPatchReviewDrawer extends ConsumerStatefulWidget {
  final AgentTask? task;

  const StudioPatchReviewDrawer({super.key, this.task});

  @override
  ConsumerState<StudioPatchReviewDrawer> createState() =>
      _StudioPatchReviewDrawerState();
}

class _StudioPatchReviewDrawerState
    extends ConsumerState<StudioPatchReviewDrawer> {
  String? _selectedPath;
  bool _selectedStaged = false;

  @override
  Widget build(BuildContext context) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final patchState = ref.watch(patchProposalProvider);
    final thread = ref
        .watch(studioThreadProvider)
        .threadForTaskView(widget.task?.id);
    final patch = studioPatchForDrawer(
      patchState,
      drawer.diffId,
      thread: thread,
      taskId: widget.task?.id,
      selectedPath: drawer.patchFilePath,
    );
    if (patch == null) {
      if ((drawer.diffId ?? '').trim().isNotEmpty) {
        return _MissingPatchReviewDrawer(
          patchSetId: drawer.diffId!,
          selectedPath: drawer.patchFilePath,
        );
      }
      return StudioGitReviewDrawer(
        selectedPath: _selectedPath,
        selectedStaged: _selectedStaged,
        onSelect: (path, staged) {
          setState(() {
            _selectedPath = path;
            _selectedStaged = staged;
          });
        },
      );
    }
    final selectedPath = drawer.patchFilePath;
    return _PatchDiffReviewDrawer(
      patch: patch,
      selectedPath: selectedPath,
      diffText: _diffPreview(patch, selectedPath),
    );
  }

  String _diffPreview(ProposedPatchSet patch, String? selectedPath) {
    final edits = selectedPath == null
        ? patch.edits
        : patch.edits.where((edit) => edit.path == selectedPath).toList();
    if (edits.isEmpty) {
      if (patch.isPlanOnly) {
        return patch.planMarkdown ??
            patch.comparisonSummary ??
            'This plan does not include a file diff yet.';
      }
      return selectedPath == null
          ? 'No diff available yet.'
          : 'No diff available for $selectedPath.';
    }
    return edits
        .map((edit) {
          return [
            '--- ${edit.path}',
            '+++ ${edit.path}',
            if (edit.unifiedDiff?.isNotEmpty == true)
              edit.unifiedDiff!
            else
              _fallbackUnifiedDiff(edit),
          ].join('\n');
        })
        .join('\n\n');
  }
}

String _fallbackUnifiedDiff(ProposedFileEdit edit) {
  final before = edit.before ?? '';
  final after = edit.after ?? '';
  final beforeLines = _splitDiffLines(before);
  final afterLines = _splitDiffLines(after);
  return switch (edit.type) {
    ProposedFileEditType.create => [
      '@@ -0,0 +1,${afterLines.length} @@',
      for (final line in afterLines) '+$line',
    ].join('\n'),
    ProposedFileEditType.delete => [
      '@@ -1,${beforeLines.length} +0,0 @@',
      for (final line in beforeLines) '-$line',
    ].join('\n'),
    ProposedFileEditType.modify => _lineDiff(beforeLines, afterLines),
  };
}

List<String> _splitDiffLines(String value) {
  if (value.isEmpty) return const [];
  final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    return lines.sublist(0, lines.length - 1);
  }
  return lines;
}

String _lineDiff(List<String> before, List<String> after) {
  final rows = _diffRows(before, after);
  final result = <String>['@@ -1,${before.length} +1,${after.length} @@'];
  for (final row in rows) {
    switch (row.type) {
      case _DiffRowType.unchanged:
        result.add(' ${row.value}');
        break;
      case _DiffRowType.removed:
        result.add('-${row.value}');
        break;
      case _DiffRowType.added:
        result.add('+${row.value}');
        break;
    }
  }
  return result.join('\n');
}

List<_DiffRow> _diffRows(List<String> before, List<String> after) {
  final lcs = List.generate(
    before.length + 1,
    (_) => List<int>.filled(after.length + 1, 0),
  );
  for (var i = before.length - 1; i >= 0; i--) {
    for (var j = after.length - 1; j >= 0; j--) {
      lcs[i][j] = before[i] == after[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  final rows = <_DiffRow>[];
  var i = 0;
  var j = 0;
  while (i < before.length && j < after.length) {
    if (before[i] == after[j]) {
      rows.add(_DiffRow(_DiffRowType.unchanged, before[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      rows.add(_DiffRow(_DiffRowType.removed, before[i]));
      i++;
    } else {
      rows.add(_DiffRow(_DiffRowType.added, after[j]));
      j++;
    }
  }
  while (i < before.length) {
    rows.add(_DiffRow(_DiffRowType.removed, before[i]));
    i++;
  }
  while (j < after.length) {
    rows.add(_DiffRow(_DiffRowType.added, after[j]));
    j++;
  }
  return rows;
}

enum _DiffRowType { unchanged, removed, added }

class _DiffRow {
  final _DiffRowType type;
  final String value;

  const _DiffRow(this.type, this.value);
}

class _MissingPatchReviewDrawer extends ConsumerWidget {
  final String patchSetId;
  final String? selectedPath;

  const _MissingPatchReviewDrawer({
    required this.patchSetId,
    required this.selectedPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Center(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    StudioIcons.differenceOutlined,
                    size: 17,
                    color: tokens.textMuted,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Patch review unavailable',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.sm,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                selectedPath == null || selectedPath!.trim().isEmpty
                    ? 'Circuit could not find the selected patch review. It may have been dismissed, restored from older history, or not loaded for this thread yet.'
                    : 'Circuit could not find the selected patch review for $selectedPath. It may have been dismissed, restored from older history, or not loaded for this thread yet.',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              SelectableText(
                'Patch id: $patchSetId',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xs,
                  height: 1.3,
                  fontFamily: EditorDefaults.studioMonospaceFontFamily,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  OutlinedButton(
                    style: studioPatchSecondaryActionStyle(tokens),
                    onPressed: () => ref
                        .read(studioRightDrawerProvider.notifier)
                        .openRepositoryDiff(),
                    child: const Text('Show repo changes'),
                  ),
                  OutlinedButton(
                    style: studioPatchSecondaryActionStyle(tokens),
                    onPressed:
                        selectedPath == null || selectedPath!.trim().isEmpty
                        ? null
                        : () => ref
                              .read(studioRightDrawerProvider.notifier)
                              .openFile(selectedPath!),
                    child: const Text('Open current file'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatchDiffReviewDrawer extends ConsumerWidget {
  final ProposedPatchSet patch;
  final String? selectedPath;
  final String diffText;

  const _PatchDiffReviewDrawer({
    required this.patch,
    required this.selectedPath,
    required this.diffText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final edits = patch.edits;
    final effectiveSelectedPath = selectedPath ?? edits.firstOrNull?.path;
    final selectedEdit = effectiveSelectedPath == null
        ? null
        : edits.where((edit) => edit.path == effectiveSelectedPath).firstOrNull;
    final stats = _patchReviewStats(patch);
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceInset.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: tokens.studioDivider.withValues(alpha: 0.68),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      patch.isPlanOnly
                          ? StudioIcons.altRouteOutlined
                          : StudioIcons.differenceOutlined,
                      color: tokens.textMuted,
                      size: 13,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patch.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: FontSizes.xs,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: _formatFileCount(patch.fileCount)),
                              if (stats.additions > 0 || stats.deletions > 0)
                                TextSpan(
                                  text:
                                      '  +${stats.additions} -${stats.deletions}',
                                ),
                              if (patch.applyStatus != null)
                                TextSpan(text: '  ${patch.applyStatus!.name}'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: FontSizes.xs,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (effectiveSelectedPath != null) ...[
                    StudioChromeIconButton(
                      tooltip: 'Open current file',
                      onTap: () => ref
                          .read(studioRightDrawerProvider.notifier)
                          .openFile(effectiveSelectedPath),
                      icon: StudioIcons.openInNew,
                      width: 26,
                      height: 24,
                      iconSize: 14,
                    ),
                    const SizedBox(width: Spacing.xs),
                  ],
                  StudioChromeIconButton(
                    tooltip: 'Copy diff',
                    onTap: () =>
                        Clipboard.setData(ClipboardData(text: diffText)),
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
            StudioPatchReviewActionBar(patch: patch),
            Divider(
              color: tokens.studioDivider.withValues(alpha: 0.72),
              height: 1,
            ),
            if (edits.length > 1)
              SizedBox(
                height: 104,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  itemCount: edits.length,
                  separatorBuilder: (_, _) => Divider(
                    color: tokens.studioDivider.withValues(alpha: 0.42),
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final edit = edits[index];
                    return _PatchDiffFileRow(
                      edit: edit,
                      selected: edit.path == effectiveSelectedPath,
                      onTap: () => ref
                          .read(studioRightDrawerProvider.notifier)
                          .openPatchFile(patch.id, edit.path),
                    );
                  },
                ),
              ),
            if (edits.length > 1)
              Divider(
                color: tokens.studioDivider.withValues(alpha: 0.72),
                height: 1,
              ),
            if (selectedEdit != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.xs,
                  Spacing.md,
                  0,
                ),
                child: _PatchDiffSelectedFileHeader(edit: selectedEdit),
              ),
            Expanded(
              child: RepaintBoundary(
                child: StudioVirtualizedTextDocumentBody(
                  text: diffText,
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.sm,
                    Spacing.md,
                    Spacing.lg,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatchDiffFileRow extends ConsumerWidget {
  final ProposedFileEdit edit;
  final bool selected;
  final VoidCallback onTap;

  const _PatchDiffFileRow({
    required this.edit,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final stats = _editReviewStats(edit);
    return StudioFocusableActionSurface(
      key: ValueKey('studio-patch-diff-file-${edit.path}'),
      semanticLabel: 'Open ${edit.type.name} diff for ${edit.path}',
      selected: selected,
      onTap: onTap,
      child: Container(
        color: selected
            ? tokens.studioRailSelected.withValues(alpha: 0.45)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: 7,
          ),
          child: Row(
            children: [
              Icon(
                _patchEditIcon(edit.type),
                size: 13,
                color: selected ? tokens.textPrimary : tokens.textMuted,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  edit.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? tokens.textPrimary : tokens.textSecondary,
                    fontSize: FontSizes.xs,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
              if (stats.additions > 0 || stats.deletions > 0)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '+${stats.additions}',
                        style: TextStyle(color: tokens.success),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: '-${stats.deletions}',
                        style: TextStyle(color: tokens.error),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatchDiffSelectedFileHeader extends ConsumerWidget {
  final ProposedFileEdit edit;

  const _PatchDiffSelectedFileHeader({required this.edit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Row(
      children: [
        Icon(_patchEditIcon(edit.type), size: 13, color: tokens.textMuted),
        const SizedBox(width: Spacing.xs),
        Expanded(
          child: Text(
            edit.path,
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
            edit.type.name,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: FontSizes.xs,
              height: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PatchReviewStats {
  final int additions;
  final int deletions;

  const _PatchReviewStats({required this.additions, required this.deletions});
}

_PatchReviewStats _patchReviewStats(ProposedPatchSet patch) {
  var additions = 0;
  var deletions = 0;
  for (final edit in patch.edits) {
    final stats = _editReviewStats(edit);
    additions += stats.additions;
    deletions += stats.deletions;
  }
  return _PatchReviewStats(additions: additions, deletions: deletions);
}

_PatchReviewStats _editReviewStats(ProposedFileEdit edit) {
  var additions = 0;
  var deletions = 0;
  final diff = edit.unifiedDiff;
  if (diff != null && diff.trim().isNotEmpty) {
    for (final line in diff.split('\n')) {
      if (line.startsWith('+++') || line.startsWith('---')) continue;
      if (line.startsWith('+')) additions++;
      if (line.startsWith('-')) deletions++;
    }
    return _PatchReviewStats(additions: additions, deletions: deletions);
  }
  final before = edit.before;
  final after = edit.after;
  if (before != null && after != null) {
    for (final row in _diffRows(
      _splitDiffLines(before),
      _splitDiffLines(after),
    )) {
      switch (row.type) {
        case _DiffRowType.added:
          additions++;
          break;
        case _DiffRowType.removed:
          deletions++;
          break;
        case _DiffRowType.unchanged:
          break;
      }
    }
  } else if (after != null) {
    additions = _splitDiffLines(after).length;
  } else if (before != null) {
    deletions = _splitDiffLines(before).length;
  }
  return _PatchReviewStats(additions: additions, deletions: deletions);
}

IconData _patchEditIcon(ProposedFileEditType type) {
  return switch (type) {
    ProposedFileEditType.create => StudioIcons.noteAddOutlined,
    ProposedFileEditType.modify => StudioIcons.descriptionOutlined,
    ProposedFileEditType.delete => StudioIcons.deleteOutline,
  };
}

String _formatFileCount(int count) => '$count ${count == 1 ? 'file' : 'files'}';
