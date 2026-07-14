import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/generated_artifact.dart';
import '../../state/theme_provider.dart';
import 'studio_artifact_descriptor.dart';
import 'studio_artifact_metadata.dart';

/// Renders bounded text, structured, and binary previews for an artifact.
class StudioArtifactDrawerPreview extends ConsumerWidget {
  final GeneratedArtifact artifact;

  const StudioArtifactDrawerPreview({super.key, required this.artifact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    if (artifact.previewRows.isNotEmpty) {
      return _ArtifactStructuredPreview(artifact: artifact);
    }
    if (_isBinaryPreviewOnly(artifact.kind)) {
      return _BinaryArtifactPreview(artifact: artifact);
    }
    if (artifact.filePath.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<String>(
      future: _readArtifactPreview(artifact.filePath),
      builder: (context, snapshot) {
        final text = snapshot.data?.trim() ?? '';
        if (text.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: tokens.surfacePanel.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: tokens.studioDivider.withValues(alpha: 0.22),
            ),
          ),
          child: Text(
            text,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: FontSizes.xs,
              height: 1.25,
              fontFamily: artifact.kind == GeneratedArtifactKind.json
                  ? EditorDefaults.studioMonospaceFontFamily
                  : null,
            ),
          ),
        );
      },
    );
  }

  bool _isBinaryPreviewOnly(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.powerPoint ||
      GeneratedArtifactKind.docx ||
      GeneratedArtifactKind.pdf => true,
      _ => false,
    };
  }

  static Future<String> _readArtifactPreview(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return '';
    final bytes = await file
        .openRead(0, 4096)
        .fold<List<int>>(
          <int>[],
          (previous, element) => previous..addAll(element),
        );
    return String.fromCharCodes(
      bytes,
      0,
      bytes.length,
    ).replaceAll('\u0000', '').trim();
  }
}

class _ArtifactStructuredPreview extends ConsumerWidget {
  final GeneratedArtifact artifact;

