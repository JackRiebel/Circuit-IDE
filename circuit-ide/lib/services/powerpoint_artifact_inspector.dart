import 'dart:convert';

class PowerPointArtifactInspection {
  final bool hasZipHeader;
  final bool hasContentTypes;
  final bool hasPresentation;
  final bool hasTheme;
  final bool hasSlideMaster;
  final bool hasCoreProperties;
  final bool hasExtendedProperties;
  final int slideCount;
  final int declaredSlideCount;
  final String? title;
  final List<String> slideTypes;
  final bool hasCircuitFooter;
  final bool hasAgenda;
  final bool hasDecisionSnapshot;
  final bool hasSectionDivider;
  final bool hasTableSlide;
  final bool hasAppendix;
  final bool hasEnterpriseStyling;

  const PowerPointArtifactInspection({
    required this.hasZipHeader,
    required this.hasContentTypes,
    required this.hasPresentation,
    required this.hasTheme,
    required this.hasSlideMaster,
    required this.hasCoreProperties,
    required this.hasExtendedProperties,
    required this.slideCount,
    required this.declaredSlideCount,
    required this.title,
    required this.slideTypes,
    required this.hasCircuitFooter,
    required this.hasAgenda,
    required this.hasDecisionSnapshot,
    required this.hasSectionDivider,
    required this.hasTableSlide,
    required this.hasAppendix,
    required this.hasEnterpriseStyling,
  });

  bool get isStructurallyValid =>
      hasZipHeader &&
      hasContentTypes &&
      hasPresentation &&
      hasTheme &&
      hasSlideMaster &&
      hasCoreProperties &&
      hasExtendedProperties &&
      slideCount > 0 &&
      declaredSlideCount == slideCount;

  bool get hasExpectedDeckStructure =>
      isStructurallyValid &&
      hasAgenda &&
      hasDecisionSnapshot &&
      hasSectionDivider &&
      hasTableSlide &&
      hasAppendix &&
      hasCircuitFooter &&
      hasEnterpriseStyling;
}

class PowerPointArtifactInspector {
  const PowerPointArtifactInspector();

  PowerPointArtifactInspection inspect(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final slideFiles =
        RegExp(r'ppt/slides/slide(\d+)\.xml')
            .allMatches(text)
            .map((match) => int.tryParse(match.group(1) ?? ''))
            .whereType<int>()
            .toSet()
            .toList(growable: false)
          ..sort();
    final slideTypes =
        RegExp(r'<p:cNvPr id="7" name="Slide type"[\s\S]*?<a:t>(.*?)</a:t>')
            .allMatches(text)
            .map((match) => _xmlDecode(match.group(1) ?? ''))
            .toList(growable: false);
    return PowerPointArtifactInspection(
      hasZipHeader:
          bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4b &&
          bytes[2] == 0x03 &&
          bytes[3] == 0x04,
      hasContentTypes: text.contains('[Content_Types].xml'),
      hasPresentation: text.contains('ppt/presentation.xml'),
      hasTheme:
          text.contains('ppt/theme/theme1.xml') &&
          text.contains('<a:theme') &&
          text.contains('name="Circuit"'),
      hasSlideMaster: text.contains('ppt/slideMasters/slideMaster1.xml'),
      hasCoreProperties:
          text.contains('docProps/core.xml') &&
          text.contains('<dc:creator>CircuitCode</dc:creator>'),
      hasExtendedProperties:
          text.contains('docProps/app.xml') &&
          text.contains('<Application>CircuitCode</Application>'),
      slideCount: slideFiles.length,
      declaredSlideCount: _declaredSlideCount(text),
      title: _firstElementText(text, 'dc:title'),
      slideTypes: slideTypes,
      hasCircuitFooter: text.contains('CircuitCode - Generated artifact'),
      hasAgenda: text.contains('Agenda'),
      hasDecisionSnapshot:
          text.contains('Decision Snapshot') || slideTypes.contains('Decision'),
      hasSectionDivider: slideTypes.contains('Section'),
      hasTableSlide: slideTypes.contains('Table'),
      hasAppendix: slideTypes.contains('Appendix'),
      hasEnterpriseStyling:
          text.contains('Content panel') &&
          text.contains('Header rule') &&
          text.contains('Accent') &&
          text.contains('PresentationFormat'),
    );
  }

  static int _declaredSlideCount(String text) {
    final declared = _firstElementText(text, 'Slides');
    if (declared != null) return int.tryParse(declared) ?? 0;
    return RegExp(r'<p:sldId\b').allMatches(text).length;
  }

  static String? _firstElementText(String text, String element) {
    final match = RegExp(
      '<$element[^>]*>([\\s\\S]*?)</$element>',
      caseSensitive: false,
    ).firstMatch(text);
    final value = match?.group(1);
    return value == null ? null : _xmlDecode(value);
  }

  static String _xmlDecode(String value) => value
      .replaceAll('&quot;', '"')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&');
}
