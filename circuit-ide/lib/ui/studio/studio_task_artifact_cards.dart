import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../core/constants/studio_layout_contract.dart';
import '../../models/generated_artifact.dart';
import '../../models/studio_source_artifact.dart';
import '../../state/artifact_launch_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/theme_provider.dart';
import '../../theme/theme_tokens.dart';

class StudioGeneratedArtifactStack extends StatelessWidget {
  final List<StudioSourceArtifact> artifacts;

  const StudioGeneratedArtifactStack({super.key, required this.artifacts});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final artifact in artifacts) _GeneratedArtifactCard(artifact),
      ],
    );
  }
}

class _GeneratedArtifactCard extends ConsumerWidget {
  final StudioSourceArtifact sourceArtifact;

  const _GeneratedArtifactCard(this.sourceArtifact);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final artifact = GeneratedArtifact.fromSourceArtifact(sourceArtifact);
    final fileName = artifact?.fileName ?? sourceArtifact.title;
    final filePath = artifact?.filePath ?? sourceArtifact.filePath ?? '';
    final summary = artifact?.summary ?? sourceArtifact.subtitle;
    final typeLabel = artifact == null
        ? 'Artifact'
        : '${artifact.typeLabel} • v${artifact.version}';
    final byteSize = artifact == null ? null : _formatArtifactSize(artifact);
    return Container(
      constraints: const BoxConstraints(
        maxWidth: StudioLayoutContract.artifactWidth,
      ),
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        color: tokens.studioCard.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.34)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.studioControl.withValues(alpha: 0.54),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _artifactIcon(artifact?.kind),
                    color: tokens.textSecondary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: FontSizes.md,
                          height: 1.18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [typeLabel, ?byteSize].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: FontSizes.xs,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                _ArtifactCardAction(
                  label: 'Open',
                  onPressed: filePath.isEmpty
                      ? null
                      : () => _launchArtifactPath(context, ref, filePath),
                ),
                _ArtifactCardAction(
                  label: 'Reveal',
                  onPressed: filePath.isEmpty
                      ? null
                      : () => _launchArtifactPath(
                          context,
                          ref,
                          p.dirname(filePath),
                        ),
                ),
                _ArtifactCardAction(
                  label: 'Review',
                  onPressed: () => _reviewArtifact(
                    ref,
                    artifact: artifact,
                    sourceArtifact: sourceArtifact,
                    filePath: filePath,
                  ),
                ),
                if (artifact?.canRegenerate ?? false)
                  _ArtifactCardAction(
                    label: 'Regenerate',
                    onPressed: () =>
                        unawaited(_regenerateArtifact(context, ref, artifact!)),
                  ),
                if (artifact?.canRegenerate ?? false)
                  _ArtifactCardAction(
                    label: 'Edit source',
                    onPressed: () =>
                        unawaited(_editArtifactSource(context, ref, artifact!)),
                  ),
                if (artifact?.parentArtifactId != null)
                  _ArtifactCardAction(
                    label: 'Compare',
                    onPressed: () =>
                        _compareArtifactVersions(context, ref, artifact!),
                  ),
              ],
            ),
          ),
          if (summary.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 11),
              child: Text(
                summary,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: FontSizes.sm,
                  height: 1.32,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: tokens.surfacePanel.withValues(alpha: 0.12),
              border: Border(
                top: BorderSide(
                  color: tokens.studioDivider.withValues(alpha: 0.32),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    filePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.2,
                      fontFamily: EditorDefaults.studioMonospaceFontFamily,
                    ),
                  ),
                ),
                TextButton(
                  style: _artifactTextActionStyle(tokens),
                  onPressed: filePath.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: filePath));
                          _showArtifactSnack(context, 'Copied artifact path');
                        },
                  child: const Text('Copy path'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _artifactIcon(GeneratedArtifactKind? kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.csv => StudioIcons.tableChartOutlined,
      GeneratedArtifactKind.json => StudioIcons.dataObjectOutlined,
      GeneratedArtifactKind.pdf => StudioIcons.pictureAsPdfOutlined,
      GeneratedArtifactKind.powerPoint => StudioIcons.slideshowOutlined,
      GeneratedArtifactKind.docx => StudioIcons.articleOutlined,
      GeneratedArtifactKind.diagram ||
      GeneratedArtifactKind.chart => StudioIcons.accountTreeOutlined,
      GeneratedArtifactKind.markdown ||
      GeneratedArtifactKind.html ||
      GeneratedArtifactKind.report ||
      null => StudioIcons.descriptionOutlined,
    };
  }

  static String _formatArtifactSize(GeneratedArtifact artifact) {
    if (artifact.byteSize < 1024) return '${artifact.byteSize} B';
    final kb = artifact.byteSize / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  static void _reviewArtifact(
    WidgetRef ref, {
    required GeneratedArtifact? artifact,
    required StudioSourceArtifact sourceArtifact,
    required String filePath,
  }) {
    final drawer = ref.read(studioRightDrawerProvider.notifier);
    if (artifact != null &&
        filePath.trim().isNotEmpty &&
        _artifactOpensInCodeReview(artifact.kind)) {
      drawer.openFile(filePath);
      return;
    }
    drawer.openArtifact(sourceArtifact);
  }

  static Future<void> _regenerateArtifact(
    BuildContext context,
    WidgetRef ref,
    GeneratedArtifact artifact,
  ) async {
    final regenerated = await ref
        .read(studioSourceArtifactProvider.notifier)
        .regenerateGeneratedArtifact(artifact);
    if (!context.mounted) return;
    _showArtifactSnack(
      context,
      regenerated == null
          ? 'Could not regenerate artifact'
          : 'Created ${regenerated.fileName}',
    );
  }

  static Future<void> _editArtifactSource(
    BuildContext context,
    WidgetRef ref,
    GeneratedArtifact artifact,
  ) async {
    final recipe = artifact.generationRecipe;
    if (recipe == null) return;
    final hasExternalChanges = await ref
        .read(studioSourceArtifactProvider.notifier)
        .generatedArtifactHasExternalChanges(artifact);
    if (!context.mounted) return;
    if (hasExternalChanges) {
      final continueWithSavedSource = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('External artifact change detected'),
          content: const Text(
            'This file changed outside CircuitCode. Regenerating will create a new version from the saved structured source and will not overwrite the external file.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Use saved source'),
            ),
          ],
        ),
      );
      if (continueWithSavedSource != true) return;
    }
    if (!context.mounted) return;
    final controller = TextEditingController(text: recipe.sourceContent);
    final editedContent = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${artifact.typeLabel} source'),
        content: SizedBox(
          width: 720,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 14,
            maxLines: 24,
            expands: false,
            style: const TextStyle(
              fontFamily: EditorDefaults.studioMonospaceFontFamily,
              fontSize: FontSizes.sm,
            ),
            decoration: const InputDecoration(
              hintText: 'Structured source used to generate this artifact',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Regenerate version'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (editedContent == null || editedContent.trim().isEmpty) return;
    final regenerated = await ref
        .read(studioSourceArtifactProvider.notifier)
        .regenerateGeneratedArtifact(
          artifact,
          sourceContentOverride: editedContent,
        );
    if (!context.mounted) return;
    _showArtifactSnack(
      context,
      regenerated == null
          ? 'Could not regenerate edited artifact'
          : 'Created ${regenerated.fileName}',
    );
  }

  static Future<void> _compareArtifactVersions(
    BuildContext context,
    WidgetRef ref,
    GeneratedArtifact artifact,
  ) async {
    final parentId = artifact.parentArtifactId;
    if (parentId == null) return;
    final parent = ref
        .read(studioSourceArtifactProvider)
        .artifacts
        .map(GeneratedArtifact.fromSourceArtifact)
        .whereType<GeneratedArtifact>()
        .where((candidate) => candidate.id == parentId)
        .firstOrNull;
    if (parent == null) {
      _showArtifactSnack(context, 'Earlier artifact version is unavailable');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Artifact version comparison'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Table(
              columnWidths: const {0: IntrinsicColumnWidth()},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                _versionComparisonRow(
                  'Version',
                  'v${parent.version}',
                  'v${artifact.version}',
                ),
                _versionComparisonRow(
                  'Format',
                  parent.typeLabel,
                  artifact.typeLabel,
                ),
                _versionComparisonRow(
                  'File',
                  parent.fileName,
                  artifact.fileName,
                ),
                _versionComparisonRow(
                  'Size',
                  _formatArtifactSize(parent),
                  _formatArtifactSize(artifact),
                ),
                _versionComparisonRow(
                  'Output hash',
                  _shortArtifactHash(parent.outputHash),
                  _shortArtifactHash(artifact.outputHash),
                ),
                _versionComparisonRow(
                  'Composition',
                  _shortArtifactHash(
                    parent.generationRecipe?.compositionHash ?? '',
                  ),
                  _shortArtifactHash(
                    artifact.generationRecipe?.compositionHash ?? '',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static TableRow _versionComparisonRow(
    String label,
    String parentValue,
    String childValue,
  ) {
    const labelStyle = TextStyle(fontWeight: FontWeight.w600);
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text(label, style: labelStyle),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: SelectableText(parentValue),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: SelectableText(childValue),
        ),
      ],
    );
  }

  static String _shortArtifactHash(String value) {
    if (value.trim().isEmpty) return 'Unavailable';
    return value.length <= 12 ? value : '${value.substring(0, 12)}…';
  }

  static bool _artifactOpensInCodeReview(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.csv ||
      GeneratedArtifactKind.markdown ||
      GeneratedArtifactKind.html ||
      GeneratedArtifactKind.json ||
      GeneratedArtifactKind.diagram ||
      GeneratedArtifactKind.chart ||
      GeneratedArtifactKind.report => true,
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.pdf ||
      GeneratedArtifactKind.powerPoint ||
      GeneratedArtifactKind.docx => false,
    };
  }

  static Future<void> _launchArtifactPath(
    BuildContext context,
    WidgetRef ref,
    String filePath,
  ) async {
    final uri = Uri.file(filePath);
    final launcher = ref.read(artifactLaunchProvider);
    if (!await launcher(uri)) {
      if (!context.mounted) return;
      _showArtifactSnack(context, 'Could not open artifact');
    }
  }

  static void _showArtifactSnack(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1100),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _ArtifactCardAction extends ConsumerWidget {
  final String label;
  final VoidCallback? onPressed;

  const _ArtifactCardAction({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return TextButton(
      style: _artifactTextActionStyle(tokens),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

ButtonStyle _artifactTextActionStyle(ThemeTokens tokens) {
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
