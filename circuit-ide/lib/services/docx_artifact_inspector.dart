import 'dart:convert';

class DocxArtifactInspection {
  final bool hasZipHeader;
  final bool hasContentTypes;
  final bool hasDocument;
  final bool hasStyles;
  final bool hasNumbering;
  final bool hasSettings;
  final bool hasFooter;
  final bool hasCoreProperties;
  final bool hasExtendedProperties;
  final String? title;
  final int paragraphCount;
  final int tableCount;
  final int bulletCount;
  final int headingCount;
  final int styleCount;
  final int declaredWordCount;
  final int declaredParagraphCount;
  final bool hasReportOverview;
  final bool hasExecutiveDecisionBrief;
  final bool hasRecommendationSummary;
  final bool hasRiskRegister;
  final bool hasNextStepActionPlan;
  final bool hasDocumentMap;
  final bool hasValidationChecklist;
  final bool hasAssumptionsAppendix;
  final bool hasSourcesAppendix;
  final bool hasCircuitFooter;
  final bool hasEnterpriseStyles;
  final bool hasKeywordsMetadata;

  const DocxArtifactInspection({
    required this.hasZipHeader,
    required this.hasContentTypes,
    required this.hasDocument,
    required this.hasStyles,
    required this.hasNumbering,
    required this.hasSettings,
    required this.hasFooter,
    required this.hasCoreProperties,
    required this.hasExtendedProperties,
    required this.title,
    required this.paragraphCount,
    required this.tableCount,
    required this.bulletCount,
    required this.headingCount,
    required this.styleCount,
    required this.declaredWordCount,
    required this.declaredParagraphCount,
    required this.hasReportOverview,
    required this.hasExecutiveDecisionBrief,
    required this.hasRecommendationSummary,
    required this.hasRiskRegister,
    required this.hasNextStepActionPlan,
    required this.hasDocumentMap,
    required this.hasValidationChecklist,
    required this.hasAssumptionsAppendix,
    required this.hasSourcesAppendix,
    required this.hasCircuitFooter,
    required this.hasEnterpriseStyles,
    required this.hasKeywordsMetadata,
  });

  bool get isStructurallyValid =>
      hasZipHeader &&
      hasContentTypes &&
      hasDocument &&
      hasStyles &&
      hasNumbering &&
      hasSettings &&
      hasFooter &&
      hasCoreProperties &&
      hasExtendedProperties &&
      paragraphCount > 0 &&
      styleCount >= 6;

  bool get hasExpectedReportStructure =>
      isStructurallyValid &&
      hasReportOverview &&
      hasExecutiveDecisionBrief &&
      hasRecommendationSummary &&
      hasRiskRegister &&
      hasNextStepActionPlan &&
      hasDocumentMap &&
      hasValidationChecklist &&
      hasCircuitFooter &&
      hasEnterpriseStyles &&
      hasKeywordsMetadata;
}

class DocxArtifactInspector {
  const DocxArtifactInspector();

  DocxArtifactInspection inspect(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return DocxArtifactInspection(
      hasZipHeader:
          bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4b &&
          bytes[2] == 0x03 &&
          bytes[3] == 0x04,
      hasContentTypes: text.contains('[Content_Types].xml'),
      hasDocument:
          text.contains('word/document.xml') && text.contains('<w:document'),
      hasStyles: text.contains('word/styles.xml') && text.contains('<w:styles'),
      hasNumbering:
          text.contains('word/numbering.xml') && text.contains('<w:numbering'),
      hasSettings:
          text.contains('word/settings.xml') && text.contains('<w:settings'),
      hasFooter: text.contains('word/footer1.xml') && text.contains('<w:ftr'),
      hasCoreProperties:
          text.contains('docProps/core.xml') &&
          text.contains('<dc:creator>CircuitCode</dc:creator>'),
      hasExtendedProperties:
          text.contains('docProps/app.xml') &&
          text.contains('<Application>CircuitCode</Application>'),
      title: _firstElementText(text, 'dc:title'),
      paragraphCount: RegExp(r'<w:p[ >]').allMatches(text).length,
      tableCount: RegExp(r'<w:tbl[ >]').allMatches(text).length,
      bulletCount: RegExp(r'<w:numPr>').allMatches(text).length,
      headingCount: RegExp(
        r'<w:pStyle w:val="Heading[12]"',
      ).allMatches(text).length,
      styleCount: RegExp(r'<w:style\b').allMatches(text).length,
      declaredWordCount: _intElement(text, 'Words') ?? 0,
      declaredParagraphCount: _intElement(text, 'Paragraphs') ?? 0,
      hasReportOverview: text.contains('Report Overview'),
      hasExecutiveDecisionBrief: text.contains('Executive Decision Brief'),
      hasRecommendationSummary: text.contains('Recommendation Summary'),
      hasRiskRegister: text.contains('Risk &amp; Assumption Register'),
      hasNextStepActionPlan: text.contains('Next-Step Action Plan'),
      hasDocumentMap: text.contains('Document Map'),
      hasValidationChecklist: text.contains('Validation Checklist'),
      hasAssumptionsAppendix: text.contains('Appendix A: Assumptions'),
      hasSourcesAppendix: text.contains('Appendix B: Sources / Evidence'),
      hasCircuitFooter: text.contains('CircuitCode - Generated artifact'),
      hasEnterpriseStyles:
          text.contains('Aptos') &&
          text.contains('Heading1') &&
          text.contains('Caption') &&
          text.contains('CBD5E1'),
      hasKeywordsMetadata:
          text.contains('<cp:keywords>') &&
          text.contains('enterprise') &&
          text.contains('CircuitCode'),
    );
  }

  static int? _intElement(String text, String element) =>
      int.tryParse(_firstElementText(text, element) ?? '');

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
