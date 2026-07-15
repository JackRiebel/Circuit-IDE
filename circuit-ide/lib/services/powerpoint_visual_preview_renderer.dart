import 'dart:convert';

import '../models/artifact_document.dart';
import '../models/artifact_template.dart';
import 'powerpoint_artifact_renderer.dart';

/// Deterministic first-slide preview for a generated PowerPoint package.
///
/// macOS Quick Look can stall on PPTX in headless CI, so the artifact pipeline
/// emits this reviewable SVG from the same shared document consumed by the
/// PPTX renderer. It makes title, brand, footer, confidentiality, and bounded
/// content geometry inspectable without claiming to be an Office rendering.
class PowerPointVisualPreviewRenderer {
  final PowerPointArtifactRenderer deckRenderer;

  const PowerPointVisualPreviewRenderer({
    this.deckRenderer = const PowerPointArtifactRenderer(),
  });

  PowerPointVisualPreview render(ArtifactDocument document) {
    final template = const ArtifactTemplateRegistry().fromDocument(document);
    final isDark = template.layout == 'executive-dark';
    final title = _truncate(document.title, 76);
    final sourceLines = [
      for (final section in document.sections) ...section.bullets,
      for (final section in document.sections)
        if (section.body.trim().isNotEmpty) _firstSentence(section.body),
    ].where((value) => value.trim().isNotEmpty).toList(growable: false);
    final bullets = sourceLines.take(5).toList(growable: false);
    final hasTitleOverflow = document.title.trim().length > 76;
    final hasContentOverflow =
        sourceLines.length > 5 ||
        sourceLines.any((line) => _normalizedLength(line) > 96);
    final background = isDark ? '161616' : 'F8FAFC';
    final panel = isDark ? '202020' : 'FFFFFF';
    final bodyText = isDark ? 'F4F4F5' : '172033';
    final mutedText = isDark ? 'C4C7CC' : '64748B';
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900" viewBox="0 0 1600 900" role="img" aria-labelledby="title desc">',
      )
      ..writeln(
        '<title id="title">${_escape(template.logoText)} PowerPoint preview</title>',
      )
      ..writeln(
        '<desc id="desc">Generated first-slide review preview for ${_escape(document.title)}.</desc>',
      )
      ..writeln('<rect width="1600" height="900" fill="#$background"/>')
      ..writeln(
        '<rect width="20" height="900" fill="#${template.accentColor}"/>',
      )
      ..writeln(
        '<rect x="84" y="208" width="1430" height="578" rx="12" fill="#$panel"/>',
      )
      ..writeln(
        '<rect x="92" y="92" width="480" height="8" fill="#${template.accentColor}"/>',
      )
      ..writeln(
        '<text x="92" y="68" fill="#${template.accentColor}" font-family="${_escape(template.fontFamily)}" font-size="24" font-weight="700" letter-spacing="3">${_escape(template.logoText)}</text>',
      )
      ..writeln(
        '<text x="1508" y="68" fill="#${template.accentColor}" font-family="${_escape(template.fontFamily)}" font-size="20" font-weight="700" text-anchor="end">${_escape(template.confidentialityLabel)}</text>',
      )
      ..writeln(
        '<text x="92" y="160" fill="#$bodyText" font-family="${_escape(template.fontFamily)}" font-size="58" font-weight="700">${_escape(title)}</text>',
      )
      ..writeln(
        '<text x="112" y="278" fill="#$mutedText" font-family="${_escape(template.fontFamily)}" font-size="24" font-weight="700">EXECUTIVE SUMMARY</text>',
      );
    for (var index = 0; index < bullets.length; index++) {
      final y = 350 + (index * 72);
      buffer
        ..writeln(
          '<circle cx="128" cy="$y" r="8" fill="#${template.accentColor}"/>',
        )
        ..writeln(
          '<text x="160" y="${y + 8}" fill="#$bodyText" font-family="${_escape(template.fontFamily)}" font-size="30">${_escape(_truncate(bullets[index], 96))}</text>',
        );
    }
    if (bullets.isEmpty) {
      buffer.writeln(
        '<text x="112" y="350" fill="#$mutedText" font-family="${_escape(template.fontFamily)}" font-size="30">No summary bullets were available.</text>',
      );
    }
    buffer
      ..writeln(
        '<line x1="92" y1="834" x2="1508" y2="834" stroke="#${template.accentColor}" stroke-width="2"/>',
      )
      ..writeln(
        '<text x="92" y="866" fill="#$mutedText" font-family="${_escape(template.fontFamily)}" font-size="20">${_escape(template.footerText)}</text>',
      )
      ..writeln(
        '<text x="1508" y="866" fill="#$mutedText" font-family="${_escape(template.fontFamily)}" font-size="20" text-anchor="end">Slide 1 preview</text>',
      )
      ..writeln('</svg>');
    return PowerPointVisualPreview(
      bytes: utf8.encode(buffer.toString()),
      metadata: {
        'pptxVisualPreviewRenderer': 'artifact_document_first_slide_v1',
        'pptxVisualPreviewSlideCount': 1,
        'pptxVisualPreviewHasTitleOverflow': hasTitleOverflow,
        'pptxVisualPreviewHasContentOverflow': hasContentOverflow,
        'pptxVisualPreviewHasTextTruncation':
            hasTitleOverflow || hasContentOverflow,
        'pptxVisualPreviewBulletCount': bullets.length,
        'pptxVisualPreviewTemplateId': template.id,
      },
    );
  }

  /// Builds a page for every slide emitted by [PowerPointArtifactRenderer].
  ///
  /// This remains a deterministic structural review surface, not an Office or
  /// Quick Look render. Unlike the legacy first-slide preview, it exposes
  /// title and content clipping risk across the full bounded deck.
  PowerPointVisualPreview renderDeck(ArtifactDocument document) {
    final template = const ArtifactTemplateRegistry().fromDocument(document);
    final isDark = template.layout == 'executive-dark';
    final background = isDark ? '161616' : 'F8FAFC';
    final panel = isDark ? '202020' : 'FFFFFF';
    final bodyText = isDark ? 'F4F4F5' : '172033';
    final mutedText = isDark ? 'C4C7CC' : '64748B';
    final slides = deckRenderer.reviewSlidesFor(document);
    final reviewSlides = slides.isEmpty
        ? const [
            PowerPointSlideReview(
              title: 'Untitled deck',
              eyebrow: 'Review',
              kind: 'Content',
              contentLines: [],
            ),
          ]
        : slides;
    final titleOverflowSlides = <int>[];
    final contentOverflowSlides = <int>[];
    for (var index = 0; index < reviewSlides.length; index++) {
      final slide = reviewSlides[index];
      if (_normalizedLength(slide.title) > 76) {
        titleOverflowSlides.add(index + 1);
      }
      // The deck renderer creates continuation slides rather than packing an
      // arbitrary number of rows into one frame, and regular narrative wraps
      // inside its text boxes. Values beyond this multi-line budget are the
      // remaining package-level clipping/truncation risk.
      if (slide.contentLines.any((line) => _normalizedLength(line) > 220)) {
        contentOverflowSlides.add(index + 1);
      }
    }
    final overflowSlides = <int>{
      ...titleOverflowSlides,
      ...contentOverflowSlides,
    }.toList()..sort();
    final totalHeight = 900 * reviewSlides.length;
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="$totalHeight" viewBox="0 0 1600 $totalHeight" role="img" aria-labelledby="title desc">',
      )
      ..writeln(
        '<title id="title">${_escape(template.logoText)} PowerPoint structural review</title>',
      )
      ..writeln(
        '<desc id="desc">Structural layout review for ${_escape(document.title)} across ${reviewSlides.length} generated ${reviewSlides.length == 1 ? 'slide' : 'slides'}. Native PowerPoint rendering is reviewed separately.</desc>',
      );
    for (var index = 0; index < reviewSlides.length; index++) {
      final slide = reviewSlides[index];
      final slideNumber = index + 1;
      final yOffset = index * 900;
      final hasTitleOverflow = titleOverflowSlides.contains(slideNumber);
      final hasContentOverflow = contentOverflowSlides.contains(slideNumber);
      final hasOverflow = hasTitleOverflow || hasContentOverflow;
      final visibleLines = slide.contentLines.take(7).toList(growable: false);
      buffer
        ..writeln(
          '<rect y="$yOffset" width="1600" height="900" fill="#$background"/>',
        )
        ..writeln(
          '<rect x="0" y="$yOffset" width="20" height="900" fill="#${template.accentColor}"/>',
        )
        ..writeln(
          '<rect x="84" y="${yOffset + 208}" width="1430" height="578" rx="12" fill="#$panel"/>',
        )
        ..writeln(
          '<rect x="92" y="${yOffset + 92}" width="480" height="8" fill="#${template.accentColor}"/>',
        )
        ..writeln(
          '<text x="92" y="${yOffset + 68}" fill="#${template.accentColor}" font-family="${_escape(template.fontFamily)}" font-size="24" font-weight="700" letter-spacing="3">${_escape(template.logoText)}</text>',
        )
        ..writeln(
          '<text x="1508" y="${yOffset + 68}" fill="#${template.accentColor}" font-family="${_escape(template.fontFamily)}" font-size="20" font-weight="700" text-anchor="end">${_escape(template.confidentialityLabel)}</text>',
        )
        ..writeln(
          '<text x="92" y="${yOffset + 160}" fill="#$bodyText" font-family="${_escape(template.fontFamily)}" font-size="58" font-weight="700">${_escape(_truncate(slide.title, 76))}</text>',
        )
        ..writeln(
          '<text x="112" y="${yOffset + 278}" fill="#$mutedText" font-family="${_escape(template.fontFamily)}" font-size="24" font-weight="700">${_escape(_truncate('${slide.eyebrow} · ${slide.kind}', 80))}</text>',
        );
      for (var lineIndex = 0; lineIndex < visibleLines.length; lineIndex++) {
        final y = yOffset + 350 + (lineIndex * 58);
        buffer
          ..writeln(
            '<circle cx="128" cy="$y" r="8" fill="#${template.accentColor}"/>',
          )
          ..writeln(
            '<text x="160" y="${y + 8}" fill="#$bodyText" font-family="${_escape(template.fontFamily)}" font-size="26">${_escape(_truncate(visibleLines[lineIndex], 96))}</text>',
          );
      }
      if (visibleLines.isEmpty) {
        buffer.writeln(
          '<text x="112" y="${yOffset + 350}" fill="#$mutedText" font-family="${_escape(template.fontFamily)}" font-size="26">No visible slide content was available for review.</text>',
        );
      }
      final flags = <String>[
        if (hasTitleOverflow) 'Title exceeds review frame',
        if (hasContentOverflow) 'Slide content exceeds review frame',
        if (!hasOverflow) 'No structural text overflow detected',
      ];
      buffer
        ..writeln(
          '<rect x="92" y="${yOffset + 700}" width="1416" height="58" rx="6" fill="#${hasOverflow ? 'FEE2E2' : (isDark ? '253126' : 'ECFDF3')}"/>',
        )
        ..writeln(
          '<text x="112" y="${yOffset + 736}" fill="#${hasOverflow ? '991B1B' : (isDark ? '86EFAC' : '166534')}" font-family="${_escape(template.fontFamily)}" font-size="16" font-weight="700">${_escape(flags.join(' · '))}</text>',
        )
        ..writeln(
          '<line x1="92" y1="${yOffset + 834}" x2="1508" y2="${yOffset + 834}" stroke="#${template.accentColor}" stroke-width="2"/>',
        )
        ..writeln(
          '<text x="92" y="${yOffset + 866}" fill="#$mutedText" font-family="${_escape(template.fontFamily)}" font-size="20">${_escape(template.footerText)}</text>',
        )
        ..writeln(
          '<text x="1508" y="${yOffset + 866}" fill="#$mutedText" font-family="${_escape(template.fontFamily)}" font-size="20" text-anchor="end">Structural review · slide $slideNumber of ${reviewSlides.length}</text>',
        );
    }
    buffer.writeln('</svg>');
    return PowerPointVisualPreview(
      bytes: utf8.encode(buffer.toString()),
      metadata: {
        'pptxVisualPreviewRenderer': 'artifact_document_multislide_v2',
        'pptxVisualPreviewReviewMode': 'structural_multi_slide',
        'pptxVisualPreviewSlideCount': reviewSlides.length,
        'pptxVisualPreviewReviewPageCount': reviewSlides.length,
        'pptxVisualPreviewFirstSlideOnly': false,
        'pptxVisualPreviewHasTitleOverflow': titleOverflowSlides.isNotEmpty,
        'pptxVisualPreviewHasContentOverflow': contentOverflowSlides.isNotEmpty,
        'pptxVisualPreviewHasTextTruncation': overflowSlides.isNotEmpty,
        'pptxVisualPreviewOverflowSlideNumbers': overflowSlides,
        'pptxVisualPreviewOverflowSlideCount': overflowSlides.length,
      },
    );
  }

  String _firstSentence(String value) {
    final normalized = value.replaceAll('\n', ' ').trim();
    final match = RegExp(r'^(.{1,140}?[.!?])(?:\s|$)').firstMatch(normalized);
    return match?.group(1) ?? normalized;
  }

  String _truncate(String value, int limit) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= limit
        ? normalized
        : '${normalized.substring(0, limit - 1).trimRight()}…';
  }

  int _normalizedLength(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim().length;

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class PowerPointVisualPreview {
  final List<int> bytes;
  final Map<String, Object?> metadata;

  const PowerPointVisualPreview({required this.bytes, required this.metadata});
}
