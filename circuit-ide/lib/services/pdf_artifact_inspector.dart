import 'dart:convert';

class PdfArtifactInspection {
  final bool hasPdfHeader;
  final bool hasCatalog;
  final bool hasXref;
  final bool hasTrailer;
  final int pageCount;
  final int objectCount;
  final bool hasLetterMediaBox;
  final bool hasCircuitHeader;
  final bool hasCircuitFooter;
  final bool hasPageNumberFooter;
  final bool hasAccentBar;
  final bool hasTableGrid;
  final bool hasOutlineCatalog;
  final bool hasOutlineTree;
  final bool hasReportOverviewBookmark;
  final bool hasLeadDecisionBookmark;
  final bool hasExecutiveDecisionBookmark;
  final bool hasValidationBookmark;
  final bool hasLeadDecisionCallout;
  final bool hasExecutiveDecisionBrief;
  final bool hasRecommendationSummary;
  final bool hasRiskRegister;
  final bool hasNextStepActionPlan;
  final bool hasStakeholderReadout;
  final bool hasEvidenceConfidenceMatrix;
  final bool hasApprovalGates;
  final bool hasValidationChecklist;
  final bool hasCustomerHandoffScorecard;
  final bool hasDecisionLog;
  final bool hasExplicitTableGeometry;
  final bool hasInfoKeywords;
  final String? title;

  const PdfArtifactInspection({
    required this.hasPdfHeader,
    required this.hasCatalog,
    required this.hasXref,
    required this.hasTrailer,
    required this.pageCount,
    required this.objectCount,
    required this.hasLetterMediaBox,
    required this.hasCircuitHeader,
    required this.hasCircuitFooter,
    required this.hasPageNumberFooter,
    required this.hasAccentBar,
    required this.hasTableGrid,
    required this.hasOutlineCatalog,
    required this.hasOutlineTree,
    required this.hasReportOverviewBookmark,
    required this.hasLeadDecisionBookmark,
    required this.hasExecutiveDecisionBookmark,
    required this.hasValidationBookmark,
    required this.hasLeadDecisionCallout,
    required this.hasExecutiveDecisionBrief,
    required this.hasRecommendationSummary,
    required this.hasRiskRegister,
    required this.hasNextStepActionPlan,
    required this.hasStakeholderReadout,
    required this.hasEvidenceConfidenceMatrix,
    required this.hasApprovalGates,
    required this.hasValidationChecklist,
    required this.hasCustomerHandoffScorecard,
    required this.hasDecisionLog,
    required this.hasExplicitTableGeometry,
    required this.hasInfoKeywords,
    required this.title,
  });

  bool get isStructurallyValid =>
      hasPdfHeader &&
      hasCatalog &&
      hasXref &&
      hasTrailer &&
      pageCount > 0 &&
      objectCount >= pageCount + 6;

  bool get hasExpectedReportChrome =>
      hasLetterMediaBox &&
      hasCircuitHeader &&
      hasCircuitFooter &&
      hasPageNumberFooter &&
      hasAccentBar &&
      hasOutlineCatalog &&
      hasOutlineTree &&
      hasReportOverviewBookmark &&
      hasLeadDecisionBookmark &&
      hasExecutiveDecisionBookmark &&
      hasValidationBookmark &&
      hasLeadDecisionCallout &&
      hasExecutiveDecisionBrief &&
      hasRecommendationSummary &&
      hasRiskRegister &&
      hasNextStepActionPlan &&
      hasStakeholderReadout &&
      hasEvidenceConfidenceMatrix &&
      hasApprovalGates &&
      hasValidationChecklist &&
      hasCustomerHandoffScorecard &&
      hasDecisionLog &&
      hasExplicitTableGeometry &&
      hasInfoKeywords;

  bool containsText(String text) =>
      _normalizedTitle(title).contains(_normalizedTitle(text));

  static String _normalizedTitle(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}

class PdfArtifactInspector {
  const PdfArtifactInspector();

  PdfArtifactInspection inspect(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    return PdfArtifactInspection(
      hasPdfHeader: text.startsWith('%PDF-'),
      hasCatalog: text.contains('/Type /Catalog'),
      hasXref: RegExp(r'\nxref\s*\n').hasMatch(text),
      hasTrailer: text.contains('trailer') && text.contains('startxref'),
      pageCount: RegExp(r'/Type /Page\b').allMatches(text).length,
      objectCount: RegExp(r'\n\d+ 0 obj\n').allMatches(text).length,
      hasLetterMediaBox: text.contains('/MediaBox [0 0 612 792]'),
      hasCircuitHeader: text.contains('CircuitCode generated artifact'),
      hasCircuitFooter: text.contains('CircuitCode - Generated artifact'),
      hasPageNumberFooter: RegExp(r'Page \d+ of \d+').hasMatch(text),
      hasAccentBar: text.contains('0 0 8 792 re f'),
      hasTableGrid: text.contains(' re S'),
      hasOutlineCatalog:
          text.contains('/Outlines') && text.contains('/PageMode /UseOutlines'),
      hasOutlineTree:
          text.contains('/Type /Outlines') &&
          RegExp(r'/Count\s+\d+').hasMatch(text) &&
          text.contains('/Dest ['),
      hasReportOverviewBookmark: _hasBookmark(text, 'Report Overview'),
      hasLeadDecisionBookmark: _hasBookmark(text, 'Lead Decision Callout'),
      hasExecutiveDecisionBookmark: _hasBookmark(
        text,
        'Executive Decision Brief',
      ),
      hasValidationBookmark: _hasBookmark(text, 'Validation Checklist'),
      hasLeadDecisionCallout:
          text.contains('Lead Decision Callout') &&
          text.contains('Decision ask') &&
          text.contains('Handoff status') &&
          text.contains('Review path'),
      hasExecutiveDecisionBrief: text.contains('Executive Decision Brief'),
      hasRecommendationSummary: text.contains('Recommendation Summary'),
      hasRiskRegister: text.contains('Risk & Assumption Register'),
      hasNextStepActionPlan: text.contains('Next-Step Action Plan'),
      hasStakeholderReadout: text.contains('Stakeholder Readout'),
      hasEvidenceConfidenceMatrix: text.contains('Evidence Confidence Matrix'),
      hasApprovalGates: text.contains('Approval Gates'),
      hasValidationChecklist: text.contains('Validation Checklist'),
      hasCustomerHandoffScorecard: text.contains('Customer Handoff Scorecard'),
      hasDecisionLog: text.contains('Decision Log'),
      hasExplicitTableGeometry:
          text.contains(' re f') &&
          text.contains(' re S') &&
          text.contains('0.78 0.81 0.84 RG'),
      hasInfoKeywords:
          text.contains('/Keywords') &&
          text.contains('enterprise') &&
          text.contains('CircuitCode'),
      title: _titleFromInfo(text),
    );
  }

  static String? _titleFromInfo(String text) {
    final match = RegExp(r'/Title \(((?:\\.|[^\\)])*)\)').firstMatch(text);
    final raw = match?.group(1);
    if (raw == null) return null;
    return raw
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll('\\\\', '\\');
  }

  static bool _hasBookmark(String text, String title) {
    final titleIndex = text.indexOf('/Title (${_pdfText(title)})');
    if (titleIndex == -1) return false;
    final nextTitleIndex = text.indexOf('/Title (', titleIndex + 1);
    final endIndex = nextTitleIndex == -1 ? text.length : nextTitleIndex;
    return text.substring(titleIndex, endIndex).contains('/Dest [');
  }

  static String _pdfText(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ');
  }
}
