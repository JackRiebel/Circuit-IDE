import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../models/generated_artifact.dart';
import '../../models/studio_source_artifact.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_shell_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/studio_thread_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_artifact_chart_detail_rows.dart';
import 'studio_artifact_descriptor.dart';
import 'studio_artifact_diagram_excel_detail_rows.dart';
import 'studio_artifact_document_detail_rows.dart';
import 'studio_artifact_drawer_actions.dart';
import 'studio_artifact_drawer_preview.dart';
import 'studio_artifact_metadata.dart';
import 'studio_artifact_package_detail_rows.dart';
import 'studio_artifact_package_panels.dart';
import 'studio_chrome.dart';
import 'studio_drawer_empty_state.dart';

/// Lists artifacts for the selected task and owns their detail/review affordances.
class StudioArtifactsDrawer extends ConsumerWidget {
  final AgentTask? task;

  const StudioArtifactsDrawer({super.key, this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadId = ref.watch(
      studioThreadProvider.select(
        (state) => state.threadForTaskView(task?.id)?.id,
      ),
    );
    final artifactView = ref.watch(
      studioSourceArtifactsForThreadProvider(threadId),
    );
    final drawer = ref.watch(studioRightDrawerProvider);
    final artifacts = artifactView.artifacts
        .where(
          (artifact) =>
              artifact.kind == StudioSourceArtifactKind.generatedArtifact,
        )
        .map(GeneratedArtifact.fromSourceArtifact)
        .nonNulls
        .toList(growable: false);
    if (artifacts.isEmpty) {
      return StudioDrawerEmptyState(
        icon: StudioIcons.filePresentOutlined,
        title: 'No artifacts yet',
        detail:
            'Generated files, spreadsheets, reports, diagrams, and charts appear here.',
        actionLabel: 'Start a task',
        onAction: () => ref.read(studioShellProvider.notifier).openHome(),
      );
    }
    StudioSourceArtifact? sourceFor(GeneratedArtifact artifact) {
      return artifactView.artifacts
          .where((candidate) => candidate.id == 'generated-${artifact.id}')
          .firstOrNull;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      children: [
        for (final artifact in artifacts)
          Builder(
            builder: (context) {
              final source = sourceFor(artifact);
              final selected = source?.id == drawer.selectedArtifactId;
              return _ArtifactDrawerCard(
                artifact: artifact,
                companionArtifacts: _packageCompanions(artifact, artifacts),
                selected: selected,
                onTap: source == null
                    ? null
                    : () {
                        ref
                            .read(studioRightDrawerProvider.notifier)
                            .openArtifact(source);
                      },
                onReview: () {
                  if (artifact.filePath.trim().isEmpty) return;
                  if (_artifactOpensInCodeReview(artifact.kind)) {
                    ref
                        .read(studioRightDrawerProvider.notifier)
                        .openFile(artifact.filePath);
                    return;
                  }
                  if (source != null) {
                    ref
                        .read(studioRightDrawerProvider.notifier)
                        .openArtifact(source);
                  }
                },
                onOpenCompanion: (companion) {
                  final companionSource = sourceFor(companion);
                  if (companionSource == null) return;
                  ref
                      .read(studioRightDrawerProvider.notifier)
                      .openArtifact(companionSource);
                },
              );
            },
          ),
      ],
    );
  }
}

class _ArtifactDrawerCard extends ConsumerWidget {
  final GeneratedArtifact artifact;
  final List<GeneratedArtifact> companionArtifacts;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onReview;
  final ValueChanged<GeneratedArtifact> onOpenCompanion;

