import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/reviewed_edit.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';

class StudioPatchFileRow extends ConsumerWidget {
  final ProposedPatchSet patch;
  final StudioPatchFileSummary file;

  const StudioPatchFileRow({
    super.key,
    required this.patch,
    required this.file,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final opensDiff = file.hasDiff;
    return StudioFocusableActionSurface(
      semanticLabel: opensDiff
          ? 'Open diff for ${file.path}'
          : 'Open file ${file.path}',
      borderRadius: BorderRadius.zero,
      onTap: () {
        if (file.hasDiff) {
          ref
              .read(studioRightDrawerProvider.notifier)
              .openPatchFile(patch.id, file.path);
        } else {
          ref.read(studioRightDrawerProvider.notifier).openFile(file.path);
        }
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          children: [
            Icon(
              file.hasDiff
                  ? StudioIcons.descriptionOutlined
                  : StudioIcons.articleOutlined,
              color: tokens.textMuted,
              size: 11,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                file.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.xs,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (file.additions > 0 || file.deletions > 0) ...[
              Text(
                '+${file.additions}',
                style: TextStyle(
                  color: tokens.success,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                '-${file.deletions}',
                style: TextStyle(
                  color: tokens.error,
                  fontSize: FontSizes.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(width: Spacing.sm),
            Icon(StudioIcons.chevronRight, color: tokens.textMuted, size: 13),
          ],
        ),
      ),
    );
  }
}

class StudioPatchFileSummary {
  final String path;
  final int additions;
  final int deletions;
  final bool hasDiff;

  const StudioPatchFileSummary({
    required this.path,
    this.additions = 0,
    this.deletions = 0,
    this.hasDiff = false,
  });
}

StudioPatchFileSummary studioPatchDelta(ProposedPatchSet patch) {
  final files = studioPatchFiles(patch);
  return StudioPatchFileSummary(
    path: '',
    additions: files.fold(0, (total, file) => total + file.additions),
    deletions: files.fold(0, (total, file) => total + file.deletions),
  );
}

List<StudioPatchFileSummary> studioPatchFiles(ProposedPatchSet patch) {
  if (patch.edits.isNotEmpty) {
    return [
      for (final edit in patch.edits)
        StudioPatchFileSummary(
          path: edit.path,
          additions: _lineDelta(edit).additions,
          deletions: _lineDelta(edit).deletions,
          hasDiff: true,
        ),
    ];
  }
  return [
    for (final file in patch.plannedFiles)
      StudioPatchFileSummary(path: file.split(' — ').first.trim()),
  ];
}

StudioPatchFileSummary _lineDelta(ProposedFileEdit edit) {
  if ((edit.unifiedDiff ?? '').trim().isNotEmpty) {
    var additions = 0;
    var deletions = 0;
    for (final line in edit.unifiedDiff!.split('\n')) {
      if (line.startsWith('+++') || line.startsWith('---')) continue;
      if (line.startsWith('+')) additions++;
      if (line.startsWith('-')) deletions++;
    }
    return StudioPatchFileSummary(
      path: edit.path,
      additions: additions,
      deletions: deletions,
    );
  }
  final before = edit.before?.split('\n').length ?? 0;
  final after = edit.after?.split('\n').length ?? 0;
  return StudioPatchFileSummary(
    path: edit.path,
    additions: after > before ? after - before : after,
    deletions: before > after ? before - after : 0,
  );
}
