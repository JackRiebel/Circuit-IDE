import 'dart:convert';
import 'dart:isolate';

import 'worker_cancellation.dart';

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
  final bool hasCustomerHandoffReadinessMatrix;
  final bool hasDecisionLog;
  final bool hasDecisionSignOff;
  final bool hasVisibleExternalHandoffManifest;
  final bool hasExplicitTableGeometry;
  final bool hasInfoKeywords;
  final bool hasCustomQualityInfo;
  final bool hasVisualVerificationManifest;
  final bool hasAccessibilityPolicy;
  final bool hasMarkedContent;
  final bool hasStructTreeRoot;
  final bool hasParentTree;
  final bool hasTaggedPageContent;
  final bool hasExternalHandoffManifest;
  final bool hasRenderSafeTextFrame;
  final bool hasPageCountConsistency;
  final bool hasResolvableBookmarkDestinations;
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
    required this.hasCustomerHandoffReadinessMatrix,
    required this.hasDecisionLog,
    required this.hasDecisionSignOff,
    required this.hasVisibleExternalHandoffManifest,
    required this.hasExplicitTableGeometry,
    required this.hasInfoKeywords,
    required this.hasCustomQualityInfo,
    required this.hasVisualVerificationManifest,
    this.hasAccessibilityPolicy = false,
    this.hasMarkedContent = false,
    this.hasStructTreeRoot = false,
    this.hasParentTree = false,
    this.hasTaggedPageContent = false,
    required this.hasExternalHandoffManifest,
    required this.hasRenderSafeTextFrame,
    required this.hasPageCountConsistency,
    required this.hasResolvableBookmarkDestinations,
    required this.title,
  });

  bool get isStructurallyValid =>
      hasPdfHeader &&
      hasCatalog &&
      hasXref &&
      hasTrailer &&
      hasPageCountConsistency &&
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
      hasCustomerHandoffReadinessMatrix &&
      hasDecisionLog &&
      hasDecisionSignOff &&
      hasVisibleExternalHandoffManifest &&
      hasExplicitTableGeometry &&
      hasInfoKeywords &&
      hasCustomQualityInfo &&
      hasVisualVerificationManifest &&
      hasAccessibilityPolicy &&
      hasTaggedPdfStructure &&
      hasExternalHandoffManifest &&
      hasRenderSafeTextFrame &&
      hasResolvableBookmarkDestinations;

  bool get hasTaggedPdfStructure =>
      hasMarkedContent &&
      hasStructTreeRoot &&
      hasParentTree &&
      hasTaggedPageContent;

  bool containsText(String text) =>
      _normalizedTitle(title).contains(_normalizedTitle(text));

  static String _normalizedTitle(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}

class PdfArtifactInspector {
  const PdfArtifactInspector();