  const _ArtifactDrawerCard({
    required this.artifact,
    required this.companionArtifacts,
    required this.selected,
    required this.onTap,
    required this.onReview,
    required this.onOpenCompanion,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.studioCard.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? tokens.accent.withValues(alpha: 0.38)
                : tokens.studioDivider.withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StudioFocusableActionSurface(
              key: ValueKey('artifact-card-${artifact.id}'),
              semanticLabel:
                  'Open ${artifact.fileName}, ${_artifactMeta(artifact)}',
              selected: selected,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 9, 8),
                child: Row(
                  children: [
                    Icon(
                      _artifactDrawerIcon(artifact.kind),
                      color: tokens.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artifact.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: FontSizes.sm,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _artifactMeta(artifact),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: FontSizes.xxs,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _artifactWorkbenchHint(artifact),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted.withValues(alpha: 0.82),
                              fontSize: FontSizes.xxs,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (artifact.summary.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 0, 11, 9),
                child: Text(
                  artifact.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                    height: 1.25,
                  ),
                ),
              ),
            if (studioIsArtifactPackageManifest(artifact))
              StudioArtifactPackageReadinessPanel(
                artifact: artifact,
                companionArtifacts: companionArtifacts,
              ),
            if (studioArtifactMetadataStringList(
              artifact,
              'externalHandoffManifest',
            ).isNotEmpty)
              StudioArtifactHandoffManifestPanel(artifact: artifact),
            StudioArtifactDrawerPreview(artifact: artifact),
            if (companionArtifacts.isNotEmpty)
              StudioArtifactPackageCompanionList(
                artifacts: companionArtifacts,
                onOpen: onOpenCompanion,
              ),
            if (selected) _ArtifactDrawerDetailGrid(artifact: artifact),
            StudioArtifactDrawerActions(artifact: artifact, onReview: onReview),
          ],
        ),
      ),
    );
  }

  IconData _artifactDrawerIcon(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.csv => StudioIcons.tableChartOutlined,
      GeneratedArtifactKind.json => StudioIcons.dataObjectOutlined,
      GeneratedArtifactKind.diagram ||
      GeneratedArtifactKind.chart => StudioIcons.accountTreeOutlined,
      GeneratedArtifactKind.pdf => StudioIcons.pictureAsPdfOutlined,
      GeneratedArtifactKind.powerPoint => StudioIcons.slideshowOutlined,
      GeneratedArtifactKind.docx => StudioIcons.articleOutlined,
      GeneratedArtifactKind.markdown ||
      GeneratedArtifactKind.html ||
      GeneratedArtifactKind.report => StudioIcons.descriptionOutlined,
    };
  }

  String _artifactMeta(GeneratedArtifact artifact) {
    final parts = <String>[artifact.typeLabel];
    final qualityStatus = studioArtifactMetadataString(
      artifact,
      'qualityStatus',
    );
    if (qualityStatus.isNotEmpty) parts.add(qualityStatus);
    if (studioIsArtifactPackageManifest(artifact)) {
      final packageLabel = studioArtifactMetadataString(
        artifact,
        'packageLabel',
      );
      final artifactCount = studioArtifactMetadataInt(
        artifact,
        'artifactCount',
      );
      final readyCount = studioArtifactMetadataInt(
        artifact,
        'readyArtifactCount',
      );
      final packageStatus = studioArtifactMetadataString(
        artifact,
        'packageQualityStatus',
      );
      final averageScore = studioArtifactMetadataInt(
        artifact,
        'averageQualityScore',
      );
      if (packageLabel.isNotEmpty) parts.add(packageLabel);
      if (artifactCount > 0) parts.add('$artifactCount artifacts');
      if (readyCount > 0 && artifactCount > 0) {
        parts.add('$readyCount ready');
      }
      if (packageStatus.isNotEmpty && packageStatus != qualityStatus) {
        parts.add(packageStatus);
      }
      if (averageScore > 0) parts.add('$averageScore/100');
    }
    if (artifact.kind == GeneratedArtifactKind.diagram) {
      final nodeCount = studioArtifactMetadataInt(artifact, 'nodeCount');
      final edgeCount = studioArtifactMetadataInt(artifact, 'edgeCount');
      final topologyType = studioArtifactMetadataString(
        artifact,
        'topologyType',
      );
      final resiliencyModel = studioArtifactMetadataString(
        artifact,
        'resiliencyModel',
      );
      final validationGapCount = studioArtifactMetadataInt(
        artifact,
        'validationGapCount',
      );
      if (topologyType.isNotEmpty) parts.add(topologyType);
      if (nodeCount > 0 && edgeCount > 0) {
        parts.add('$nodeCount nodes');
        parts.add('$edgeCount links');
      }
      if (resiliencyModel.isNotEmpty && resiliencyModel != 'Review') {
        parts.add(resiliencyModel);
      }
      if (validationGapCount > 0) {
        parts.add('$validationGapCount gaps');
      }
    }
    if (artifact.kind == GeneratedArtifactKind.excel &&
        studioArtifactMetadataString(artifact, 'workbookKind') ==
            'solution_sizing') {
      final users = studioArtifactMetadataString(artifact, 'users');
      final aps = studioArtifactMetadataString(artifact, 'accessPoints');
      final wan = studioArtifactMetadataString(artifact, 'wan');
      final gateCount = studioArtifactMetadataInt(artifact, 'gateCount');
      final riskCount = studioArtifactMetadataInt(artifact, 'riskCount');
      if (users.isNotEmpty) parts.add('$users users');
      if (aps.isNotEmpty) parts.add('$aps APs');
      if (wan.isNotEmpty) parts.add(wan);
      if (gateCount > 0) parts.add('$gateCount gates');
      if (riskCount > 0) parts.add('$riskCount risks');
    }
    if (artifact.kind == GeneratedArtifactKind.chart) {
      final pointCount = studioArtifactMetadataInt(artifact, 'pointCount');
      final highRiskCount = studioArtifactMetadataInt(
        artifact,
        'highRiskCount',
      );
      final chartPackType = studioArtifactMetadataString(
        artifact,
        'chartPackType',
      );
      final handoffStatus = studioArtifactMetadataString(
        artifact,
        'handoffStatus',
      );
      final signals = studioArtifactMetadataStringList(artifact, 'signals');
      if (chartPackType.isNotEmpty) parts.add(chartPackType);
      if (pointCount > 0) parts.add('$pointCount points');
      if (highRiskCount > 0) {
        parts.add('$highRiskCount high risk');
      }
      if (signals.isNotEmpty) {
        parts.add(studioArtifactCompactSignalList(signals));
      }
      if (handoffStatus.isNotEmpty) parts.add(handoffStatus);
    }
    if (artifact.kind == GeneratedArtifactKind.powerPoint) {
      final theme = studioArtifactMetadataString(artifact, 'theme');
      final deckType = studioArtifactMetadataString(artifact, 'deckType');
      final handoffStatus = studioArtifactMetadataString(
        artifact,
        'handoffStatus',
      );
      final inspectionStatus = studioArtifactMetadataString(
        artifact,
        'pptxInspectionStatus',
      );
      final readinessSignals = studioArtifactMetadataStringList(
        artifact,
        'readinessSignals',
      );
      if (deckType.isNotEmpty) parts.add(deckType);
      if (theme.isNotEmpty) parts.add('$theme theme');
      if (inspectionStatus.isNotEmpty) {
        parts.add('PPTX $inspectionStatus');
      }
      if (readinessSignals.isNotEmpty) {
        parts.add(studioArtifactCompactSignalList(readinessSignals));
      }
      if (handoffStatus.isNotEmpty) parts.add(handoffStatus);
    }
    if (artifact.kind == GeneratedArtifactKind.docx) {
      final wordCount = studioArtifactMetadataInt(artifact, 'wordCount');
      final reportType = studioArtifactMetadataString(artifact, 'reportType');
      final handoffStatus = studioArtifactMetadataString(
        artifact,
        'handoffStatus',
      );
      final inspectionStatus = studioArtifactMetadataString(
        artifact,
        'docxInspectionStatus',
      );
      final visualEvidenceReliability = studioArtifactMetadataString(
        artifact,
        'visualEvidenceReliability',
      );
      if (reportType.isNotEmpty) parts.add(reportType);
      if (wordCount > 0) parts.add('$wordCount words');
      if (inspectionStatus.isNotEmpty) {
        parts.add('DOCX $inspectionStatus');
      }
      if (visualEvidenceReliability.isNotEmpty) {
        parts.add(
          studioArtifactVisualEvidenceReliabilityLabel(
            visualEvidenceReliability,
          ),
        );
      }
      if (handoffStatus.isNotEmpty) parts.add(handoffStatus);
    }
    if (artifact.kind == GeneratedArtifactKind.pdf) {
      final bookmarkCount = studioArtifactMetadataInt(
        artifact,
        'bookmarkCount',
      );
      final reportType = studioArtifactMetadataString(artifact, 'reportType');
      final handoffStatus = studioArtifactMetadataString(
        artifact,
        'handoffStatus',
      );
      final inspectionStatus = studioArtifactMetadataString(
        artifact,
        'pdfInspectionStatus',
      );
      final visualEvidenceReliability = studioArtifactMetadataString(
        artifact,
        'visualEvidenceReliability',
      );
      if (reportType.isNotEmpty) parts.add(reportType);
      if (bookmarkCount > 0) parts.add('$bookmarkCount bookmarks');
      if (inspectionStatus.isNotEmpty) {
        parts.add('PDF $inspectionStatus');
      }
      if (visualEvidenceReliability.isNotEmpty) {
        parts.add(
          studioArtifactVisualEvidenceReliabilityLabel(
            visualEvidenceReliability,
          ),
        );
      }
      if (handoffStatus.isNotEmpty) parts.add(handoffStatus);
    }
    if (artifact.sheetCount > 1) {
      parts.add(switch (artifact.kind) {
        GeneratedArtifactKind.powerPoint => '${artifact.sheetCount} slides',
        GeneratedArtifactKind.docx => '${artifact.sheetCount} sections',
        GeneratedArtifactKind.pdf => '${artifact.sheetCount} pages',
        GeneratedArtifactKind.chart => '${artifact.sheetCount} charts',
        _ => '${artifact.sheetCount} sheets',
      });
    }
    if (artifact.byteSize > 0) {
      parts.add(studioArtifactFormatBytes(artifact.byteSize));
    }
    parts.add(artifact.statusLabel);
    return parts.join(' • ');
  }
}

