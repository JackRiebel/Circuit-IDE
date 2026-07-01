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
  final bool hasExecutiveDecisionBrief;
  final bool hasRecommendationSummary;
  final bool hasRiskRegister;
  final bool hasNextStepActionPlan;
  final bool hasValidationChecklist;
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
    required this.hasExecutiveDecisionBrief,
    required this.hasRecommendationSummary,
    required this.hasRiskRegister,
    required this.hasNextStepActionPlan,
    required this.hasValidationChecklist,
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
      hasExecutiveDecisionBrief &&
      hasRecommendationSummary &&
      hasRiskRegister &&
      hasNextStepActionPlan &&
      hasValidationChecklist &&
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
      hasExecutiveDecisionBrief: text.contains('Executive Decision Brief'),
      hasRecommendationSummary: text.contains('Recommendation Summary'),
      hasRiskRegister: text.contains('Risk & Assumption Register'),
      hasNextStepActionPlan: text.contains('Next-Step Action Plan'),
      hasValidationChecklist: text.contains('Validation Checklist'),
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
}
