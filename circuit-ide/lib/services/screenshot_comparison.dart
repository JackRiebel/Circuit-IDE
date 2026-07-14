import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/context_attachment.dart';
import 'screenshot_context_attachment_builder.dart';

/// A normalized rectangle in an image. Values are fractions of image width
/// and height, so a finding remains meaningful after the image is resized.
class ScreenshotComparisonRegion {
  final double x;
  final double y;
  final double width;
  final double height;

  const ScreenshotComparisonRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  bool get isValid =>
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1 &&
      y + height <= 1;

  String get label =>
      '${_percent(x)}, ${_percent(y)}, ${_percent(width)}, ${_percent(height)}';

  Map<String, double> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  static ScreenshotComparisonRegion? tryParse(String value) {
    final values = value
        .split(',')
        .map((part) => double.tryParse(part.trim()))
        .toList(growable: false);
    if (values.length != 4 || values.any((part) => part == null)) return null;
    final region = ScreenshotComparisonRegion(
      x: values[0]!,
      y: values[1]!,
      width: values[2]!,
      height: values[3]!,
    );
    return region.isValid ? region : null;
  }

  static String _percent(double value) => '${(value * 100).round()}%';
}

enum ScreenshotComparisonSide { reference, current }

extension ScreenshotComparisonSideLabel on ScreenshotComparisonSide {
  String get label =>
      this == ScreenshotComparisonSide.reference ? 'Reference' : 'Current';
}

/// A user-supplied region finding. The model can add additional findings in
/// its response, but these annotations are already reviewable and durable.
class ScreenshotComparisonFinding {
  final ScreenshotComparisonSide side;
  final String text;
  final ScreenshotComparisonRegion region;

  const ScreenshotComparisonFinding({
    required this.side,
    required this.text,
    required this.region,
  });

  Map<String, Object> toJson() => {
    'side': side.name,
    'text': text,
    'region': region.toJson(),
  };

  String get citation => '${side.label} region (${region.label}): $text';
}

/// Parsed form of `/compare reference.png | current.png | current: finding @
/// 0.10,0.20,0.30,0.15`. Additional `| side: finding @ x,y,w,h` segments can
/// record several annotated findings in the same request.
class ScreenshotComparisonDirective {
  final String referencePath;
  final String currentPath;
  final List<ScreenshotComparisonFinding> findings;

  const ScreenshotComparisonDirective({
    required this.referencePath,
    required this.currentPath,
    this.findings = const [],
  });

  static ScreenshotComparisonDirective? tryParse(String raw) {
    final parts = raw
        .split('|')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) return null;
    final referencePath = parts[0];
    final currentPath = parts[1];
    if (referencePath.isEmpty || currentPath.isEmpty) return null;
    final findings = <ScreenshotComparisonFinding>[];
    for (final value in parts.skip(2)) {
      final finding = _findingFrom(value);
      if (finding == null) return null;
      findings.add(finding);
    }
    return ScreenshotComparisonDirective(
      referencePath: referencePath,
      currentPath: currentPath,
      findings: findings,
    );
  }

  static ScreenshotComparisonFinding? _findingFrom(String value) {
    final match = RegExp(
      r'^\s*(?:(reference|current)\s*:\s*)?(.+?)\s*@\s*([0-9.,\s]+)\s*$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final text = match.group(2)?.trim() ?? '';
    final region = ScreenshotComparisonRegion.tryParse(match.group(3) ?? '');
    if (text.isEmpty || region == null) return null;
    return ScreenshotComparisonFinding(
      side: match.group(1)?.toLowerCase() == 'reference'
          ? ScreenshotComparisonSide.reference
          : ScreenshotComparisonSide.current,
      text: text,
      region: region,
    );
  }

  String get usage =>
      '/compare reference.png | current.png | current: finding @ 0.10,0.20,0.30,0.15';
}

class ScreenshotComparisonAttachmentSet {
  final String comparisonId;
  final List<ContextAttachment> attachments;

  const ScreenshotComparisonAttachmentSet({
    required this.comparisonId,
    required this.attachments,
  });
}

/// Turns a reference/current image pair into independently deliverable pixel
/// inputs plus a durable comparison note. The note makes region citations
/// available to plans, patches, and exported context without pretending that
/// a non-vision model inspected pixels.
class ScreenshotComparisonAttachmentBuilder {
  final ScreenshotContextAttachmentBuilder imageBuilder;

  const ScreenshotComparisonAttachmentBuilder({
    this.imageBuilder = const ScreenshotContextAttachmentBuilder(),
  });

