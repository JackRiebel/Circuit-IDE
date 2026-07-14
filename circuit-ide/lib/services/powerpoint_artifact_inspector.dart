import 'dart:convert';
import 'dart:isolate';

import 'worker_cancellation.dart';
import 'office_package_relationship_inspector.dart';
import 'zip_package_integrity.dart';

class PowerPointArtifactInspection {
  final bool hasZipHeader;
  final bool hasValidZipContainer;
  final bool hasResolvablePackageRelationships;
  final bool hasContentTypes;
  final bool hasPresentation;
  final bool hasTheme;
  final bool hasSlideMaster;
  final bool hasCoreProperties;
  final bool hasExtendedProperties;
  final bool hasCustomProperties;
  final bool hasNarrativeManifest;
  final bool hasExternalHandoffManifest;
  final int slideCount;
  final int declaredSlideCount;
  final String? title;
  final List<String> slideTypes;
  final bool hasReadinessStatusStrip;
  final bool hasCircuitFooter;
  final bool hasAgenda;
  final bool hasAgendaLayout;
  final bool hasDeliveryBrief;
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
  final bool hasPublishingGate;
  final bool hasPublishingGateLayout;
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
    required this.hasValidZipContainer,
    required this.hasResolvablePackageRelationships,
    required this.hasContentTypes,
    required this.hasPresentation,
    required this.hasTheme,
    required this.hasSlideMaster,
    required this.hasCoreProperties,
    required this.hasExtendedProperties,
    required this.hasCustomProperties,
    required this.hasNarrativeManifest,
    required this.hasExternalHandoffManifest,
    required this.slideCount,
    required this.declaredSlideCount,
    required this.title,
    required this.slideTypes,
    required this.hasReadinessStatusStrip,
    required this.hasCircuitFooter,
    required this.hasAgenda,
    required this.hasAgendaLayout,
    required this.hasDeliveryBrief,
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
    required this.hasPublishingGate,
    required this.hasPublishingGateLayout,
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
      hasValidZipContainer &&
      hasResolvablePackageRelationships &&
      hasContentTypes &&
      hasPresentation &&
      hasTheme &&
      hasSlideMaster &&
      hasCoreProperties &&
      hasExtendedProperties &&
      hasCustomProperties &&
      hasNarrativeManifest &&
      hasExternalHandoffManifest &&
      slideCount > 0 &&
      declaredSlideCount == slideCount;

  bool get hasExpectedDeckStructure =>
      isStructurallyValid &&
      hasAgenda &&
      hasAgendaLayout &&
      hasDeliveryBrief &&
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
      hasPublishingGate &&
      hasPublishingGateLayout &&
      hasClosingDecisionAsk &&
      hasTableSlide &&
      hasAppendix &&
      hasSourcesSlide &&
      hasAssumptionsSourcesSlide &&
      hasReadinessStatusStrip &&
      hasCircuitFooter &&
      hasEnterpriseStyling &&
      hasSpeakerNotes &&
      hasSlideNumbers;

  Map<String, Object?> toMetadata({int? expectedSlideCount}) {
    final checks = <String, bool>{
      'ZIP package header': hasZipHeader,
      'ZIP central-directory integrity': hasValidZipContainer,
      'OOXML relationship targets': hasResolvablePackageRelationships,
      '[Content_Types].xml': hasContentTypes,
      'ppt/presentation.xml': hasPresentation,
      'ppt/theme/theme1.xml': hasTheme,
      'slide master': hasSlideMaster,
      'core properties': hasCoreProperties,
      'extended properties': hasExtendedProperties,
      'custom properties': hasCustomProperties,
      'narrative manifest': hasNarrativeManifest,
      'external handoff manifest': hasExternalHandoffManifest,
      'slide files': slideCount > 0,
      'declared slide count': declaredSlideCount == slideCount,
      'speaker notes': hasSpeakerNotes,
      'slide numbers': hasSlideNumbers,
      'enterprise styling': hasEnterpriseStyling,
      'readiness status strip': hasReadinessStatusStrip,
      'expected deck structure': hasExpectedDeckStructure,
      if (expectedSlideCount != null)
        'expected slide count': expectedSlideCount == slideCount,
    };
    final failedChecks = checks.entries
        .where((entry) => !entry.value)
        .map((entry) => entry.key)
        .toList(growable: false);
    return {
      'pptxInspectionVersion': '1.0',
      'pptxInspectionStatus': failedChecks.isEmpty
          ? 'Verified'
          : 'Needs review',
      'pptxStructuralValid': isStructurallyValid,
      'pptxExpectedDeckStructure': hasExpectedDeckStructure,
      'pptxInspectionFailedChecks': failedChecks,
      'pptxInspectionFailedCheckCount': failedChecks.length,
      'pptxParsedSlideCount': declaredSlideCount,
      'pptxSlideFileCount': slideCount,
      'pptxNotesFileCount': notesSlideCount,
      'pptxHasContentTypes': hasContentTypes,
      'pptxZipContainerValid': hasValidZipContainer,
      'pptxRelationshipTargetsValid': hasResolvablePackageRelationships,
      'pptxHasPresentationXml': hasPresentation,
      'pptxHasPresentationRels': hasPresentation,
      'pptxHasTheme': hasTheme,
      'pptxHasCoreProps': hasCoreProperties,
      'pptxHasAppProps': hasExtendedProperties,
      'pptxHasCustomProps': hasCustomProperties,
      'pptxHasSpeakerNotes': hasSpeakerNotes,
      'pptxHas16x9Layout': hasPresentation,
      'pptxHasAgendaSlide': hasAgenda || hasAgendaLayout,
      'pptxHasRecommendationSlide':
          hasExecutiveRecommendation || hasRecommendationCards,
      'pptxHasSourcesSlide': hasSourcesSlide || hasAssumptionsSourcesSlide,
      'pptxHasTableSlide': hasTableSlide,
      'pptxHasSectionDivider': hasSectionDivider || hasSectionDividerLayout,
      'pptxHasDecisionMatrix': hasDecisionMatrix,
      'pptxHasDeliveryBrief': hasDeliveryBrief,
      'pptxHasRoadmapTimeline': hasRoadmapTimeline,
      'pptxHasPublishingGate': hasPublishingGate,
      'pptxHasReadinessStatusStrip': hasReadinessStatusStrip,
      'pptxHasEnterpriseStyling': hasEnterpriseStyling,
      'pptxUsesLightTheme': usesLightTheme,
      'pptxUsesDarkTheme': usesDarkTheme,
      'pptxSlideTypes': slideTypes,
      'pptxExpectedDeckChrome': [
        'Content types',
        'Presentation XML',
        'Theme',
        'Core/app/custom properties',
        'Slide XML',
        'Speaker notes',
        'Readiness strip',
        'Enterprise styling',
      ],
    };
  }
}

