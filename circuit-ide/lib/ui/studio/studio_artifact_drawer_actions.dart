import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/generated_artifact.dart';
import '../../services/artifact_visual_preview_verifier.dart';
import '../../services/macos_file_reveal_service.dart';
import '../../state/artifact_launch_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';
import 'artifact_template_selector.dart';
import 'studio_artifact_descriptor.dart';
import 'studio_chrome.dart';

/// Artifact open, reveal, review, template, and export controls.
class StudioArtifactDrawerActions extends ConsumerWidget {
  final GeneratedArtifact artifact;
  final VoidCallback onReview;

  const StudioArtifactDrawerActions({
    super.key,
    required this.artifact,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final exportTargets = ref
        .read(studioSourceArtifactProvider.notifier)
        .supportedExportTargets(artifact);
    final visualPreviewPath = artifact.metadata['visualPreviewPath']
        ?.toString()
        .trim();
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.studioDivider.withValues(alpha: 0.22)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            style: _compactDrawerActionStyle(tokens),
            onPressed: artifact.filePath.isEmpty
                ? null
                : () => ref.read(artifactLaunchProvider)(
                    Uri.file(artifact.filePath),
                  ),
            child: const Text('Open'),
          ),
          TextButton(
            style: _compactDrawerActionStyle(tokens),
            onPressed: artifact.filePath.isEmpty
                ? null
                : () async {
                    final revealed = await MacosFileRevealService.platform
                        .reveal(artifact.filePath);
                    if (revealed) return;
                    await ref.read(artifactLaunchProvider)(
                      Uri.file(p.dirname(artifact.filePath)),
                    );
                  },
            child: const Text('Reveal'),
          ),
          TextButton(
            style: _compactDrawerActionStyle(tokens),
            onPressed: onReview,
            child: const Text('Review'),
          ),
          if (visualPreviewPath != null && visualPreviewPath.isNotEmpty)
            TextButton(
              style: _compactDrawerActionStyle(tokens),
              onPressed: () {
                final verification = const ArtifactVisualPreviewVerifier()
                    .verifySync(artifact);
                if (!verification.isValid || verification.path == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        verification.reason ??
                            'This visual preview could not be verified.',
                      ),
                    ),
                  );
                  return;
                }
                ref.read(artifactLaunchProvider)(Uri.file(verification.path!));
              },
              child: const Text('Preview'),
            ),
          if (artifact.canRegenerate)
            TextButton(
              style: _compactDrawerActionStyle(tokens),
              onPressed: () async {
                final template = await showArtifactTemplateSelector(
                  context,
                  selectedTemplateId:
                      artifact.generationRecipe?.templateId ??
                      'circuit-standard',
                );
                if (template == null || !context.mounted) return;
                await ref
                    .read(studioSourceArtifactProvider.notifier)
                    .regenerateGeneratedArtifact(
                      artifact,
                      templateId: template.id,
                    );
              },
              child: const Text('Template'),
            ),
          if (exportTargets.isNotEmpty)
            PopupMenuButton<GeneratedArtifactKind>(
              tooltip: 'Export as',
              color: tokens.studioPanel,
              elevation: 10,
              position: PopupMenuPosition.under,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: tokens.studioDivider.withValues(alpha: 0.6),
                ),
              ),
              onSelected: (kind) async {
                await ref
                    .read(studioSourceArtifactProvider.notifier)
                    .exportGeneratedArtifact(artifact, kind);
              },
              itemBuilder: (context) => [
                for (final kind in exportTargets)
                  PopupMenuItem<GeneratedArtifactKind>(
                    value: kind,
                    height: 32,
                    child: Text(
                      studioArtifactExportLabel(kind),
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xs,
                        height: 1.1,
                      ),
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Text(
                  'Export',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: FontSizes.xxs,
                    height: 1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          StudioChromeIconButton(
            tooltip: 'Copy path',
            onTap: artifact.filePath.isEmpty
                ? null
                : () =>
                      Clipboard.setData(ClipboardData(text: artifact.filePath)),
            icon: StudioIcons.copy,
            width: 26,
            height: 22,
            iconSize: 13,
          ),
        ],
      ),
    );
  }
}

ButtonStyle _compactDrawerActionStyle(ThemeTokens tokens) {
  return TextButton.styleFrom(
    foregroundColor: tokens.textSecondary,
    disabledForegroundColor: tokens.textMuted.withValues(alpha: 0.38),
    textStyle: const TextStyle(fontSize: FontSizes.xxs, height: 1),
    visualDensity: VisualDensity.compact,
    minimumSize: const Size(0, 24),
    padding: const EdgeInsets.symmetric(horizontal: 7),
  );
}