  Future<ScreenshotComparisonAttachmentSet> build({
    required String referencePath,
    required String currentPath,
    List<ScreenshotComparisonFinding> findings = const [],
  }) async {
    final normalizedReference = p.normalize(referencePath);
    final normalizedCurrent = p.normalize(currentPath);
    final comparisonId = _comparisonId(normalizedReference, normalizedCurrent);
    final reference = await imageBuilder.build(normalizedReference);
    final current = await imageBuilder.build(normalizedCurrent);
    final resolvedReference =
        reference ?? _unsupportedImage(normalizedReference);
    final resolvedCurrent = current ?? _unsupportedImage(normalizedCurrent);
    final serializedFindings = findings
        .map((finding) => finding.toJson())
        .toList(growable: false);
    final attachments = <ContextAttachment>[
      _decorateImage(
        attachment: resolvedReference,
        id: '$comparisonId:reference',
        side: ScreenshotComparisonSide.reference,
        partnerPath: normalizedCurrent,
        comparisonId: comparisonId,
        findings: serializedFindings,
      ),
      _decorateImage(
        attachment: resolvedCurrent,
        id: '$comparisonId:current',
        side: ScreenshotComparisonSide.current,
        partnerPath: normalizedReference,
        comparisonId: comparisonId,
        findings: serializedFindings,
      ),
      ContextAttachment(
        id: '$comparisonId:findings',
        type: ContextAttachmentType.note,
        label:
            'Screenshot comparison: ${p.basename(normalizedReference)} → ${p.basename(normalizedCurrent)}',
        content: _comparisonPrompt(
          referencePath: normalizedReference,
          currentPath: normalizedCurrent,
          comparisonId: comparisonId,
          findings: findings,
        ),
        resolutionStatus: ContextAttachmentResolutionStatus.resolved,
        estimatedTokens: 120 + findings.length * 24,
        metadata: {
          'artifactRole': 'visual_comparison',
          'comparisonId': comparisonId,
          'referencePath': normalizedReference,
          'currentPath': normalizedCurrent,
          'comparisonFindings': serializedFindings,
          'comparisonCitationFormat':
              '$comparisonId · [Reference|Current region x,y,width,height]',
          'comparisonProvenance':
              'User-selected screenshot pair with normalized annotated regions.',
        },
        createdAt: DateTime.now(),
      ),
    ];
    return ScreenshotComparisonAttachmentSet(
      comparisonId: comparisonId,
      attachments: attachments,
    );
  }

  ContextAttachment _decorateImage({
    required ContextAttachment attachment,
    required String id,
    required ScreenshotComparisonSide side,
    required String partnerPath,
    required String comparisonId,
    required List<Map<String, Object>> findings,
  }) {
    return attachment.copyWith(
      id: id,
      label: '${side.label} — ${attachment.label}',
      content: [
        attachment.content?.trim() ?? '',
        'Comparison role: ${side.label}.',
        'Comparison partner: ${p.basename(partnerPath)}.',
        'Comparison citation: $comparisonId · ${side.label}.',
      ].where((line) => line.isNotEmpty).join('\n'),
      metadata: {
        ...attachment.metadata,
        'artifactRole': 'visual_comparison',
        'comparisonId': comparisonId,
        'comparisonRole': side.name,
        'comparisonPartnerPath': partnerPath,
        'comparisonFindings': findings,
        'comparisonCitation': '$comparisonId · ${side.label}',
      },
    );
  }

  ContextAttachment _unsupportedImage(String path) => ContextAttachment(
    id: 'comparison:unsupported:$path',
    type: ContextAttachmentType.image,
    label: p.basename(path),
    path: path,
    content: 'Comparison image is not a supported PNG, JPG, GIF, or WebP file.',
    resolutionStatus: ContextAttachmentResolutionStatus.skipped,
    estimatedTokens: 18,
    metadata: const {
      'artifactRole': 'visual_comparison',
      'visionInputStatus': 'unsupported_image',
    },
    createdAt: DateTime.now(),
  );

  String _comparisonPrompt({
    required String referencePath,
    required String currentPath,
    required String comparisonId,
    required List<ScreenshotComparisonFinding> findings,
  }) {
    return [
      'Screenshot comparison $comparisonId.',
      'Reference: ${p.basename(referencePath)}.',
      'Current: ${p.basename(currentPath)}.',
      'Compare the two supplied images only when the selected model accepts image pixels. Otherwise, retain their metadata and ask for a description or a vision-capable model.',
      'For each visual finding, cite its side and normalized region as `[Reference|Current region x,y,width,height]` so the finding remains linked to the screenshot in any plan, patch, or handoff artifact.',
      if (findings.isNotEmpty) 'User-annotated findings:',
      ...findings.map((finding) => '- ${finding.citation}'),
    ].join('\n');
  }

  String _comparisonId(String referencePath, String currentPath) {
    final digest = sha256
        .convert(utf8.encode('$referencePath\u0000$currentPath'))
        .toString()
        .substring(0, 12);
    return 'comparison-$digest';
  }
}
