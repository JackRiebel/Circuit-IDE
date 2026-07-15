import '../../models/generated_artifact.dart';
import 'studio_artifact_metadata.dart';

/// Projects presentation and document metadata into Artifact drawer rows.
List<(String, String)> studioArtifactDocumentDetailRows(
  GeneratedArtifact artifact,
) {
  return [
    if (artifact.kind == GeneratedArtifactKind.powerPoint) ...[
      if (studioArtifactMetadataString(artifact, 'deckType').isNotEmpty)
        ('Deck', studioArtifactMetadataString(artifact, 'deckType')),
      if (studioArtifactMetadataString(artifact, 'handoffStatus').isNotEmpty)
        ('Handoff', studioArtifactMetadataString(artifact, 'handoffStatus')),
      if (studioArtifactMetadataInt(artifact, 'customerHandoffGateCount') > 0)
        (
          'Handoff gates',
          '${studioArtifactMetadataInt(artifact, 'customerHandoffGateReadyCount')}/${studioArtifactMetadataInt(artifact, 'customerHandoffGateCount')} ready',
        ),
      if (studioArtifactMetadataString(artifact, 'theme').isNotEmpty)
        ('Theme', studioArtifactMetadataString(artifact, 'theme')),
      if (studioArtifactMetadataString(artifact, 'audience').isNotEmpty)
        ('Audience', studioArtifactMetadataString(artifact, 'audience')),
      if (studioArtifactMetadataString(artifact, 'deckPurpose').isNotEmpty)
        ('Purpose', studioArtifactMetadataString(artifact, 'deckPurpose')),
      if (studioArtifactMetadataString(
        artifact,
        'pptxInspectionStatus',
      ).isNotEmpty)
        (
          'PPTX inspection',
          studioArtifactMetadataString(artifact, 'pptxInspectionStatus'),
        ),
      if (studioArtifactMetadataInt(artifact, 'pptxSlideFileCount') > 0)
        (
          'Slide files',
          '${studioArtifactMetadataInt(artifact, 'pptxSlideFileCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'pptxNotesFileCount') > 0)
        (
          'Speaker notes',
          '${studioArtifactMetadataInt(artifact, 'pptxNotesFileCount')}',
        ),
      if (studioArtifactMetadataBool(artifact, 'pptxHas16x9Layout'))
        ('Layout', '16:9'),
      if (studioArtifactMetadataStringList(
        artifact,
        'pptxInspectionFailedChecks',
      ).isNotEmpty)
        (
          'PPTX checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'pptxInspectionFailedChecks',
            ),
          ),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'deliveryReadinessLevel',
      ).isNotEmpty)
        (
          'Delivery readiness',
          studioArtifactMetadataString(artifact, 'deliveryReadinessLevel'),
        ),
      if (studioArtifactMetadataInt(artifact, 'deliveryReadinessScore') > 0)
        (
          'Delivery score',
          '${studioArtifactMetadataInt(artifact, 'deliveryReadinessScore')}/100',
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'deckStatusStrip',
      ).isNotEmpty)
        (
          'Deck status',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'deckStatusStrip'),
          ),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'deckReviewPriority',
      ).isNotEmpty)
        (
          'Review priority',
          studioArtifactMetadataString(artifact, 'deckReviewPriority'),
        ),
      if (studioArtifactMetadataString(artifact, 'decisionAsk').isNotEmpty)
        ('Ask', studioArtifactMetadataString(artifact, 'decisionAsk')),
      if (studioArtifactMetadataString(artifact, 'narrativeArc').isNotEmpty)
        ('Narrative', studioArtifactMetadataString(artifact, 'narrativeArc')),
      if (studioArtifactMetadataStringList(artifact, 'agendaItems').isNotEmpty)
        (
          'Agenda',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'agendaItems'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'slideFamilies',
      ).isNotEmpty)
        (
          'Slide families',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'slideFamilies'),
          ),
        ),
      if (studioArtifactMetadataStringList(artifact, 'slidePreview').isNotEmpty)
        (
          'Slide preview',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'slidePreview'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'readinessSignals',
      ).isNotEmpty)
        (
          'Readiness',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'readinessSignals'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'deliveryReadinessDrivers',
      ).isNotEmpty)
        (
          'Readiness drivers',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'deliveryReadinessDrivers',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'audienceHandoffNotes',
      ).isNotEmpty)
        (
          'Audience handoff',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'audienceHandoffNotes'),
          ),
        ),
      if (studioArtifactMetadataString(artifact, 'tableCoverage').isNotEmpty)
        ('Tables', studioArtifactMetadataString(artifact, 'tableCoverage')),
      if (studioArtifactMetadataString(artifact, 'sourceCoverage').isNotEmpty)
        ('Sources', studioArtifactMetadataString(artifact, 'sourceCoverage')),
      if (studioArtifactMetadataString(
        artifact,
        'evidenceConfidence',
      ).isNotEmpty)
        (
          'Evidence confidence',
          studioArtifactMetadataString(artifact, 'evidenceConfidence'),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'deckReviewChecklist',
      ).isNotEmpty)
        (
          'Deck review',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'deckReviewChecklist'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'deckVisualVerificationChecklist',
      ).isNotEmpty)
        (
          'Visual checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'deckVisualVerificationChecklist',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'deckEvidencePolicy',
      ).isNotEmpty)
        (
          'Evidence policy',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'deckEvidencePolicy'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'deckPublishingMetadata',
      ).isNotEmpty)
        (
          'Publishing',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'deckPublishingMetadata',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'deckHandoffActions',
      ).isNotEmpty)
        (
          'Handoff actions',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'deckHandoffActions'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'presentationRiskFlags',
      ).isNotEmpty)
        (
          'Presentation risks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'presentationRiskFlags'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'validationGaps',
      ).isNotEmpty)
        (
          'Validation gaps',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'validationGaps'),
          ),
        ),
      if (studioArtifactMetadataInt(artifact, 'sectionCount') > 0)
        ('Sections', '${studioArtifactMetadataInt(artifact, 'sectionCount')}'),
      if (studioArtifactMetadataInt(artifact, 'sectionDividerCount') > 0)
        (
          'Dividers',
          '${studioArtifactMetadataInt(artifact, 'sectionDividerCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'deliveryBriefSlideCount') > 0)
        (
          'Delivery brief',
          '${studioArtifactMetadataInt(artifact, 'deliveryBriefSlideCount')} slide',
        ),
      if (studioArtifactMetadataInt(artifact, 'tableCount') > 0)
        ('Tables', '${studioArtifactMetadataInt(artifact, 'tableCount')}'),
      if (studioArtifactMetadataInt(artifact, 'tableSlideCount') > 0)
        (
          'Table slides',
          '${studioArtifactMetadataInt(artifact, 'tableSlideCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'recommendationSlideCount') > 0)
        (
          'Recommendations',
          '${studioArtifactMetadataInt(artifact, 'recommendationSlideCount')} slides',
        ),
      if (studioArtifactMetadataInt(artifact, 'assumptionCount') > 0)
        (
          'Assumptions',
          '${studioArtifactMetadataInt(artifact, 'assumptionCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'citationCount') > 0)
        ('Sources', '${studioArtifactMetadataInt(artifact, 'citationCount')}'),
      if (studioArtifactMetadataBool(artifact, 'hasCustomerReadyStructure'))
        ('Structure', 'Customer-ready deck flow'),
      if (studioArtifactMetadataBool(artifact, 'hasCustomerReadyDeck'))
        ('Package', 'Stakeholder-review deck'),
      if (studioArtifactMetadataBool(artifact, 'hasSpeakerNotes'))
        ('Notes', 'Speaker notes included'),
      if (studioArtifactMetadataInt(artifact, 'speakerNoteCount') > 0)
        (
          'Speaker notes',
          '${studioArtifactMetadataInt(artifact, 'speakerNoteCount')}',
        ),
    ],
    if (artifact.kind == GeneratedArtifactKind.docx ||
        artifact.kind == GeneratedArtifactKind.pdf) ...[
      if (studioArtifactMetadataInt(artifact, 'pageCount') > 0 &&
          artifact.sheetCount == 0)
        ('Pages', '${studioArtifactMetadataInt(artifact, 'pageCount')}'),
      if (studioArtifactMetadataString(artifact, 'reportType').isNotEmpty)
        ('Type', studioArtifactMetadataString(artifact, 'reportType')),
      if (studioArtifactMetadataString(artifact, 'audience').isNotEmpty)
        ('Audience', studioArtifactMetadataString(artifact, 'audience')),
      if (studioArtifactMetadataString(artifact, 'reportPurpose').isNotEmpty)
        ('Purpose', studioArtifactMetadataString(artifact, 'reportPurpose')),
      if (studioArtifactMetadataString(artifact, 'handoffStatus').isNotEmpty)
        ('Handoff', studioArtifactMetadataString(artifact, 'handoffStatus')),
      if (studioArtifactMetadataString(artifact, 'decisionOwner').isNotEmpty)
        ('Owner', studioArtifactMetadataString(artifact, 'decisionOwner')),
      if (studioArtifactMetadataString(artifact, 'decisionAsk').isNotEmpty)
        ('Ask', studioArtifactMetadataString(artifact, 'decisionAsk')),
      if (studioArtifactMetadataString(artifact, 'reviewPath').isNotEmpty)
        ('Review path', studioArtifactMetadataString(artifact, 'reviewPath')),
      if (studioArtifactMetadataString(artifact, 'artifactTemplate') ==
              'business_use_case_brief' &&
          studioArtifactMetadataString(
            artifact,
            'businessCaseExecutiveReadiness',
          ).isNotEmpty)
        (
          'Business readiness',
          studioArtifactMetadataString(
            artifact,
            'businessCaseExecutiveReadiness',
          ),
        ),
      if (studioArtifactMetadataString(artifact, 'artifactTemplate') ==
              'business_use_case_brief' &&
          studioArtifactMetadataInt(artifact, 'businessCaseHandoffGateCount') >
              0)
        (
          'Handoff gates',
          '${studioArtifactMetadataInt(artifact, 'businessCaseHandoffReadyCount')}/${studioArtifactMetadataInt(artifact, 'businessCaseHandoffGateCount')} ready',
        ),
      if (artifact.kind == GeneratedArtifactKind.docx &&
          studioArtifactMetadataString(
            artifact,
            'docxInspectionStatus',
          ).isNotEmpty)
        (
          'DOCX inspection',
          studioArtifactMetadataString(artifact, 'docxInspectionStatus'),
        ),
      if (artifact.kind == GeneratedArtifactKind.docx &&
          studioArtifactMetadataBool(artifact, 'docxStructuralValid'))
        ('DOCX package', 'Structurally valid'),
      if (artifact.kind == GeneratedArtifactKind.docx &&
          studioArtifactMetadataBool(artifact, 'docxExpectedReportStructure'))
        ('DOCX structure', 'Customer-ready report'),
      if (artifact.kind == GeneratedArtifactKind.docx &&
          studioArtifactMetadataInt(artifact, 'docxDeclaredWordCount') > 0)
        (
          'Declared words',
          '${studioArtifactMetadataInt(artifact, 'docxDeclaredWordCount')}',
        ),
      if (artifact.kind == GeneratedArtifactKind.docx &&
          studioArtifactMetadataInt(artifact, 'docxParagraphCount') > 0)
        (
          'Paragraphs',
          '${studioArtifactMetadataInt(artifact, 'docxParagraphCount')}',
        ),
      if (artifact.kind == GeneratedArtifactKind.docx &&
          studioArtifactMetadataBool(artifact, 'docxHasTableOfContents'))
        ('Table of contents', 'Included'),
      if (artifact.kind == GeneratedArtifactKind.docx &&
          studioArtifactMetadataBool(artifact, 'docxHasExplicitTableGeometry'))
        ('Table geometry', 'Fixed layout'),
      if (artifact.kind == GeneratedArtifactKind.docx &&
          studioArtifactMetadataBool(artifact, 'docxHasRepeatingTableHeaders'))
        ('Table headers', 'Repeating'),
      if (artifact.kind == GeneratedArtifactKind.docx &&
          studioArtifactMetadataBool(artifact, 'docxHasAccessibilityManifest'))
        ('Accessibility', 'Manifest included'),
      if (artifact.kind == GeneratedArtifactKind.docx &&
          studioArtifactMetadataStringList(
            artifact,
            'docxInspectionFailedChecks',
          ).isNotEmpty)
        (
          'DOCX checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'docxInspectionFailedChecks',
            ),
          ),
        ),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataString(
            artifact,
            'pdfInspectionStatus',
          ).isNotEmpty)
        (
          'PDF inspection',
          studioArtifactMetadataString(artifact, 'pdfInspectionStatus'),
        ),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataBool(artifact, 'pdfStructuralValid'))
        ('PDF package', 'Structurally valid'),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataBool(artifact, 'pdfExpectedReportChrome'))
        ('PDF chrome', 'Customer-ready report'),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataInt(artifact, 'pdfParsedPageCount') > 0)
        (
          'Parsed pages',
          '${studioArtifactMetadataInt(artifact, 'pdfParsedPageCount')}',
        ),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataInt(artifact, 'pdfObjectCount') > 0)
        (
          'PDF objects',
          '${studioArtifactMetadataInt(artifact, 'pdfObjectCount')}',
        ),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataBool(artifact, 'pdfHasOutlineTree'))
        ('Bookmarks', 'Outline tree'),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataBool(
            artifact,
            'pdfHasResolvableBookmarkDestinations',
          ))
        ('Bookmark links', 'Resolvable'),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataBool(artifact, 'pdfHasRenderSafeTextFrame'))
        ('Text frame', 'Render-safe'),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataBool(artifact, 'pdfHasPageCountConsistency'))
        ('Page count', 'Consistent'),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataBool(
            artifact,
            'pdfHasVisualVerificationManifest',
          ))
        ('Visual manifest', 'Included'),
      if (artifact.kind == GeneratedArtifactKind.pdf &&
          studioArtifactMetadataStringList(
            artifact,
            'pdfInspectionFailedChecks',
          ).isNotEmpty)
        (
          'PDF checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'pdfInspectionFailedChecks',
            ),
          ),
        ),
      if (studioArtifactMetadataBool(artifact, 'hasReportQualityManifest'))
        (
          'Quality',
          studioArtifactMetadataString(
                artifact,
                'qualityManifestVersion',
              ).isEmpty
              ? 'Report quality manifest'
              : 'Manifest v${studioArtifactMetadataString(artifact, 'qualityManifestVersion')}',
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'publishingMetadata',
      ).isNotEmpty)
        (
          'Publishing',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'publishingMetadata'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'accessibilitySignals',
      ).isNotEmpty)
        (
          'Accessibility',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'accessibilitySignals'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'visualVerificationChecklist',
      ).isNotEmpty)
        (
          'Visual checks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(
              artifact,
              'visualVerificationChecklist',
            ),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'documentParts',
      ).isNotEmpty)
        (
          'Parts',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'documentParts'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'readinessSignals',
      ).isNotEmpty)
        (
          'Readiness',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'readinessSignals'),
          ),
        ),
      if (studioArtifactMetadataString(artifact, 'tableCoverage').isNotEmpty)
        ('Tables', studioArtifactMetadataString(artifact, 'tableCoverage')),
      if (studioArtifactMetadataString(artifact, 'evidenceCoverage').isNotEmpty)
        (
          'Evidence',
          studioArtifactMetadataString(artifact, 'evidenceCoverage'),
        ),
      if (studioArtifactMetadataString(
        artifact,
        'evidenceConfidence',
      ).isNotEmpty)
        (
          'Evidence confidence',
          studioArtifactMetadataString(artifact, 'evidenceConfidence'),
        ),
      if (studioArtifactMetadataString(artifact, 'artifactTemplate') ==
              'evidence_pack' &&
          studioArtifactMetadataInt(
                artifact,
                'evidenceCustomerHandoffGateCount',
              ) >
              0)
        (
          'Handoff gates',
          '${studioArtifactMetadataInt(artifact, 'evidenceCustomerHandoffReadyCount')}/${studioArtifactMetadataInt(artifact, 'evidenceCustomerHandoffGateCount')} ready',
        ),
      if (studioArtifactMetadataString(
        artifact,
        'visualEvidenceReliability',
      ).isNotEmpty)
        (
          'Visual evidence',
          studioArtifactVisualEvidenceReliabilityLabel(
            studioArtifactMetadataString(artifact, 'visualEvidenceReliability'),
          ),
        ),
      if (studioArtifactMetadataInt(artifact, 'visualEvidenceCount') > 0)
        (
          'Visual items',
          '${studioArtifactMetadataInt(artifact, 'visualEvidenceCount')} captured',
        ),
      if (studioArtifactMetadataInt(artifact, 'visualEvidenceAttachmentCount') >
          0)
        (
          'Visual intake',
          '${studioArtifactMetadataInt(artifact, 'visualEvidenceAttachmentCount')} item${studioArtifactMetadataInt(artifact, 'visualEvidenceAttachmentCount') == 1 ? '' : 's'} registered',
        ),
      if (studioArtifactMetadataString(
        artifact,
        'visualEvidenceFormatCoverage',
      ).isNotEmpty)
        (
          'Image formats',
          studioArtifactMetadataString(
            artifact,
            'visualEvidenceFormatCoverage',
          ),
        ),
      if (studioArtifactMetadataInt(artifact, 'visualEvidenceDimensionCount') >
          0)
        (
          'Dimensions',
          '${studioArtifactMetadataInt(artifact, 'visualEvidenceDimensionCount')} detected',
        ),
      if (studioArtifactMetadataInt(artifact, 'visualEvidenceSidecarCount') > 0)
        (
          'OCR/sidecar',
          '${studioArtifactMetadataInt(artifact, 'visualEvidenceSidecarCount')} attached',
        ),
      if (studioArtifactMetadataInt(
            artifact,
            'visualEvidenceMetadataOnlyCount',
          ) >
          0)
        (
          'Metadata-only',
          '${studioArtifactMetadataInt(artifact, 'visualEvidenceMetadataOnlyCount')} need validation',
        ),
      if (studioArtifactMetadataBool(
        artifact,
        'visualEvidenceRequiresVisionReview',
      ))
        ('Vision review', 'Required before pixel-level claims'),
      if (studioArtifactMetadataString(
        artifact,
        'visualEvidenceReviewAction',
      ).isNotEmpty)
        (
          'Visual next step',
          studioArtifactMetadataString(artifact, 'visualEvidenceReviewAction'),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'reportEvidencePolicy',
      ).isNotEmpty)
        (
          'Evidence policy',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'reportEvidencePolicy'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'reportReviewChecklist',
      ).isNotEmpty)
        (
          'Report review',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'reportReviewChecklist'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'reportHandoffActions',
      ).isNotEmpty)
        (
          'Handoff actions',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'reportHandoffActions'),
          ),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'reportRiskFlags',
      ).isNotEmpty)
        (
          'Report risks',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'reportRiskFlags'),
          ),
        ),
      if (studioArtifactMetadataString(artifact, 'appendixCoverage').isNotEmpty)
        (
          'Appendices',
          studioArtifactMetadataString(artifact, 'appendixCoverage'),
        ),
      if (studioArtifactMetadataStringList(
        artifact,
        'validationGaps',
      ).isNotEmpty)
        (
          'Validation gaps',
          studioArtifactCompactSignalList(
            studioArtifactMetadataStringList(artifact, 'validationGaps'),
          ),
        ),
      if (studioArtifactMetadataInt(artifact, 'wordCount') > 0)
        ('Words', '${studioArtifactMetadataInt(artifact, 'wordCount')}'),
      if (studioArtifactMetadataInt(artifact, 'bookmarkCount') > 0)
        (
          'Bookmarks',
          '${studioArtifactMetadataInt(artifact, 'bookmarkCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'reportSectionCount') > 0)
        (
          'Report parts',
          '${studioArtifactMetadataInt(artifact, 'reportSectionCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'sectionCount') > 0)
        ('Sections', '${studioArtifactMetadataInt(artifact, 'sectionCount')}'),
      if (studioArtifactMetadataInt(artifact, 'tableCount') > 0)
        (
          studioArtifactMetadataString(artifact, 'tableCoverage').isEmpty
              ? 'Tables'
              : 'Table count',
          '${studioArtifactMetadataInt(artifact, 'tableCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'assumptionCount') > 0)
        (
          'Assumptions',
          '${studioArtifactMetadataInt(artifact, 'assumptionCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'citationCount') > 0)
        ('Sources', '${studioArtifactMetadataInt(artifact, 'citationCount')}'),
      if (studioArtifactMetadataInt(artifact, 'evidenceGapCount') > 0)
        (
          'Evidence gaps',
          '${studioArtifactMetadataInt(artifact, 'evidenceGapCount')}',
        ),
      if (studioArtifactMetadataInt(artifact, 'approvalGateCount') > 0)
        (
          'Approval gates',
          '${studioArtifactMetadataInt(artifact, 'approvalGateCount')}',
        ),
      if (studioArtifactMetadataBool(artifact, 'hasCustomerReadyPackage'))
        ('Package', 'Customer-ready report flow'),
      if (studioArtifactMetadataBool(artifact, 'hasCustomerReadyReport'))
        ('Handoff package', 'Stakeholder-ready Word report'),
      if (studioArtifactMetadataBool(artifact, 'hasCustomerReadyPdf'))
        ('Handoff package', 'Final customer PDF'),
    ],
  ];
}