String _artifactWorkbenchHint(GeneratedArtifact artifact) {
  final persistedLabel = studioArtifactMetadataString(
    artifact,
    'artifactDescriptorLabel',
  );
  final persistedUseCases = studioArtifactMetadataStringList(
    artifact,
    'artifactUseCases',
  );
  if (persistedLabel.isNotEmpty) {
    if (persistedUseCases.isEmpty) return '$persistedLabel artifact';
    return '$persistedLabel for ${persistedUseCases.take(3).join(', ')}';
  }
  if (studioIsArtifactPackageManifest(artifact)) {
    return 'Package manifest for the generated deliverable set';
  }
  final descriptor = studioArtifactDescriptorFor(artifact.kind);
  if (descriptor.useCases.isEmpty) return '${descriptor.label} artifact';
  return '${descriptor.label} for ${descriptor.useCases.take(3).join(', ')}';
}

List<GeneratedArtifact> _packageCompanions(
  GeneratedArtifact package,
  List<GeneratedArtifact> artifacts,
) {
  if (!studioIsArtifactPackageManifest(package)) return const [];
  final ids = studioArtifactMetadataStringList(package, 'artifactIds').toSet();
  final files = studioArtifactMetadataStringList(
    package,
    'artifactFiles',
  ).toSet();
  if (ids.isEmpty && files.isEmpty) return const [];
  return artifacts
      .where(
        (artifact) =>
            artifact.id != package.id &&
            (ids.contains(artifact.id) || files.contains(artifact.fileName)),
      )
      .toList(growable: false);
}

