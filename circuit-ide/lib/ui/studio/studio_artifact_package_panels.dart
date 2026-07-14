import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/generated_artifact.dart';
import '../../state/theme_provider.dart';
import 'studio_artifact_metadata.dart';
import 'studio_chrome.dart';

/// Summarizes readiness, verification, and gaps for an artifact package.
class StudioArtifactPackageReadinessPanel extends ConsumerWidget {
  final GeneratedArtifact artifact;
  final List<GeneratedArtifact> companionArtifacts;

  const StudioArtifactPackageReadinessPanel({
    super.key,
    required this.artifact,
    required this.companionArtifacts,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final label = studioArtifactMetadataString(artifact, 'packageLabel');
    final packageStatus = studioArtifactMetadataString(
      artifact,
      'packageQualityStatus',
    );
    final qualityStatus = studioArtifactMetadataString(
      artifact,
      'qualityStatus',
    );
    final status = packageStatus.isNotEmpty
        ? packageStatus
        : qualityStatus.isNotEmpty
        ? qualityStatus
        : artifact.statusLabel;
    final artifactCount = studioArtifactMetadataInt(artifact, 'artifactCount');
    final readyCount = studioArtifactMetadataInt(
      artifact,
      'readyArtifactCount',
    );
    final averageScore = studioArtifactMetadataInt(
      artifact,
      'averageQualityScore',
    );
    final fileTypes = studioArtifactMetadataStringList(
      artifact,
      'packageFileTypes',
    );
    final files = studioArtifactMetadataStringList(artifact, 'artifactFiles');
    final previewSurfaces = studioArtifactMetadataStringList(
      artifact,
      'packagePreviewSurfaces',
    );
    final checks = studioArtifactMetadataStringList(
      artifact,
      'packageVerificationChecks',
    );
    final signals = studioArtifactMetadataStringList(
      artifact,
      'packageReadinessSignals',
    );
    final gaps = studioArtifactMetadataStringList(
      artifact,
      'packageReadinessGaps',
    );
    final next = studioArtifactMetadataString(artifact, 'packageNextAction');
    final companionCount = companionArtifacts.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                StudioIcons.inventory2Outlined,
                color: tokens.textMuted,
                size: 14,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label.isEmpty ? 'Artifact package' : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.xs,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ArtifactPackageStatusPill(text: status),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              if (artifactCount > 0)
                _ArtifactPackageMetricPill(
                  label: 'Artifacts',
                  value: readyCount > 0
                      ? '$readyCount/$artifactCount'
                      : '$artifactCount',
                ),
              if (companionCount > 0)
                _ArtifactPackageMetricPill(
                  label: 'Linked',
                  value: '$companionCount',
                ),
              if (averageScore > 0)
                _ArtifactPackageMetricPill(
                  label: 'Quality',
                  value: '$averageScore/100',
                ),
              for (final type in fileTypes.take(4))
                _ArtifactPackageChip(text: type),
              if (fileTypes.length > 4)
                _ArtifactPackageChip(text: '+${fileTypes.length - 4} types'),
            ],
          ),
          if (previewSurfaces.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ArtifactPackageSignalGroup(
              title: 'Preview surfaces',
              values: previewSurfaces,
            ),
          ],
          if (checks.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ArtifactPackageSignalGroup(
              title: 'Verification checks',
              values: checks,
            ),
          ],
          if (signals.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ArtifactPackageSignalGroup(
              title: 'Ready signals',
              values: signals,
            ),
          ],
          if (gaps.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ArtifactPackageSignalGroup(
              title: 'Readiness gaps',
              values: gaps,
              warning: true,
            ),
          ],
          if (files.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ArtifactPackageSignalGroup(
              title: 'Included files',
              values: files,
              maxVisible: 5,
            ),
          ],
          if (next.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              next,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Displays the durable publishing and review manifest for an artifact.
class StudioArtifactHandoffManifestPanel extends ConsumerWidget {
  final GeneratedArtifact artifact;

  const StudioArtifactHandoffManifestPanel({super.key, required this.artifact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final manifest = studioArtifactMetadataStringList(
      artifact,
      'externalHandoffManifest',
    );
    if (manifest.isEmpty) return const SizedBox.shrink();
    final gate = manifest.firstWhere(
      (item) => item.toLowerCase().startsWith('publishing gate:'),
      orElse: () => '',
    );
    final owner = manifest.firstWhere(
      (item) => item.toLowerCase().startsWith('review owner:'),
      orElse: () => '',
    );
    final evidence = manifest.firstWhere(
      (item) => item.toLowerCase().startsWith('evidence status:'),
      orElse: () => '',
    );
    final sourcePackage = manifest.firstWhere(
      (item) => item.toLowerCase().startsWith('source package:'),
      orElse: () => '',
    );
    final assumptionPackage = manifest.firstWhere(
      (item) => item.toLowerCase().startsWith('assumption package:'),
      orElse: () => '',
    );
    final visible = [
      if (gate.isNotEmpty) gate,
      if (owner.isNotEmpty) owner,
      if (evidence.isNotEmpty) evidence,
      if (sourcePackage.isNotEmpty) sourcePackage,
      if (assumptionPackage.isNotEmpty) assumptionPackage,
      for (final item in manifest)
        if (![
          gate,
          owner,
          evidence,
          sourcePackage,
          assumptionPackage,
        ].contains(item))
          item,
    ].take(5).toList(growable: false);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                StudioIcons.factCheckOutlined,
                color: tokens.textMuted,
                size: 14,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'External handoff manifest',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.xs,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (manifest.length > visible.length)
                Text(
                  '+${manifest.length - visible.length}',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          for (final item in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(
                      studioArtifactManifestLabel(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: FontSizes.xxs,
                        height: 1.18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      studioArtifactManifestDetail(item),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: FontSizes.xxs,
                        height: 1.18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ArtifactPackageStatusPill extends ConsumerWidget {
  final String text;

  const _ArtifactPackageStatusPill({required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: FontSizes.xxs,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ArtifactPackageMetricPill extends ConsumerWidget {
  final String label;
  final String value;

  const _ArtifactPackageMetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.studioControl.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.18)),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xxs,
            height: 1,
          ),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: value,
              style: TextStyle(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtifactPackageChip extends ConsumerWidget {
  final String text;

  const _ArtifactPackageChip({required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: FontSizes.xxs,
          height: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ArtifactPackageSignalGroup extends ConsumerWidget {
  final String title;
  final List<String> values;
  final int maxVisible;
  final bool warning;

  const _ArtifactPackageSignalGroup({
    required this.title,
    required this.values,
    this.maxVisible = 3,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final visible = values.take(maxVisible).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: FontSizes.xxs,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        for (final value in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  warning
                      ? StudioIcons.errorOutline
                      : StudioIcons.checkCircleOutline,
                  color: warning
                      ? tokens.warning.withValues(alpha: 0.86)
                      : tokens.textMuted,
                  size: 12,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xxs,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (values.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(left: 17),
            child: Text(
              '+${values.length - visible.length} more',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
                height: 1.1,
              ),
            ),
          ),
      ],
    );
  }
}

/// Lists companion deliverables that belong to the selected package.
class StudioArtifactPackageCompanionList extends ConsumerWidget {
  final List<GeneratedArtifact> artifacts;
  final ValueChanged<GeneratedArtifact> onOpen;

  const StudioArtifactPackageCompanionList({
    super.key,
    required this.artifacts,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 5),
            child: Row(
              children: [
                Icon(
                  StudioIcons.inventory2Outlined,
                  color: tokens.textMuted,
                  size: 13,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Package deliverables',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: FontSizes.xxs,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${artifacts.length}',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          for (final artifact in artifacts.take(6))
            StudioFocusableActionSurface(
              key: ValueKey('artifact-companion-${artifact.id}'),
              semanticLabel:
                  'Open ${artifact.fileName}, ${artifact.typeLabel} deliverable',
              onTap: () => onOpen(artifact),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  children: [
                    Icon(
                      _artifactCompanionIcon(artifact.kind),
                      color: tokens.textMuted,
                      size: 13,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artifact.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: FontSizes.xxs,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            artifact.typeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: FontSizes.xxs,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      StudioIcons.chevronRight,
                      color: tokens.textMuted,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          if (artifacts.length > 6)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 7),
              child: Text(
                '+${artifacts.length - 6} more deliverables',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: FontSizes.xxs,
                  height: 1.1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _artifactCompanionIcon(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.csv => StudioIcons.tableChartOutlined,
      GeneratedArtifactKind.powerPoint => StudioIcons.slideshowOutlined,
      GeneratedArtifactKind.docx ||
      GeneratedArtifactKind.pdf ||
      GeneratedArtifactKind.markdown ||
      GeneratedArtifactKind.html ||
      GeneratedArtifactKind.report => StudioIcons.articleOutlined,
      GeneratedArtifactKind.diagram ||
      GeneratedArtifactKind.chart => StudioIcons.accountTreeOutlined,
      GeneratedArtifactKind.json => StudioIcons.dataObjectOutlined,
    };
  }
}