  const _ArtifactStructuredPreview({required this.artifact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
            child: Row(
              children: [
                Icon(
                  _previewIcon(artifact.kind),
                  color: tokens.textMuted,
                  size: 13,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _previewTitle(artifact),
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
                if (artifact.sheetCount > 0 ||
                    artifact.kind == GeneratedArtifactKind.diagram)
                  Text(
                    _previewCount(artifact),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
          _ArtifactTablePreview(rows: artifact.previewRows, embedded: true),
        ],
      ),
    );
  }

  IconData _previewIcon(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.csv => StudioIcons.tableChartOutlined,
      GeneratedArtifactKind.powerPoint => StudioIcons.viewCarouselOutlined,
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

  String _previewTitle(GeneratedArtifact artifact) {
    if (studioIsArtifactPackageManifest(artifact)) return 'Package contents';
    final persisted = studioArtifactMetadataString(
      artifact,
      'artifactPreviewSurface',
    );
    if (persisted.isNotEmpty) return persisted;
    return studioArtifactDescriptorFor(artifact.kind).previewSurface;
  }

  String _previewCount(GeneratedArtifact artifact) {
    return switch (artifact.kind) {
      GeneratedArtifactKind.powerPoint => '${artifact.sheetCount} slides',
      GeneratedArtifactKind.docx => '${artifact.sheetCount} sections',
      GeneratedArtifactKind.pdf => '${artifact.sheetCount} pages',
      GeneratedArtifactKind.chart => '${artifact.sheetCount} charts',
      GeneratedArtifactKind.excel => '${artifact.sheetCount} sheets',
      GeneratedArtifactKind.diagram =>
        studioArtifactMetadataInt(artifact, 'nodeCount') > 0
            ? '${studioArtifactMetadataInt(artifact, 'nodeCount')} nodes'
            : '${artifact.previewRows.length - 1} signals',
      _ => '${artifact.sheetCount} items',
    };
  }
}

class _BinaryArtifactPreview extends ConsumerWidget {
  final GeneratedArtifact artifact;

  const _BinaryArtifactPreview({required this.artifact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final detail = switch (artifact.kind) {
      GeneratedArtifactKind.powerPoint =>
        artifact.sheetCount > 0
            ? '${artifact.sheetCount} slide deck'
            : 'PowerPoint deck',
      GeneratedArtifactKind.excel =>
        artifact.sheetCount > 0
            ? '${artifact.sheetCount} sheet workbook'
            : 'Excel workbook',
      GeneratedArtifactKind.docx => 'Word document',
      GeneratedArtifactKind.pdf =>
        artifact.sheetCount > 0
            ? '${artifact.sheetCount} page PDF document'
            : 'PDF document',
      _ => artifact.typeLabel,
    };
    final extension = p.extension(artifact.fileName).replaceFirst('.', '');
    final parts = <String>[
      if (extension.isNotEmpty) extension.toUpperCase(),
      if (artifact.byteSize > 0) studioArtifactFormatBytes(artifact.byteSize),
      if (artifact.sheetCount > 0) _binaryCountLabel(artifact),
    ];
    final trustBoundary = studioArtifactMetadataString(
      artifact,
      'artifactTrustBoundary',
    );
    final evidenceReadiness = studioArtifactMetadataString(
      artifact,
      'artifactEvidenceReadiness',
    );
    final primaryAction = studioArtifactMetadataString(
      artifact,
      'artifactPrimaryAction',
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            artifact.kind == GeneratedArtifactKind.powerPoint
                ? StudioIcons.slideshowOutlined
                : StudioIcons.insertDriveFileOutlined,
            color: tokens.textMuted,
            size: 15,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$detail ready',
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
                Text(
                  trustBoundary.isEmpty
                      ? 'Open to inspect the full document in its native app.'
                      : trustBoundary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xxs,
                    height: 1.2,
                  ),
                ),
                if (evidenceReadiness.isNotEmpty ||
                    primaryAction.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (evidenceReadiness.isNotEmpty) evidenceReadiness,
                      if (primaryAction.isNotEmpty) primaryAction,
                    ].join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xxs,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (parts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final part in parts)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.studioControl.withValues(alpha: 0.32),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: tokens.studioDivider.withValues(
                                alpha: 0.18,
                              ),
                            ),
                          ),
                          child: Text(
                            part,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: FontSizes.xxs,
                              height: 1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _binaryCountLabel(GeneratedArtifact artifact) {
    return switch (artifact.kind) {
      GeneratedArtifactKind.powerPoint => '${artifact.sheetCount} slides',
      GeneratedArtifactKind.excel => '${artifact.sheetCount} sheets',
      GeneratedArtifactKind.pdf => '${artifact.sheetCount} pages',
      GeneratedArtifactKind.docx => '${artifact.sheetCount} sections',
      _ => '${artifact.sheetCount} items',
    };
  }
}

class _ArtifactTablePreview extends ConsumerWidget {
  final List<List<String>> rows;
  final bool embedded;

  const _ArtifactTablePreview({required this.rows, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final visibleRows = rows.take(6).toList(growable: false);
    final columnCount = visibleRows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    final table = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(
          horizontalInside: BorderSide(
            color: tokens.studioDivider.withValues(alpha: 0.16),
          ),
        ),
        children: [
          for (var rowIndex = 0; rowIndex < visibleRows.length; rowIndex++)
            TableRow(
              decoration: BoxDecoration(
                color: rowIndex == 0
                    ? tokens.studioControl.withValues(alpha: 0.36)
                    : Colors.transparent,
              ),
              children: [
                for (
                  var columnIndex = 0;
                  columnIndex < columnCount;
                  columnIndex++
                )
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      columnIndex < visibleRows[rowIndex].length
                          ? visibleRows[rowIndex][columnIndex]
                          : '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: rowIndex == 0
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                        fontSize: FontSizes.xxs,
                        height: 1.18,
                        fontWeight: rowIndex == 0
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
    if (embedded) return table;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surfacePanel.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: table,
    );
  }
}
