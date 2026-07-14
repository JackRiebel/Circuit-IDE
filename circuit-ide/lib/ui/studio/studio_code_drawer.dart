import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_source_artifact.dart';
import '../../state/file_tree_provider.dart';
import '../../state/studio_code_edit_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';
import 'studio_drawer_empty_state.dart';
import 'studio_virtualized_text_document.dart';

/// Read-only, virtualized projection of the selected source artifact or file.
class StudioCodeDrawer extends ConsumerWidget {
  const StudioCodeDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    final selected = _selectedArtifact(ref);
    final rootPath = ref.watch(fileTreeProvider).rootPath;
    final path = drawer.filePath ?? selected?.filePath;
    if (path == null) {
      return StudioDrawerEmptyState(
        icon: StudioIcons.code,
        title: 'No file selected',
        detail: 'Open a file or source row to inspect code here.',
        actionLabel: 'Open files',
        onAction: () => ref
            .read(studioRightDrawerProvider.notifier)
            .openMode(StudioDrawerMode.files),
      );
    }
    final resolved = resolveStudioDrawerPath(rootPath, path);
    final editor = ref.watch(studioCodeEditProvider);
    if (editor.filePath != path && !editor.isLoading) {
      Future.microtask(
        () => ref.read(studioCodeEditProvider.notifier).open(path),
      );
    }
    if (editor.isLoading || editor.filePath != path) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: Spacing.sm),
            Text('Opening file…'),
          ],
        ),
      );
    }
    if (editor.error != null) {
      return StudioDrawerEmptyState(
        icon: StudioIcons.errorOutline,
        title: 'Could not open file',
        detail: editor.error!,
        actionLabel: 'Retry',
        onAction: () => ref.read(studioCodeEditProvider.notifier).open(path),
      );
    }
    return _StudioCodePreviewView(
      title: path,
      resolvedPath: resolved,
      state: editor,
    );
  }

  StudioSourceArtifact? _selectedArtifact(WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    return ref.watch(
      studioSourceArtifactByIdProvider(drawer.selectedArtifactId),
    );
  }
}

class _StudioCodePreviewView extends ConsumerWidget {
  final String title;
  final String resolvedPath;
  final StudioCodeEditState state;

  const _StudioCodePreviewView({
    required this.title,
    required this.resolvedPath,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
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
                  Expanded(
                    child: Tooltip(
                      message: resolvedPath,
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
                    onTap: () =>
                        Clipboard.setData(ClipboardData(text: state.draft)),
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
                  text: state.draft,
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

String resolveStudioDrawerPath(String? rootPath, String path) {
  if (p.isAbsolute(path)) return path;
  if (rootPath == null) return path;
  return p.normalize(p.join(rootPath, path));
}
