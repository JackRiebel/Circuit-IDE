import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/context_attachment.dart';
import '../../services/screenshot_comparison.dart';
import '../../services/screenshot_context_attachment_builder.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';

/// Parsed image or screenshot-comparison input shown before a prompt is sent.
class ComposerImagePreviewData {
  final String path;
  final String? role;
  final String? referencePath;
  final String? currentPath;
  final List<ScreenshotComparisonFinding> findings;

  const ComposerImagePreviewData({
    required this.path,
    this.role,
    this.referencePath,
    this.currentPath,
    this.findings = const [],
  });

  bool get isComparison => referencePath != null && currentPath != null;
}

List<ComposerImagePreviewData> studioImageDirectivePreviews(String text) {
  final previews = <ComposerImagePreviewData>[];
  final seen = <String>{};
  for (final line in text.split('\n')) {
    final path = _imageDirectivePath(line);
    if (path != null && seen.add(path)) {
      previews.add(ComposerImagePreviewData(path: path));
      continue;
    }
    final comparison = _comparisonDirectiveFromLine(line);
    if (comparison == null) continue;
    final referencePath = p.normalize(comparison.referencePath);
    final currentPath = p.normalize(comparison.currentPath);
    if (seen.add(referencePath)) {
      previews.add(
        ComposerImagePreviewData(
          path: referencePath,
          role: 'Reference',
          referencePath: referencePath,
          currentPath: currentPath,
          findings: comparison.findings,
        ),
      );
    }
    if (seen.add(currentPath)) {
      previews.add(
        ComposerImagePreviewData(
          path: currentPath,
          role: 'Current',
          referencePath: referencePath,
          currentPath: currentPath,
          findings: comparison.findings,
        ),
      );
    }
  }
  return previews;
}

List<String> studioImageDirectivePaths(String text) =>
    studioImageDirectivePreviews(
      text,
    ).map((preview) => preview.path).toList(growable: false);

String? _imageDirectivePath(String line) {
  final match = RegExp(
    r'^\s*/(?:image|screenshot)\s+(.+?)\s*$',
  ).firstMatch(line);
  final path = match?.group(1)?.trim();
  return path == null || path.isEmpty ? null : p.normalize(path);
}

ScreenshotComparisonDirective? _comparisonDirectiveFromLine(String line) {
  final match = RegExp(r'^\s*/compare\s+(.+?)\s*$').firstMatch(line);
  final raw = match?.group(1);
  return raw == null ? null : ScreenshotComparisonDirective.tryParse(raw);
}

bool studioImageDirectiveReferencesPath(String line, String normalizedPath) {
  if (_imageDirectivePath(line) == normalizedPath) return true;
  final comparison = _comparisonDirectiveFromLine(line);
  return comparison != null &&
      (p.normalize(comparison.referencePath) == normalizedPath ||
          p.normalize(comparison.currentPath) == normalizedPath);
}

/// Compact, removable preview chip for an image directive in the composer.
class StudioImageDirectivePreview extends StatelessWidget {
  final String path;
  final String? role;
  final dynamic tokens;
  final VoidCallback onRemove;
  final VoidCallback onPreview;

  const StudioImageDirectivePreview({
    super.key,
    required this.path,
    required this.role,
    required this.tokens,
    required this.onRemove,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surfaceBase.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: StudioFocusableActionSurface(
              key: ValueKey('studio-image-preview-${p.normalize(path)}'),
              semanticLabel: role == null
                  ? 'Preview attached image ${p.basename(path)}'
                  : 'Preview $role comparison image ${p.basename(path)}',
              onTap: onPreview,
              borderRadius: BorderRadius.circular(Radii.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      File(path),
                      width: 34,
                      height: 34,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 34,
                        height: 34,
                        color: tokens.surfaceInset,
                        alignment: Alignment.center,
                        child: Icon(
                          StudioIcons.brokenImageOutlined,
                          size: 15,
                          color: tokens.warning,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.basename(path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: FontSizes.xxs,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          role == null
                              ? 'Vision input · checked before send'
                              : '$role · comparison input',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: FontSizes.xxs,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          StudioChromeIconButton(
            tooltip: 'Remove image',
            onTap: onRemove,
            icon: StudioIcons.close,
            width: 26,
            height: 26,
            iconSize: 14,
          ),
        ],
      ),
    );
  }
}

void showStudioImageDirectivePreview(
  BuildContext context,
  ComposerImagePreviewData preview,
) {
  final reference = preview.referencePath ?? preview.path;
  final current = preview.currentPath;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                preview.isComparison
                    ? 'Reference / current comparison'
                    : p.basename(preview.path),
                style: Theme.of(dialogContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                preview.isComparison
                    ? 'Scroll or pinch to zoom. Region citations remain attached to the request.'
                    : 'Scroll or pinch to zoom this attached image.',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _ZoomableImagePane(
                        label: preview.isComparison ? 'Reference' : 'Image',
                        path: reference,
                        findings: preview.findings
                            .where(
                              (finding) =>
                                  !preview.isComparison ||
                                  finding.side ==
                                      ScreenshotComparisonSide.reference,
                            )
                            .toList(growable: false),
                      ),
                    ),
                    if (current != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ZoomableImagePane(
                          label: 'Current',
                          path: current,
                          findings: preview.findings
                              .where(
                                (finding) =>
                                    finding.side ==
                                    ScreenshotComparisonSide.current,
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _OcrProvenancePreview(paths: [reference, ?current]),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OcrProvenancePreview extends StatelessWidget {
  final List<String> paths;

  const _OcrProvenancePreview({required this.paths});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait(
        paths.map(
          (path) => const ScreenshotContextAttachmentBuilder().build(path),
        ),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        final attachments =
            snapshot.data?.whereType<ContextAttachment>().toList(
              growable: false,
            ) ??
            const <ContextAttachment>[];
        final ocrAttachments = attachments
            .where(
              (attachment) => attachment.metadata['hasOcrFallback'] == true,
            )
            .toList(growable: false);
        if (ocrAttachments.isEmpty) {
          return Text(
            'OCR: no verified local or approved extraction. This image remains distinct from model vision.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        final details = ocrAttachments
            .map((attachment) {
              final engine =
                  attachment.metadata['ocrEngine']?.toString() ?? 'OCR';
              final confidence = attachment.metadata['ocrAverageConfidence'];
              final regions = attachment.metadata['ocrBoundingBoxCount'];
              final text =
                  attachment.metadata['ocrText']?.toString().trim() ?? '';
              final percentage = confidence is num
                  ? '${(confidence * 100).round()}%'
                  : 'unknown confidence';
              return '${p.basename(attachment.path ?? attachment.label)} · $engine · $percentage · $regions region(s)\n$text';
            })
            .join('\n\n');
        return Semantics(
          label: 'OCR provenance. $details',
          child: Container(
            constraints: const BoxConstraints(maxHeight: 112),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                'OCR provenance — remove the image attachment to remove this text and its regions.\n$details',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ZoomableImagePane extends ConsumerWidget {
  final String label;
  final String path;
  final List<ScreenshotComparisonFinding> findings;

  const _ZoomableImagePane({
    required this.label,
    required this.path,
    required this.findings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceInset,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: tokens.studioDivider.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('$label · ${p.basename(path)}', maxLines: 1),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(StudioIcons.brokenImageOutlined),
                ),
              ),
            ),
          ),
          if (findings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                findings
                    .map(
                      (finding) => '[${finding.region.label}] ${finding.text}',
                    )
                    .join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
