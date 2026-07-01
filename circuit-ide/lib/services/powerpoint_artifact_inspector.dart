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
  final bool hasAgendaLayout;
  final bool hasDecisionSnapshot;
  final bool hasDecisionMatrix;
  final bool hasExecutiveRecommendation;
  final bool hasRecommendationCards;
  final bool hasKeyTakeaways;
  final bool hasSectionDivider;
  final bool hasSectionDividerLayout;
  final bool hasEnterpriseBrandPill;
  final bool hasImplementationRoadmap;
  final bool hasRoadmapTimeline;
  final bool hasClosingDecisionAsk;
  final bool hasTableSlide;
  final bool hasAppendix;
  final bool hasSourcesSlide;
  final bool hasAssumptionsSourcesSlide;
  final bool hasEnterpriseStyling;
  final bool hasSlideNumbers;
  final bool hasSpeakerNotes;
  final int notesSlideCount;
  final bool usesLightTheme;
  final bool usesDarkTheme;

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
    required this.hasAgendaLayout,
    required this.hasDecisionSnapshot,
    required this.hasDecisionMatrix,
    required this.hasExecutiveRecommendation,
    required this.hasRecommendationCards,
    required this.hasKeyTakeaways,
    required this.hasSectionDivider,
    required this.hasSectionDividerLayout,
    required this.hasEnterpriseBrandPill,
    required this.hasImplementationRoadmap,
    required this.hasRoadmapTimeline,
    required this.hasClosingDecisionAsk,
    required this.hasTableSlide,
    required this.hasAppendix,
    required this.hasSourcesSlide,
    required this.hasAssumptionsSourcesSlide,
    required this.hasEnterpriseStyling,
    required this.hasSlideNumbers,
    required this.hasSpeakerNotes,
    required this.notesSlideCount,
    required this.usesLightTheme,
    required this.usesDarkTheme,
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
      hasAgendaLayout &&
      hasDecisionSnapshot &&
      hasDecisionMatrix &&
      hasExecutiveRecommendation &&
      hasRecommendationCards &&
      hasKeyTakeaways &&
      hasSectionDivider &&
      hasSectionDividerLayout &&
      hasEnterpriseBrandPill &&
      hasImplementationRoadmap &&
      hasRoadmapTimeline &&
      hasClosingDecisionAsk &&
      hasTableSlide &&
      hasAppendix &&
      hasSourcesSlide &&
      hasAssumptionsSourcesSlide &&
      hasCircuitFooter &&
      hasEnterpriseStyling &&
      hasSpeakerNotes &&
      hasSlideNumbers;
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
    final notesSlideFiles =
        RegExp(r'ppt/notesSlides/notesSlide(\d+)\.xml')
            .allMatches(text)
            .map((match) => int.tryParse(match.group(1) ?? ''))
            .whereType<int>()
            .toSet()
            .toList(growable: false)
          ..sort();
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
      hasAgendaLayout:
          text.contains('Agenda step') && text.contains('Agenda number rail'),
      hasDecisionSnapshot:
          text.contains('Decision Snapshot') || slideTypes.contains('Decision'),
      hasDecisionMatrix:
          text.contains('Decision Matrix') ||
          slideTypes.contains('Decision Matrix'),
      hasExecutiveRecommendation:
          text.contains('Executive Recommendation') ||
          slideTypes.contains('Recommendation'),
      hasRecommendationCards:
          text.contains('Recommendation card') &&
          text.contains('Recommendation card accent'),
      hasKeyTakeaways:
          text.contains('Key Takeaways') || slideTypes.contains('Takeaways'),
      hasSectionDivider: slideTypes.contains('Section'),
      hasSectionDividerLayout:
          text.contains('Section divider rail') &&
          text.contains('Section objective') &&
          text.contains('Section preview card') &&
          text.contains('Section progress marker'),
      hasEnterpriseBrandPill:
          text.contains('Enterprise brand pill') &&
          text.contains('CircuitCode enterprise artifact'),
      hasImplementationRoadmap:
          text.contains('Implementation Roadmap') ||
          slideTypes.contains('Roadmap'),
      hasRoadmapTimeline:
          text.contains('Roadmap timeline') &&
          text.contains('Roadmap phase marker'),
      hasClosingDecisionAsk:
          text.contains('Decision Ask &amp; Next Steps') ||
          slideTypes.contains('Close'),
      hasTableSlide: slideTypes.contains('Table'),
      hasAppendix: slideTypes.contains('Appendix'),
      hasSourcesSlide: slideTypes.contains('Sources'),
      hasAssumptionsSourcesSlide: text.contains('Assumptions &amp; Sources'),
      hasEnterpriseStyling:
          text.contains('Content panel') &&
          text.contains('Header rule') &&
          text.contains('Accent') &&
          text.contains('PresentationFormat'),
      hasSlideNumbers: RegExp(r'Slide \d+ of \d+').hasMatch(text),
      hasSpeakerNotes:
          text.contains('ppt/notesMasters/notesMaster1.xml') &&
          text.contains('CircuitCode speaker notes') &&
          text.contains('Presenter notes for') &&
          notesSlideFiles.length == slideFiles.length,
      notesSlideCount: notesSlideFiles.length,
      usesLightTheme: text.contains('Generated artifact - Light theme'),
      usesDarkTheme: text.contains('Generated artifact - Dark theme'),
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