bool _artifactOpensInCodeReview(GeneratedArtifactKind kind) {
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

class _ArtifactDrawerDetailGrid extends ConsumerWidget {
  final GeneratedArtifact artifact;

  const _ArtifactDrawerDetailGrid({required this.artifact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final extension = p.extension(artifact.fileName).replaceFirst('.', '');
    final folder = artifact.filePath.trim().isEmpty
        ? ''
        : p.dirname(artifact.filePath);
    final rows = <(String, String)>[
      ('Type', artifact.typeLabel),
      ('Status', artifact.statusLabel),
      if (studioArtifactMetadataString(
        artifact,
        'artifactDescriptorLabel',
      ).isNotEmpty)
        (
          'Artifact',
          studioArtifactMetadataString(artifact, 'artifactDescriptorLabel'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'artifactPreviewSurface',
      ).isNotEmpty)
        (
          'Preview',
          studioArtifactMetadataString(artifact, 'artifactPreviewSurface'),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'artifactUseCases',
      ).isNotEmpty)
        (
          'Use cases',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'artifactUseCases'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'artifactVerificationChecks',
      ).isNotEmpty)
        (
          'Artifact checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'artifactVerificationChecks',
            ),
          ),
        ),
      if (studioArtifactMetadataString(artifact, 'qualityStatus').isNotEmpty)
        ('Quality', studioArtifactMetadataString(artifact, 'qualityStatus')),
      if (studioArtifactMetadataInt(artifact, 'qualityScore') > 0)
        ('Score', '${studioArtifactMetadataInt(artifact, 'qualityScore')}/100'),
      if (studioArtifactMetadataStringList(artifact, 'qualityGates').isNotEmpty)
        (
          'Gates',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'qualityGates'),
          ),
        ),
      if (studioArtifactMetadataStringList(artifact, 'qualityGaps').isNotEmpty)
        (
          'Gaps',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'qualityGaps'),
          ),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'accessibilityStatus',
      ).isNotEmpty)
        (
          'Accessibility',
          studioArtifactMetadataString(artifact, 'accessibilityStatus'),
        ),
      if (studioArtifactMetadataBool(artifact, 'hasAccessibleArtifact'))
        ('Accessible', 'Selected automated checks passed'),
      if (studioArtifactMetadataStringList(
        artifact,
        'accessibilityGaps',
      ).isNotEmpty)
        (
          'Accessibility gaps',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'accessibilityGaps'),
          ),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'accessibilityManualReview',
      ).isNotEmpty)
        (
          'Manual review',
          studioArtifactMetadataString(artifact, 'accessibilityManualReview'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'qualityNextAction',
      ).isNotEmpty)
        ('Next', studioArtifactMetadataString(artifact, 'qualityNextAction')),
      if (studioArtifactMetadataBool(artifact, 'hasCustomerReadyArtifact'))
        ('Ready', 'Customer handoff candidate'),
      if (studioIsArtifactPackageManifest(artifact))
        ...studioArtifactPackageDetailRows(artifact),
      ('Created', _compactDate(artifact.createdAt)),
      if (extension.isNotEmpty) ('Format', extension.toUpperCase()),
      if (artifact.sheetCount > 0)
        (_countLabel(artifact.kind), '${artifact.sheetCount}'),
      ...studioArtifactDiagramExcelDetailRows(artifact),
      ...studioArtifactChartDetailRows(artifact),
      ...studioArtifactDocumentDetailRows(artifact),
      if (artifact.requestId != null && artifact.requestId!.trim().isNotEmpty)
        ('Request', artifact.requestId!),
      if (folder.trim().isNotEmpty) ('Folder', folder),
      if (artifact.filePath.trim().isNotEmpty) ('Path', artifact.filePath),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Semantics(
              label: '${row.$1}: ${row.$2}',
              readOnly: true,
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 62,
                        child: Text(
                          row.$1,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: FontSizes.xxs,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.$2,
                          maxLines: row.$1 == 'Path' || row.$1 == 'Folder'
                              ? 2
                              : 1,
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
              ),
            ),
        ],
      ),
    );
  }

  String _countLabel(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.powerPoint => 'Slides',
      GeneratedArtifactKind.docx => 'Sections',
      GeneratedArtifactKind.pdf => 'Pages',
      GeneratedArtifactKind.chart => 'Charts',
      GeneratedArtifactKind.excel => 'Sheets',
      _ => 'Items',
    };
  }

  String _compactDate(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day}/${local.year} $hour:$minute $suffix';
  }
}