  /// Parses PDF quality signals on a worker isolate before publication.
  ///
  /// The page count is included alongside serializable metadata because the
  /// writer uses it to build preview rows without reconstructing a model on
  /// the UI isolate.
  Future<Map<String, Object?>> inspectForArtifactInWorker(
    List<int> bytes, {
    WorkerCancellationToken? cancellationToken,
  }) {
    return CancellableWorker.run<Map<String, Object?>>(
      entryPoint: _pdfInspectionWorkerEntry,
      arguments: {'bytes': bytes},
      cancellationToken: cancellationToken,
      decodeResult: _pdfMetadataFromWorkerResult,
    );
  }

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
      hasCircuitHeader: text.contains('54 758 Td'),
      hasCircuitFooter: text.contains('54 34 Td'),
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
      hasCustomerHandoffReadinessMatrix:
          text.contains('Customer Handoff Readiness Matrix') &&
          text.contains('/CircuitCustomerHandoffReadiness'),
      hasDecisionLog: text.contains('Decision Log'),
      hasDecisionSignOff:
          text.contains('Decision Sign-Off') &&
          text.contains('Signature / Date') &&
          text.contains('Handoff approval'),
      hasVisibleExternalHandoffManifest:
          text.contains('External Handoff Manifest') &&
          text.contains('Handoff Control') &&
          text.contains('Readiness Detail') &&
          text.contains('Publishing gate') &&
          text.contains('Source package') &&
          text.contains('Assumption package'),
      hasExplicitTableGeometry:
          text.contains(' re f') &&
          text.contains(' re S') &&
          text.contains('0.78 0.81 0.84 RG'),
      hasInfoKeywords:
          text.contains('/Keywords') &&
          text.contains('enterprise') &&
          text.contains('CircuitCode'),
      hasCustomQualityInfo:
          text.contains('/CircuitReportQualityManifest') &&
          text.contains('/CircuitPublishingStatus') &&
          text.contains('/CircuitReviewPath') &&
          text.contains('/CircuitCustomerHandoffReadiness'),
      hasVisualVerificationManifest:
          text.contains('/CircuitVisualVerification') &&
          text.contains('Render-safe text frame') &&
          text.contains('Bookmark destinations resolve'),
      hasAccessibilityPolicy: text.contains('/CircuitAccessibilityPolicy'),
      hasMarkedContent: text.contains('/MarkInfo << /Marked true >>'),
      hasStructTreeRoot: text.contains('/Type /StructTreeRoot'),
      hasParentTree:
          text.contains('/ParentTree ') && text.contains('/ParentTreeNextKey '),
      hasTaggedPageContent:
          RegExp(r'/StructParents\s+\d+').allMatches(text).length ==
              RegExp(
                r'/P\s+<<\s*/MCID\s+0\s*>>\s+BDC',
              ).allMatches(text).length &&
          text.contains('/Type /StructElem'),
      hasExternalHandoffManifest:
          text.contains('/CircuitExternalHandoffManifest') &&
          text.contains('Review owner:') &&
          text.contains('Publishing gate:') &&
          text.contains('Source package:'),
      hasRenderSafeTextFrame: _hasRenderSafeTextFrame(text),
      hasPageCountConsistency: _hasPageCountConsistency(text),
      hasResolvableBookmarkDestinations: _hasResolvableBookmarkDestinations(
        text,
      ),
      title: _titleFromInfo(text),
    );
  }

  static Map<String, Object?> metadataFor(PdfArtifactInspection inspection) {
    final failedChecks = <String>[
      if (!inspection.hasPdfHeader) 'PDF header missing',
      if (!inspection.hasCatalog) 'Catalog missing',
      if (!inspection.hasXref) 'xref missing',
      if (!inspection.hasTrailer) 'Trailer/startxref missing',
      if (!inspection.hasPageCountConsistency) 'Page count mismatch',
      if (!inspection.hasResolvableBookmarkDestinations)
        'Bookmark destinations do not resolve',
      if (!inspection.hasTaggedPdfStructure)
        'Tagged PDF reading-order structure missing',
      if (!inspection.hasExpectedReportChrome)
        'Expected report chrome incomplete',
      if (!inspection.hasRenderSafeTextFrame)
        'Text frame is outside safe bounds',
    ];
    return {
      'pdfInspectionVersion': '1.0',
      'pdfInspectionStatus': inspection.isStructurallyValid
          ? (inspection.hasExpectedReportChrome
                ? 'Verified'
                : 'Structurally valid - review chrome')
          : 'Failed',
      'pdfStructuralValid': inspection.isStructurallyValid,
      'pdfExpectedReportChrome': inspection.hasExpectedReportChrome,
      'pdfInspectionFailedChecks': failedChecks,
      'pdfInspectionFailedCheckCount': failedChecks.length,
      'pdfParsedTitle': inspection.title,
      'pdfParsedPageCount': inspection.pageCount,
      'pdfObjectCount': inspection.objectCount,
      'pdfHasHeader': inspection.hasPdfHeader,
      'pdfHasCatalog': inspection.hasCatalog,
      'pdfHasXref': inspection.hasXref,
      'pdfHasTrailer': inspection.hasTrailer,
      'pdfHasOutlineTree': inspection.hasOutlineTree,
      'pdfHasReportOverviewBookmark': inspection.hasReportOverviewBookmark,
      'pdfHasLeadDecisionBookmark': inspection.hasLeadDecisionBookmark,
      'pdfHasExecutiveDecisionBookmark':
          inspection.hasExecutiveDecisionBookmark,
      'pdfHasValidationBookmark': inspection.hasValidationBookmark,
      'pdfHasResolvableBookmarkDestinations':
          inspection.hasResolvableBookmarkDestinations,
      'pdfHasPageCountConsistency': inspection.hasPageCountConsistency,
      'pdfHasRenderSafeTextFrame': inspection.hasRenderSafeTextFrame,
      'pdfHasCircuitHeader': inspection.hasCircuitHeader,
      'pdfHasCircuitFooter': inspection.hasCircuitFooter,
      'pdfHasPageNumberFooter': inspection.hasPageNumberFooter,
      'pdfHasLeadDecisionCallout': inspection.hasLeadDecisionCallout,
      'pdfHasExecutiveDecisionBrief': inspection.hasExecutiveDecisionBrief,
      'pdfHasRecommendationSummary': inspection.hasRecommendationSummary,
      'pdfHasRiskRegister': inspection.hasRiskRegister,
      'pdfHasNextStepActionPlan': inspection.hasNextStepActionPlan,
      'pdfHasStakeholderReadout': inspection.hasStakeholderReadout,
      'pdfHasEvidenceConfidenceMatrix': inspection.hasEvidenceConfidenceMatrix,
      'pdfHasApprovalGates': inspection.hasApprovalGates,
      'pdfHasValidationChecklist': inspection.hasValidationChecklist,
      'pdfHasCustomerHandoffScorecard': inspection.hasCustomerHandoffScorecard,
      'pdfHasCustomerHandoffReadinessMatrix':
          inspection.hasCustomerHandoffReadinessMatrix,
      'pdfHasDecisionLog': inspection.hasDecisionLog,
      'pdfHasDecisionSignOff': inspection.hasDecisionSignOff,
      'pdfHasExternalHandoffManifest':
          inspection.hasVisibleExternalHandoffManifest &&
          inspection.hasExternalHandoffManifest,
      'pdfHasCustomQualityInfo': inspection.hasCustomQualityInfo,
      'pdfHasVisualVerificationManifest':
          inspection.hasVisualVerificationManifest,
      'pdfHasAccessibilityPolicy': inspection.hasAccessibilityPolicy,
      'pdfHasMarkedContent': inspection.hasMarkedContent,
      'pdfHasStructTreeRoot': inspection.hasStructTreeRoot,
      'pdfHasParentTree': inspection.hasParentTree,
      'pdfHasTaggedPageContent': inspection.hasTaggedPageContent,
      'pdfHasTaggedStructure': inspection.hasTaggedPdfStructure,
      'pdfHasExplicitTableGeometry': inspection.hasExplicitTableGeometry,
    };
  }

  static bool _hasPageCountConsistency(String text) {
    final declared = RegExp(
      r'/Type /Pages /Kids \[[^\]]*\] /Count (\d+)',
    ).firstMatch(text);
    final declaredCount = int.tryParse(declared?.group(1) ?? '');
    if (declaredCount == null) return false;
    final actualCount = RegExp(r'/Type /Page\b').allMatches(text).length;
    return declaredCount == actualCount && actualCount > 0;
  }

  static bool _hasResolvableBookmarkDestinations(String text) {
    final pageIds = RegExp(r'\n(\d+) 0 obj\n<< /Type /Page\b')
        .allMatches(text)
        .map((match) => match.group(1))
        .whereType<String>()
        .toSet();
    final destinationIds = RegExp(r'/Dest \[(\d+) 0 R')
        .allMatches(text)
        .map((match) => match.group(1))
        .whereType<String>()
        .toList(growable: false);
    return pageIds.isNotEmpty &&
        destinationIds.isNotEmpty &&
        destinationIds.every(pageIds.contains);
  }

  static bool _hasRenderSafeTextFrame(String text) {
    final textPositions = RegExp(
      r'(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+Td\s+\(',
    ).allMatches(text);
    var found = false;
    for (final match in textPositions) {
      found = true;
      final x = double.tryParse(match.group(1) ?? '');
      final y = double.tryParse(match.group(2) ?? '');
      if (x == null || y == null) return false;
      if (x < 40 || x > 560 || y < 28 || y > 770) return false;
    }
    return found;
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

void _pdfInspectionWorkerEntry(Map<String, Object?> arguments) {
  final replyPort = arguments['replyPort'];
  if (replyPort is! SendPort) return;
  try {
    final bytes = arguments['bytes'];
    if (bytes is! List<int>) {
      throw StateError('Missing PDF bytes for inspection.');
    }
    final inspection = const PdfArtifactInspector().inspect(bytes);
    replyPort.send({
      'result': <String, Object?>{
        'pageCount': inspection.pageCount,
        'metadata': PdfArtifactInspector.metadataFor(inspection),
      },
    });
  } catch (error) {
    replyPort.send({'error': error.toString()});
  }
}

Map<String, Object?> _pdfMetadataFromWorkerResult(Object? result) {
  if (result is! Map) {
    throw StateError('PDF inspector returned malformed metadata.');
  }
  return Map<String, Object?>.from(result);
}
