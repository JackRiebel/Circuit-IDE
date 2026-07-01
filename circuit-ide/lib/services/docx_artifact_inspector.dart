import 'dart:convert';

class DocxArtifactInspection {
  final bool hasZipHeader;
  final bool hasContentTypes;
  final bool hasDocument;
  final bool hasStyles;
  final bool hasNumbering;
  final bool hasSettings;
  final bool hasHeader;
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
  final bool hasLeadDecisionCallout;
  final bool hasTableOfContents;
  final bool hasExecutiveDecisionBrief;
  final bool hasRecommendationSummary;
  final bool hasRiskRegister;
  final bool hasNextStepActionPlan;
  final bool hasDocumentMap;
  final bool hasValidationChecklist;
  final bool hasCustomerHandoffScorecard;
  final bool hasDecisionLog;
  final bool hasAssumptionsAppendix;
  final bool hasSourcesAppendix;
  final bool hasCircuitHeader;
  final bool hasCircuitFooter;
  final bool hasEnterpriseStyles;
  final bool hasExplicitTableGeometry;
  final bool hasRepeatingTableHeaders;
  final bool hasKeywordsMetadata;

  const DocxArtifactInspection({
    required this.hasZipHeader,
    required this.hasContentTypes,
    required this.hasDocument,
    required this.hasStyles,
    required this.hasNumbering,
    required this.hasSettings,
    required this.hasHeader,
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
    required this.hasLeadDecisionCallout,
    required this.hasTableOfContents,
    required this.hasExecutiveDecisionBrief,
    required this.hasRecommendationSummary,
    required this.hasRiskRegister,
    required this.hasNextStepActionPlan,
    required this.hasDocumentMap,
    required this.hasValidationChecklist,
    required this.hasCustomerHandoffScorecard,
    required this.hasDecisionLog,
    required this.hasAssumptionsAppendix,
    required this.hasSourcesAppendix,
    required this.hasCircuitHeader,
    required this.hasCircuitFooter,
    required this.hasEnterpriseStyles,
    required this.hasExplicitTableGeometry,
    required this.hasRepeatingTableHeaders,
    required this.hasKeywordsMetadata,
  });

  bool get isStructurallyValid =>
      hasZipHeader &&
      hasContentTypes &&
      hasDocument &&
      hasStyles &&
      hasNumbering &&
      hasSettings &&
      hasHeader &&
      hasFooter &&
      hasCoreProperties &&
      hasExtendedProperties &&
      paragraphCount > 0 &&
      styleCount >= 6;

  bool get hasExpectedReportStructure =>
      isStructurallyValid &&
      hasReportOverview &&
      hasLeadDecisionCallout &&
      hasTableOfContents &&
      hasExecutiveDecisionBrief &&
      hasRecommendationSummary &&
      hasRiskRegister &&
      hasNextStepActionPlan &&
      hasDocumentMap &&
      hasValidationChecklist &&
      hasCustomerHandoffScorecard &&
      hasDecisionLog &&
      hasCircuitHeader &&
      hasCircuitFooter &&
      hasEnterpriseStyles &&
      hasExplicitTableGeometry &&
      hasRepeatingTableHeaders &&
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
      hasHeader: text.contains('word/header1.xml') && text.contains('<w:hdr'),
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
      hasLeadDecisionCallout:
          text.contains('Decision ask') &&
          text.contains('Review path') &&
          text.contains('CalloutLabel') &&
          text.contains('CCFBF1'),
      hasTableOfContents:
          text.contains('Table of Contents') && text.contains('TOC \\o'),
      hasExecutiveDecisionBrief: text.contains('Executive Decision Brief'),
      hasRecommendationSummary: text.contains('Recommendation Summary'),
      hasRiskRegister: text.contains('Risk &amp; Assumption Register'),
      hasNextStepActionPlan: text.contains('Next-Step Action Plan'),
      hasDocumentMap: text.contains('Document Map'),
      hasValidationChecklist: text.contains('Validation Checklist'),
      hasCustomerHandoffScorecard: text.contains('Customer Handoff Scorecard'),
      hasDecisionLog: text.contains('Decision Log'),
      hasAssumptionsAppendix: text.contains('Appendix A: Assumptions'),
      hasSourcesAppendix: text.contains('Appendix B: Sources / Evidence'),
      hasCircuitHeader: text.contains('CircuitCode report package'),
      hasCircuitFooter: text.contains('CircuitCode - Generated artifact'),
      hasEnterpriseStyles:
          text.contains('Aptos') &&
          text.contains('Heading1') &&
          text.contains('Caption') &&
          text.contains('CalloutLabel') &&
          text.contains('CBD5E1'),
      hasExplicitTableGeometry:
          text.contains('<w:tblW w:w="9120" w:type="dxa"/>') &&
          text.contains('<w:tblGrid>') &&
          text.contains('<w:tcW w:w='),
      hasRepeatingTableHeaders: text.contains('<w:tblHeader/>'),
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