class PowerPointArtifactInspector {
  const PowerPointArtifactInspector();

  /// Parses an Office package without holding up the UI isolate.
  ///
  /// Artifact generation already awaits this validation before it publishes a
  /// file. Returning metadata keeps the isolate boundary transferable while
  /// preserving the synchronous [inspect] API for callers that need the full
  /// inspection model.
  Future<Map<String, Object?>> inspectMetadataInWorker(
    List<int> bytes, {
    int? expectedSlideCount,
    WorkerCancellationToken? cancellationToken,
  }) {
    return CancellableWorker.run<Map<String, Object?>>(
      entryPoint: _powerPointInspectionWorkerEntry,
      arguments: {'bytes': bytes, 'expectedSlideCount': expectedSlideCount},
      cancellationToken: cancellationToken,
      decodeResult: _powerPointMetadataFromWorkerResult,
    );
  }

  PowerPointArtifactInspection inspect(List<int> bytes) {
    final zipInspection = const ZipPackageInspector().inspect(bytes);
    final relationshipInspection = const OfficePackageRelationshipInspector()
        .inspect(zipInspection);
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
      hasZipHeader: zipInspection.hasZipHeader,
      hasValidZipContainer: zipInspection.isStructurallyValid,
      hasResolvablePackageRelationships:
          relationshipInspection.hasResolvableInternalTargets,
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
      hasCustomProperties:
          text.contains('docProps/custom.xml') &&
          text.contains('CircuitDeckQualityManifest'),
      hasNarrativeManifest:
          text.contains('CircuitCommunicationJob') &&
          text.contains('CircuitNarrativeArc') &&
          text.contains('CircuitDecisionAsk') &&
          text.contains('CircuitVisibleCopyPolicy'),
      hasExternalHandoffManifest:
          text.contains('CircuitExternalHandoffManifest') &&
          text.contains('Review owner:') &&
          text.contains('Evidence status:') &&
          text.contains('Publishing gate:') &&
          text.contains('Decision ask:'),
      slideCount: slideFiles.length,
      declaredSlideCount: _declaredSlideCount(text),
      title: _firstElementText(text, 'dc:title'),
      slideTypes: slideTypes,
      hasReadinessStatusStrip:
          text.contains('Circuit readiness strip') &&
          text.contains('Circuit readiness pill') &&
          text.contains('Circuit readiness label') &&
          text.contains('Readiness:') &&
          text.contains('Evidence:') &&
          text.contains('Gate:'),
      hasCircuitFooter: text.contains('CircuitCode - Generated artifact'),
      hasAgenda: text.contains('Agenda'),
      hasAgendaLayout:
          text.contains('Agenda step') && text.contains('Agenda number rail'),
      hasDeliveryBrief:
          text.contains('Executive Delivery Brief') ||
          slideTypes.contains('Delivery Brief'),
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
          text.contains('Enterprise brand pill label'),
      hasImplementationRoadmap:
          text.contains('Implementation Roadmap') ||
          slideTypes.contains('Roadmap'),
      hasRoadmapTimeline:
          text.contains('Roadmap timeline') &&
          text.contains('Roadmap phase marker'),
      hasPublishingGate:
          text.contains('Review &amp; Publishing Gate') ||
          slideTypes.contains('Publishing Gate'),
      hasPublishingGateLayout:
          text.contains('Customer-ready checkpoint') &&
          text.contains('CircuitPublishingGate') &&
          text.contains('Visual QA') &&
          text.contains('External handoff'),
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

void _powerPointInspectionWorkerEntry(Map<String, Object?> arguments) {
  final replyPort = arguments['replyPort'];
  if (replyPort is! SendPort) return;
  try {
    final bytes = arguments['bytes'];
    if (bytes is! List<int>) {
      throw StateError('Missing PowerPoint bytes for inspection.');
    }
    replyPort.send({
      'result': const PowerPointArtifactInspector()
          .inspect(bytes)
          .toMetadata(
            expectedSlideCount: arguments['expectedSlideCount'] as int?,
          ),
    });
  } catch (error) {
    replyPort.send({'error': error.toString()});
  }
}

Map<String, Object?> _powerPointMetadataFromWorkerResult(Object? result) {
  if (result is! Map) {
    throw StateError('PowerPoint inspector returned malformed metadata.');
  }
  return Map<String, Object?>.from(result);
}
