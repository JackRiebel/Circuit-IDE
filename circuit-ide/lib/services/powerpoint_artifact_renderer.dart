import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/artifact_document.dart';

class PowerPointArtifactRenderer {
  const PowerPointArtifactRenderer();

  static const int _maxSlides = 32;
  static const int _maxTablesInDeck = 4;
  static const int _tableDataRowsPerSlide = 6;

  int slideCountFor(ArtifactDocument document) {
    return _slidesFor(document).take(_maxSlides).length;
  }

  List<List<String>> previewRowsFor(ArtifactDocument document) {
    final slides = _slidesFor(
      document,
    ).take(_maxSlides).toList(growable: false);
    return [
      ['Slide', 'Type', 'Title', 'Role'],
      for (var i = 0; i < slides.length; i++)
        [
          '${i + 1}',
          slides[i].kind.label,
          slides[i].title,
          _slideRoleFor(slides[i]),
        ],
    ];
  }

  Map<String, Object?> metadataFor(ArtifactDocument document) {
    final slides = _slidesFor(
      document,
    ).take(_maxSlides).toList(growable: false);
    final theme = _DeckTheme.forDocument(document);
    final sections = document.sections.take(10).toList(growable: false);
    final slideTypeCounts = <String, int>{};
    for (final slide in slides) {
      slideTypeCounts.update(
        slide.kind.label,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final readinessSignals = _readinessSignals(document, slideTypeCounts);
    final validationGaps = _validationGapsFor(document, slideTypeCounts);
    final agendaItems = _agendaItemsFor(document, sections);
    final slideFamilies = _slideFamiliesFor(slideTypeCounts);
    final slidePreview = _slidePreviewFor(slides);
    final reviewChecklist = _reviewChecklistFor(
      document,
      slideTypeCounts,
      validationGaps,
    );
    final handoffActions = _handoffActionsFor(document, sections);
    final evidenceConfidence = _evidenceConfidenceFor(document);
    final deliveryReadinessScore = _deliveryReadinessScore(
      document,
      slideTypeCounts,
      validationGaps,
    );
    final deliveryReadinessLevel = _deliveryReadinessLevel(
      deliveryReadinessScore,
    );
    final deliveryReadinessDrivers = _deliveryReadinessDrivers(
      document,
      slideTypeCounts,
      validationGaps,
    );
    final visualVerificationChecklist = _visualVerificationChecklistFor(
      document,
      slideTypeCounts,
    );
    final evidencePolicy = _deckEvidencePolicyFor(document);
    final publishingMetadata = _deckPublishingMetadataFor(
      document,
      deliveryReadinessScore: deliveryReadinessScore,
      deliveryReadinessLevel: deliveryReadinessLevel,
      validationGaps: validationGaps,
      evidenceConfidence: evidenceConfidence,
    );
    final statusStrip = _deckStatusStripFor(
      document,
      slides: slides,
      deliveryReadinessScore: deliveryReadinessScore,
      deliveryReadinessLevel: deliveryReadinessLevel,
      validationGaps: validationGaps,
      evidenceConfidence: evidenceConfidence,
    );
    final externalHandoffManifest = _externalHandoffManifestFor(
      document,
      sections,
      deliveryReadinessLevel: deliveryReadinessLevel,
      validationGaps: validationGaps,
      evidenceConfidence: evidenceConfidence,
    );
    final customerHandoffRows = _customerHandoffRowsFor(document, sections);
    final customerHandoffReadyCount = _customerHandoffReadyCount(
      customerHandoffRows,
    );
    final customerHandoffGateStatus = _customerHandoffGateStatus(document);
    final tableContinuationSlideCount = _tableContinuationSlideCount(document);
    final tableOverflowRowCount = _tableOverflowRowCount(document);
    final tableContinuationSummaries = _tableContinuationSummaries(document);
    return {
      'generator': 'CircuitCode',
      'artifact': 'powerpoint_deck',
      'deckType': _deckTypeFor(document),
      'handoffStatus': _handoffStatusFor(validationGaps),
      'decisionAsk': _decisionAskFor(document, sections),
      'slideCount': slides.length,
      'theme': theme.label,
      'audience': _audienceFor(document),
      'deckPurpose': _deckPurposeFor(document),
      'narrativeArc': _narrativeArcFor(document, sections),
      'communicationJob': _communicationJobFor(document, sections),
      'deliveryReadinessScore': deliveryReadinessScore,
      'deliveryReadinessLevel': deliveryReadinessLevel,
      'deliveryReadinessDrivers': deliveryReadinessDrivers,
      'deliveryReadinessDriverCount': deliveryReadinessDrivers.length,
      'deckReviewPriority': _deckReviewPriorityFor(
        deliveryReadinessScore,
        validationGaps,
      ),
      'audienceHandoffNotes': _audienceHandoffNotesFor(document, sections),
      'audienceHandoffNoteCount': _audienceHandoffNotesFor(
        document,
        sections,
      ).length,
      'agendaItems': agendaItems,
      'agendaItemCount': agendaItems.length,
      'slideFamilies': slideFamilies,
      'slideFamilyCount': slideFamilies.length,
      'slidePreview': slidePreview,
      'slidePreviewCount': slidePreview.length,
      'presentationQuality': 'Enterprise structured deck',
      'visualSystem': '${theme.label} enterprise presentation system',
      'layoutFeatures': [
        'Branded title slide',
        'Numbered agenda',
        'Audience-facing readout framing',
        'Executive delivery brief',
        'Decision snapshot tiles',
        'Decision matrix',
        'Stakeholder alignment lanes',
        'Recommendation cards',
        'Roadmap timeline',
        'Publishing gate slide',
        'Customer handoff readiness matrix',
        'Visible readiness/evidence status strip',
        'Closing decision ask',
        if (slideTypeCounts.containsKey(_DeckSlideKind.sectionDivider.label))
          'Section divider slides',
        if (slideTypeCounts.containsKey(_DeckSlideKind.table.label))
          'Table slides',
        'Speaker notes',
      ],
      'tableCoverage': document.tables.isEmpty
          ? 'No supporting tables'
          : '${document.tables.length} table${document.tables.length == 1 ? '' : 's'} packaged',
      'hasTableContinuationSlides': tableContinuationSlideCount > 0,
      'tableContinuationSlideCount': tableContinuationSlideCount,
      'tableOverflowRowCount': tableOverflowRowCount,
      'tableContinuationSummaries': tableContinuationSummaries,
      'tableContinuationSummaryCount': tableContinuationSummaries.length,
      'sourceCoverage': document.citations.isEmpty
          ? 'No citations attached'
          : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} captured',
      'evidenceConfidence': evidenceConfidence,
      'deckReviewChecklist': reviewChecklist,
      'deckReviewChecklistCount': reviewChecklist.length,
      'deckVisualVerificationChecklist': visualVerificationChecklist,
      'deckVisualVerificationChecklistCount':
          visualVerificationChecklist.length,
      'deckEvidencePolicy': evidencePolicy,
      'deckEvidencePolicyCount': evidencePolicy.length,
      'deckPublishingMetadata': publishingMetadata,
      'deckPublishingMetadataCount': publishingMetadata.length,
      'deckStatusStrip': statusStrip.labels,
      'deckStatusStripCount': statusStrip.labels.length,
      'hasDeckStatusStrip': statusStrip.labels.isNotEmpty,
      'externalHandoffManifest': externalHandoffManifest,
      'externalHandoffManifestCount': externalHandoffManifest.length,
      'hasExternalHandoffManifest': externalHandoffManifest.isNotEmpty,
      'customerHandoffGateStatus': customerHandoffGateStatus,
      'customerHandoffGateRows': customerHandoffRows
          .skip(1)
          .map((row) => row.join(' | '))
          .toList(growable: false),
      'customerHandoffGateCount': math.max(0, customerHandoffRows.length - 1),
      'customerHandoffGateReadyCount': customerHandoffReadyCount,
      'hasCustomerHandoffReadinessMatrix': true,
      'deckHandoffActions': handoffActions,
      'deckHandoffActionCount': handoffActions.length,
      'presentationRiskFlags': _presentationRiskFlagsFor(
        document,
        validationGaps,
      ),
      'validationGaps': validationGaps,
      'validationGapCount': validationGaps.length,
      'slideTypes': slideTypeCounts.keys.toList(growable: false),
      'slideTypeCounts': slideTypeCounts,
      'sectionCount': document.sections.length,
      'sectionDividerCount':
          slideTypeCounts[_DeckSlideKind.sectionDivider.label] ?? 0,
      'qualityManifestVersion': '1.0',
      'hasNarrativeManifest': true,
      'hasCustomerFacingVisibleSlides': true,
      'presenterGuidanceLocation': 'Speaker notes and readout framing metadata',
      'slideCopyPolicy':
          'Visible slides use audience-facing copy; presenter support belongs in notes and metadata.',
      'presenterTalkTrackSlideCount':
          slideTypeCounts[_DeckSlideKind.talkTrack.label] ?? 0,
      'deliveryBriefSlideCount':
          slideTypeCounts[_DeckSlideKind.deliveryBrief.label] ?? 0,
      'tableCount': document.tables.length,
      'tableSlideCount': slideTypeCounts[_DeckSlideKind.table.label] ?? 0,
      'decisionMatrixSlideCount':
          slideTypeCounts[_DeckSlideKind.decisionMatrix.label] ?? 0,
      'stakeholderAlignmentSlideCount':
          slideTypeCounts[_DeckSlideKind.stakeholderAlignment.label] ?? 0,
      'closingDecisionSlideCount':
          slideTypeCounts[_DeckSlideKind.closing.label] ?? 0,
      'publishingGateSlideCount':
          slideTypeCounts[_DeckSlideKind.publishingGate.label] ?? 0,
      'handoffReadinessSlideCount':
          slideTypeCounts[_DeckSlideKind.handoffReadiness.label] ?? 0,
      'recommendationSlideCount':
          slideTypeCounts[_DeckSlideKind.recommendation.label] ?? 0,
      'assumptionCount': document.assumptions.length,
      'citationCount': document.citations.length,
      'readinessSignals': readinessSignals,
      'readinessSignalCount': readinessSignals.length,
      'hasAgenda': slideTypeCounts.containsKey(_DeckSlideKind.agenda.label),
      'hasPresenterTalkTrack': slideTypeCounts.containsKey(
        _DeckSlideKind.talkTrack.label,
      ),
      'hasDeliveryBrief': slideTypeCounts.containsKey(
        _DeckSlideKind.deliveryBrief.label,
      ),
      'presenterBrief': _communicationJobFor(document, sections),
      'hasDecisionSnapshot': slideTypeCounts.containsKey(
        _DeckSlideKind.snapshot.label,
      ),
      'hasSectionDividers': slideTypeCounts.containsKey(
        _DeckSlideKind.sectionDivider.label,
      ),
      'hasSectionDividerLayout': slideTypeCounts.containsKey(
        _DeckSlideKind.sectionDivider.label,
      ),
      'hasEnterpriseBrandPill': true,
      'hasRecommendation': slideTypeCounts.containsKey(
        _DeckSlideKind.recommendation.label,
      ),
      'hasDecisionMatrix': slideTypeCounts.containsKey(
        _DeckSlideKind.decisionMatrix.label,
      ),
      'hasStakeholderAlignment': slideTypeCounts.containsKey(
        _DeckSlideKind.stakeholderAlignment.label,
      ),
      'hasClosingDecisionAsk': slideTypeCounts.containsKey(
        _DeckSlideKind.closing.label,
      ),
      'hasPublishingGateSlide': slideTypeCounts.containsKey(
        _DeckSlideKind.publishingGate.label,
      ),
      'hasHandoffReadinessSlide': slideTypeCounts.containsKey(
        _DeckSlideKind.handoffReadiness.label,
      ),
      'hasRoadmap': slideTypeCounts.containsKey(_DeckSlideKind.roadmap.label),
      'hasTableSlides': slideTypeCounts.containsKey(_DeckSlideKind.table.label),
      'hasSourcesSlide': slideTypeCounts.containsKey(
        _DeckSlideKind.sources.label,
      ),
      'hasDataSnapshot': slideTypeCounts.containsKey(
        _DeckSlideKind.dataSnapshot.label,
      ),
      'hasAppendixHandoff': slideTypeCounts.containsKey(
        _DeckSlideKind.appendix.label,
      ),
      'hasSpeakerNotes': true,
      'hasDeckVisualVerificationChecklist':
          visualVerificationChecklist.isNotEmpty,
      'hasDeckEvidencePolicy': evidencePolicy.isNotEmpty,
      'hasDeckPublishingMetadata': publishingMetadata.isNotEmpty,
      'hasDeckPublishingGate': publishingMetadata.isNotEmpty,
      'speakerNoteCount': slides.length,
      'hasCustomerReadyStructure': _hasCustomerReadyStructure(slideTypeCounts),
      'hasCustomerReadyDeck':
          _hasCustomerReadyStructure(slideTypeCounts) && validationGaps.isEmpty,
      'maxSlides': _maxSlides,
    };
  }

  Uint8List render(ArtifactDocument document) {
    final slides = _slidesFor(
      document,
    ).take(_maxSlides).toList(growable: false);
    final theme = _DeckTheme.forDocument(document);
    final statusStrip = _deckStatusStripFor(document, slides: slides);
    final files = <_PptxFile>[
      _PptxFile('[Content_Types].xml', _bytes(_contentTypes(slides.length))),
      _PptxFile('_rels/.rels', _bytes(_rootRels())),
      _PptxFile('docProps/app.xml', _bytes(_appXml(slides.length))),
      _PptxFile('docProps/core.xml', _bytes(_coreXml(document.title))),
      _PptxFile(
        'docProps/custom.xml',
        _bytes(_customXml(document, slides: slides, theme: theme)),
      ),
      _PptxFile('ppt/presentation.xml', _bytes(_presentation(slides.length))),
      _PptxFile(
        'ppt/_rels/presentation.xml.rels',
        _bytes(_presentationRels(slides.length)),
      ),
      _PptxFile('ppt/slideMasters/slideMaster1.xml', _bytes(_slideMaster())),
      _PptxFile(
        'ppt/slideMasters/_rels/slideMaster1.xml.rels',
        _bytes(_slideMasterRels()),
      ),
      _PptxFile('ppt/notesMasters/notesMaster1.xml', _bytes(_notesMaster())),
      _PptxFile(
        'ppt/notesMasters/_rels/notesMaster1.xml.rels',
        _bytes(_notesMasterRels()),
      ),
      _PptxFile('ppt/slideLayouts/slideLayout1.xml', _bytes(_slideLayout())),
      _PptxFile(
        'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
        _bytes(_slideLayoutRels()),
      ),
      _PptxFile('ppt/theme/theme1.xml', _bytes(_theme())),
      for (var i = 0; i < slides.length; i++)
        _PptxFile(
          'ppt/slides/slide${i + 1}.xml',
          _bytes(
            _slide(
              slides[i],
              theme: theme,
              statusStrip: statusStrip,
              slideNumber: i + 1,
              totalSlides: slides.length,
            ),
          ),
        ),
      for (var i = 0; i < slides.length; i++)
        _PptxFile(
          'ppt/slides/_rels/slide${i + 1}.xml.rels',
          _bytes(_slideRels(i + 1)),
        ),
      for (var i = 0; i < slides.length; i++)
        _PptxFile(
          'ppt/notesSlides/notesSlide${i + 1}.xml',
          _bytes(_notesSlide(slides[i], slideNumber: i + 1)),
        ),
      for (var i = 0; i < slides.length; i++)
        _PptxFile(
          'ppt/notesSlides/_rels/notesSlide${i + 1}.xml.rels',
          _bytes(_notesSlideRels(i + 1)),
        ),
    ];
    return _zip(files);
  }

  List<_DeckSlide> _slidesFor(ArtifactDocument document) {
    final sections = document.sections.take(10).toList(growable: false);
    final slides = <_DeckSlide>[
      _DeckSlide(
        title: document.title,
        eyebrow: 'CircuitCode deliverable',
        kind: _DeckSlideKind.title,
        bullets: [
          if (document.summary.isNotEmpty) document.summary,
          'Purpose: ${_deckPurposeFor(document)}.',
          'Decision ask: ${_decisionAskFor(document, sections)}',
          if (document.tables.isNotEmpty)
            '${document.tables.length} table artifact${document.tables.length == 1 ? '' : 's'} included',
          if (document.citations.isNotEmpty)
            '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} captured',
        ],
      ),
      _DeckSlide(
        title: 'Decision Flow',
        eyebrow: 'Agenda',
        kind: _DeckSlideKind.agenda,
        bullets: [
          'Orient on the customer context and decision.',
          'Review evidence, implications, and open risks.',
          'Align on the recommended path and owners.',
          'Confirm handoff actions, validation, and next step.',
          for (final section in sections.take(3)) section.title,
          if (document.tables.isNotEmpty) 'Data tables and supporting detail',
        ],
      ),
      _presenterTalkTrack(document, sections),
      _decisionSnapshot(document, sections),
      _deliveryBrief(document, sections),
      _executiveRecommendation(document, sections),
      _decisionMatrix(document, sections),
      _stakeholderAlignment(document, sections),
      if (document.summary.isNotEmpty)
        _DeckSlide(
          title: 'Executive Summary',
          eyebrow: 'Summary',
          kind: _DeckSlideKind.content,
          bullets: _sentences(document.summary).take(5).toList(growable: false),
        ),
      _keyTakeaways(document, sections),
      _implementationRoadmap(document, sections),
    ];
    for (final section in sections) {
      final bullets = [
        ...section.bullets,
        if (section.bullets.isEmpty && section.body.isNotEmpty)
          ..._sentences(section.body).take(5),
      ];
      slides
        ..add(_sectionDivider(section, bullets))
        ..add(
          _DeckSlide(
            title: _contentTitle(section.title),
            eyebrow: _contentEyebrow(section.title),
            kind: _sectionKind(section.title),
            bullets: _recommendationBullets(section.title, bullets),
          ),
        );
    }
    if (document.tables.isNotEmpty) {
      slides.add(_dataSnapshot(document));
      for (final table in document.tables.take(_maxTablesInDeck)) {
        slides.addAll(_tableSlidesFor(table));
      }
    }
    slides.add(_assumptionsAndSources(document));
    slides.add(_customerHandoffReadiness(document, sections));
    slides.add(_publishingGate(document, sections));
    slides.add(_closingDecisionAsk(document, sections));
    slides.add(_appendixHandoff(document));
    return slides;
  }

  _DeckSlide _executiveRecommendation(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final recommendation = _firstMatchingBullet(sections, [
      'recommend',
      'solution',
      'architecture',
      'proposal',
    ]);
    final validation = _firstMatchingBullet(sections, [
      'validate',
      'verify',
      'evidence',
      'source',
    ]);
    final next = _firstMatchingBullet(sections, ['next', 'phase', 'action']);
    return _DeckSlide(
      title: 'Executive Recommendation',
      eyebrow: 'Decision-ready guidance',
      kind: _DeckSlideKind.recommendation,
      bullets: [
        recommendation == null
            ? 'Recommendation: Align on the preferred path, then turn this deck into a reviewed implementation artifact.'
            : 'Recommendation: $recommendation',
        if (document.summary.isNotEmpty)
          'Business context: ${_truncate(document.summary, 150)}',
        validation == null
            ? 'Validation: Confirm source data, stakeholder assumptions, and approval criteria before execution.'
            : 'Validation: $validation',
        next == null
            ? 'Next action: Assign owners, confirm timeline, and approve the first implementation batch.'
            : 'Next action: $next',
      ],
    );
  }

  _DeckSlide _deliveryBrief(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final recommendation = _firstMatchingBullet(sections, [
      'recommend',
      'solution',
      'architecture',
      'proposal',
      'decision',
    ]);
    final evidence = _firstMatchingBullet(sections, [
      'evidence',
      'source',
      'validate',
      'data',
    ]);
    final risk = _firstMatchingBullet(sections, ['risk', 'caveat', 'concern']);
    final next = _firstMatchingBullet(sections, [
      'next',
      'phase',
      'action',
      'owner',
      'approve',
    ]);
    return _DeckSlide(
      title: 'Executive Delivery Brief',
      eyebrow: 'Customer handoff',
      kind: _DeckSlideKind.deliveryBrief,
      bullets: const [
        'Delivery brief frames the deck as an executive handoff: outcome, proof, open decision, and next owner.',
      ],
      tableRows: [
        const ['Handoff area', 'Current signal', 'Action'],
        [
          'Outcome',
          _truncate(
            recommendation ??
                (document.summary.isEmpty
                    ? 'Align stakeholders on the proposed direction.'
                    : document.summary),
            72,
          ),
          'Confirm this is the customer-facing outcome.',
        ],
        [
          'Proof',
          _truncate(
            evidence ??
                (document.tables.isEmpty
                    ? 'Attach supporting data or source evidence.'
                    : '${document.tables.length} supporting table${document.tables.length == 1 ? '' : 's'} included.'),
            72,
          ),
          'Validate sources, assumptions, and dates.',
        ],
        [
          'Open risk',
          _truncate(
            risk ??
                (document.assumptions.isEmpty
                    ? 'Assumptions and constraints need owner confirmation.'
                    : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} documented.'),
            72,
          ),
          'Resolve or explicitly accept before external handoff.',
        ],
        [
          'Next owner',
          _truncate(
            next ?? 'Assign owner, due date, and success criteria.',
            72,
          ),
          'Turn approval into a tracked next step.',
        ],
      ],
    );
  }

  _DeckSlide _presenterTalkTrack(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final audience = _audienceFor(document);
    final purpose = _deckPurposeFor(document);
    final decisionAsk = _decisionAskFor(document, sections);
    final narrative = _narrativeArcFor(document, sections);
    final job = _communicationJobFor(document, sections);
    final validation = _firstMatchingBullet(sections, [
      'validate',
      'verify',
      'evidence',
      'source',
    ]);
    return _DeckSlide(
      title: 'Readout Framing',
      eyebrow: 'Audience narrative',
      kind: _DeckSlideKind.talkTrack,
      bullets: [
        'Audience: $audience',
        'Purpose: $purpose',
        'Narrative path: $narrative',
        'Decision ask: $decisionAsk',
        validation == null
            ? 'Evidence check: Confirm assumptions, source data, and open evidence gaps before asking for approval.'
            : 'Evidence check: $validation',
        'Outcome: $job',
      ],
    );
  }

  _DeckSlide _keyTakeaways(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final recommendation = _firstMatchingBullet(sections, [
      'recommend',
      'solution',
      'architecture',
    ]);
    final risk = _firstMatchingBullet(sections, ['risk', 'caveat', 'concern']);
    final next = _firstMatchingBullet(sections, ['next', 'phase', 'action']);
    return _DeckSlide(
      title: 'Key Takeaways',
      eyebrow: 'Executive highlights',
      kind: _DeckSlideKind.takeaways,
      bullets: [
        if (document.summary.isNotEmpty)
          'Outcome: ${_truncate(document.summary, 150)}',
        if (recommendation != null)
          'Recommendation: ${_truncate(recommendation, 145)}',
        if (risk != null) 'Watch item: ${_truncate(risk, 145)}',
        if (next != null) 'Next action: ${_truncate(next, 145)}',
        if (document.tables.isNotEmpty)
          'Data: ${document.tables.length} supporting table${document.tables.length == 1 ? '' : 's'} packaged with the deck.',
      ],
    );
  }

  _DeckSlide _decisionSnapshot(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final recommendation = _firstMatchingBullet(sections, [
      'recommend',
      'solution',
      'architecture',
    ]);
    final risk = _firstMatchingBullet(sections, ['risk', 'caveat', 'concern']);
    final next = _firstMatchingBullet(sections, ['next', 'phase', 'action']);
    return _DeckSlide(
      title: 'Decision Snapshot',
      eyebrow: 'Executive readout',
      kind: _DeckSlideKind.snapshot,
      bullets: [
        recommendation == null
            ? 'Recommendation: Review the proposed approach and confirm the desired implementation path.'
            : 'Recommendation: $recommendation',
        risk == null
            ? 'Risk: Validate assumptions, source data, and implementation constraints before final approval.'
            : 'Risk: $risk',
        next == null
            ? 'Next step: Align on scope, owners, and verification criteria.'
            : 'Next step: $next',
        if (document.tables.isNotEmpty)
          'Evidence: ${document.tables.length} structured data table${document.tables.length == 1 ? '' : 's'} included.',
      ],
    );
  }

  _DeckSlide _decisionMatrix(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final recommendation = _firstMatchingBullet(sections, [
      'recommend',
      'solution',
      'architecture',
    ]);
    final evidence = _firstMatchingBullet(sections, [
      'evidence',
      'source',
      'validate',
      'data',
    ]);
    final risk = _firstMatchingBullet(sections, ['risk', 'caveat', 'concern']);
    final next = _firstMatchingBullet(sections, [
      'next',
      'phase',
      'action',
      'owner',
    ]);
    return _DeckSlide(
      title: 'Decision Matrix',
      eyebrow: 'Executive decision support',
      kind: _DeckSlideKind.decisionMatrix,
      bullets: [
        'Decision matrix captures recommendation, evidence, risk, and next action so the deck can be reviewed without reading every appendix.',
      ],
      tableRows: [
        ['Decision Area', 'Current Signal', 'Stakeholder Action'],
        [
          'Recommendation',
          _truncate(
            recommendation ??
                (document.summary.isEmpty
                    ? 'Preferred path requires stakeholder confirmation.'
                    : document.summary),
            64,
          ),
          'Approve, revise, or ask for another option.',
        ],
        [
          'Evidence',
          _truncate(
            evidence ??
                (document.tables.isEmpty
                    ? 'Attach supporting data before customer handoff.'
                    : '${document.tables.length} supporting table${document.tables.length == 1 ? '' : 's'} packaged.'),
            64,
          ),
          'Confirm source data and assumptions.',
        ],
        [
          'Risk',
          _truncate(
            risk ??
                (document.assumptions.isEmpty
                    ? 'Assumptions still need confirmation.'
                    : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} documented.'),
            64,
          ),
          'Resolve blockers before execution.',
        ],
        [
          'Next Step',
          _truncate(
            next ?? 'Assign owner, due date, and verification criteria.',
            64,
          ),
          'Turn decision into an implementation task.',
        ],
      ],
    );
  }

  _DeckSlide _stakeholderAlignment(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    return _DeckSlide(
      title: 'Stakeholder Alignment',
      eyebrow: 'Owner lanes',
      kind: _DeckSlideKind.stakeholderAlignment,
      bullets: const [
        'Stakeholder alignment maps decision roles, evidence needs, and follow-up actions so the deck can move from readout to execution.',
      ],
      tableRows: [
        const [
          'Owner / stakeholder',
          'Decision role',
          'What they need',
          'Follow-up action',
        ],
        ..._stakeholderRows(document, sections),
      ],
    );
  }

  _DeckSlide _dataSnapshot(ArtifactDocument document) {
    return _DeckSlide(
      title: 'Data Snapshot',
      eyebrow: 'Supporting detail',
      kind: _DeckSlideKind.dataSnapshot,
      bullets: [
        for (final table in document.tables.take(6))
          '${table.title}: ${math.max(0, table.rows.length - 1)} row${table.rows.length == 2 ? '' : 's'} across ${table.rows.isEmpty ? 0 : table.rows.first.length} column${table.rows.isNotEmpty && table.rows.first.length == 1 ? '' : 's'}',
        if (document.tables.length > 6)
          '${document.tables.length - 6} additional table${document.tables.length - 6 == 1 ? '' : 's'} available in the source artifact.',
      ],
    );
  }

  List<List<String>> _stakeholderRows(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final recommendation = _firstMatchingBullet(sections, [
      'recommend',
      'solution',
      'architecture',
    ]);
    final risk = _firstMatchingBullet(sections, ['risk', 'caveat', 'concern']);
    final next = _firstMatchingBullet(sections, [
      'next',
      'phase',
      'action',
      'owner',
    ]);
    final evidence = _firstMatchingBullet(sections, [
      'evidence',
      'source',
      'validate',
      'data',
    ]);
    return [
      [
        _primarySponsorFor(document),
        'Approve direction',
        _truncate(
          recommendation ??
              (document.summary.isEmpty
                  ? 'Clear recommendation and business rationale.'
                  : document.summary),
          70,
        ),
        'Confirm decision, scope, and success criteria.',
      ],
      [
        'Technical owner',
        'Validate feasibility',
        _truncate(
          evidence ??
              (document.tables.isEmpty
                  ? 'Supporting data, constraints, and implementation path.'
                  : '${document.tables.length} supporting table${document.tables.length == 1 ? '' : 's'} and implementation assumptions.'),
          70,
        ),
        'Validate design constraints, dependencies, and rollout path.',
      ],
      [
        'Risk / operations owner',
        'Accept risk posture',
        _truncate(
          risk ??
              (document.assumptions.isEmpty
                  ? 'Known risks and assumptions still need owner review.'
                  : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} requiring confirmation.'),
          70,
        ),
        'Resolve blockers and record operational acceptance.',
      ],
      [
        'Implementation owner',
        'Drive next step',
        _truncate(next ?? 'Owner, timeline, and verification plan.', 70),
        'Turn the decision into a tracked implementation or handoff task.',
      ],
    ];
  }

  String _primarySponsorFor(ArtifactDocument document) {
    final text =
        '${document.metadata['prompt'] ?? ''} ${document.title} ${document.summary}'
            .toLowerCase();
    if (text.contains('customer') || text.contains('proposal')) {
      return 'Customer sponsor';
    }
    if (text.contains('business case') || text.contains('value')) {
      return 'Business sponsor';
    }
    if (text.contains('architecture') || text.contains('technical')) {
      return 'Architecture sponsor';
    }
    return 'Executive sponsor';
  }

  _DeckSlide _implementationRoadmap(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final roadmapBullets = <String>[];
    for (final section in sections) {
      final title = section.title.toLowerCase();
      if (!title.contains('next') &&
          !title.contains('phase') &&
          !title.contains('roadmap') &&
          !title.contains('implement') &&
          !title.contains('verification')) {
        continue;
      }
      roadmapBullets.addAll(section.bullets);
      if (roadmapBullets.isEmpty && section.body.trim().isNotEmpty) {
        roadmapBullets.addAll(_sentences(section.body).take(4));
      }
    }
    if (roadmapBullets.isEmpty) {
      roadmapBullets.addAll([
        'Confirm stakeholder goals, scope, owners, and approval path.',
        if (document.tables.isNotEmpty)
          'Validate source data from ${document.tables.length} supporting table${document.tables.length == 1 ? '' : 's'}.',
        'Finalize recommendations, assumptions, risks, and success criteria.',
        'Run implementation or handoff review and capture verification evidence.',
      ]);
    }
    return _DeckSlide(
      title: 'Implementation Roadmap',
      eyebrow: 'Action plan',
      kind: _DeckSlideKind.roadmap,
      bullets: roadmapBullets.take(6).toList(growable: false),
    );
  }

  _DeckSlide _assumptionsAndSources(ArtifactDocument document) {
    final bullets = <String>[
      if (document.assumptions.isEmpty)
        'Assumption: Customer requirements, constraints, and implementation timeline require final confirmation.',
      for (final item in document.assumptions.take(5)) 'Assumption: $item',
      if (document.citations.isEmpty)
        'Source: No external citations were attached; treat this as a draft until evidence is added.',
      for (final item in document.citations.take(5)) 'Source: $item',
    ];
    return _DeckSlide(
      title: 'Assumptions & Sources',
      eyebrow: 'Evidence handoff',
      kind: _DeckSlideKind.sources,
      bullets: bullets,
    );
  }

  _DeckSlide _publishingGate(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final evidenceStatus = _evidenceConfidenceFor(document);
    final assumptionStatus = document.assumptions.isEmpty
        ? 'Assumptions missing'
        : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} captured';
    final sourceStatus = document.citations.isEmpty
        ? 'Sources missing'
        : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} attached';
    return _DeckSlide(
      title: 'Review & Publishing Gate',
      eyebrow: 'Customer-ready checkpoint',
      kind: _DeckSlideKind.publishingGate,
      bullets: const [
        'Publishing gate turns the generated deck into a reviewed customer handoff package before external sharing.',
      ],
      tableRows: [
        const ['Gate', 'Current status', 'Owner action'],
        [
          'Evidence',
          _truncate(evidenceStatus, 64),
          document.citations.isEmpty
              ? 'Attach cited source package before sharing.'
              : 'Keep source package attached to the deck.',
        ],
        [
          'Assumptions',
          _truncate(assumptionStatus, 64),
          document.assumptions.isEmpty
              ? 'Capture accountable assumption owner.'
              : 'Confirm assumptions with accountable owner.',
        ],
        [
          'Visual QA',
          '16:9 deck review required',
          'Open deck and check title, tables, roadmap, close, and sources.',
        ],
        [
          'Decision ask',
          _truncate(_decisionAskFor(document, sections), 64),
          'Approve, revise, or assign next implementation owner.',
        ],
        [
          'External handoff',
          _truncate(sourceStatus, 64),
          'Share only after reviewer approval is recorded.',
        ],
      ],
    );
  }

  _DeckSlide _customerHandoffReadiness(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    return _DeckSlide(
      title: 'Customer Handoff Readiness',
      eyebrow: 'External sharing gate',
      kind: _DeckSlideKind.handoffReadiness,
      bullets: [
        'Use this matrix before sending the deck externally: every gate should have evidence, an accountable owner, and a clear next action.',
      ],
      tableRows: _customerHandoffRowsFor(document, sections),
    );
  }

  List<List<String>> _customerHandoffRowsFor(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final hasEvidence = document.citations.isNotEmpty;
    final hasAssumptions = document.assumptions.isNotEmpty;
    final hasData = document.tables.isNotEmpty;
    final ask = _decisionAskFor(document, sections);
    final owner = _primarySponsorFor(document);
    return [
      const ['Gate', 'Signal', 'Status', 'Owner action'],
      [
        'Evidence package',
        hasEvidence
            ? '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} attached'
            : 'No cited source package attached',
        hasEvidence ? 'Ready' : 'Needs evidence',
        hasEvidence
            ? 'Keep evidence pack linked to the customer handoff.'
            : 'Attach source links, checked dates, or evidence notes.',
      ],
      [
        'Assumptions',
        hasAssumptions
            ? '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} captured'
            : 'No assumptions captured',
        hasAssumptions ? 'Ready' : 'Needs owner',
        hasAssumptions
            ? 'Confirm each assumption with the named stakeholder.'
            : 'Capture assumptions, caveats, and accountable owner.',
      ],
      [
        'Data support',
        hasData
            ? '${document.tables.length} table${document.tables.length == 1 ? '' : 's'} packaged'
            : 'No supporting data table packaged',
        hasData ? 'Ready' : 'Needs support',
        hasData
            ? 'Validate numbers and scope before external send.'
            : 'Attach sizing, inventory, comparison, or source data.',
      ],
      [
        'Decision ask',
        _truncate(ask, 74),
        ask.toLowerCase().contains('review') ||
                ask.toLowerCase().contains('approve')
            ? 'Ready'
            : 'Clarify ask',
        'Confirm the requested decision, deadline, and follow-up owner.',
      ],
      [
        'Sharing owner',
        owner,
        owner.toLowerCase().contains('sponsor') ? 'Ready' : 'Assign owner',
        'Record who approves the deck before customer delivery.',
      ],
    ];
  }

  String _customerHandoffGateStatus(ArtifactDocument document) {
    final readyCount = [
      document.citations.isNotEmpty,
      document.assumptions.isNotEmpty,
      document.tables.isNotEmpty,
    ].where((ready) => ready).length;
    if (readyCount == 3) return 'Ready for reviewer approval';
    if (readyCount >= 2) return 'Internal review before external handoff';
    return 'Draft - add evidence before external sharing';
  }

  int _customerHandoffReadyCount(List<List<String>> rows) {
    return rows.skip(1).where((row) {
      if (row.length < 3) return false;
      return row[2].trim().toLowerCase() == 'ready';
    }).length;
  }

  _DeckSlide _appendixHandoff(ArtifactDocument document) {
    final artifactTypes = <String>[
      if (document.tables.isNotEmpty)
        '${document.tables.length} data table${document.tables.length == 1 ? '' : 's'}',
      if (document.assumptions.isNotEmpty)
        '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'}',
      if (document.citations.isNotEmpty)
        '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'}',
    ];
    return _DeckSlide(
      title: 'Appendix: Handoff Checklist',
      eyebrow: 'Review package',
      kind: _DeckSlideKind.appendix,
      bullets: [
        'Review scope: Confirm title, executive summary, recommendations, risks, and next actions with the account team.',
        if (artifactTypes.isEmpty)
          'Supporting material: Attach source data, citations, and customer assumptions before final delivery.'
        else
          'Supporting material: ${artifactTypes.join(', ')} included in this generated artifact.',
        'Customer readiness: Validate terminology, product names, dates, and stakeholder-specific language.',
        'Approval path: Capture owner, due date, and success criteria before converting this into an implementation packet.',
      ],
    );
  }

  _DeckSlide _closingDecisionAsk(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final ask = _decisionAskFor(document, sections);
    final next = _firstMatchingBullet(sections, ['next', 'phase', 'action']);
    final validation = _firstMatchingBullet(sections, [
      'validate',
      'verify',
      'evidence',
    ]);
    return _DeckSlide(
      title: 'Decision Ask & Next Steps',
      eyebrow: 'Close',
      kind: _DeckSlideKind.closing,
      bullets: [
        'Decision ask: $ask',
        next == null
            ? 'Owner action: Confirm scope, timeline, and approval path.'
            : 'Owner action: $next',
        validation == null
            ? 'Validation: Confirm assumptions, source data, and success criteria.'
            : 'Validation: $validation',
        'Handoff: Use this deck as the stakeholder readout and keep the source artifact attached for review.',
      ],
    );
  }

  String _audienceFor(ArtifactDocument document) {
    final text =
        '${document.metadata['prompt'] ?? ''} ${document.title} ${document.summary} ${document.sections.map((section) => section.title).join(' ')}'
            .toLowerCase();
    if (text.contains('customer') ||
        text.contains('proposal') ||
        text.contains('client')) {
      return 'Customer stakeholders';
    }
    if (text.contains('executive') || text.contains('leadership')) {
      return 'Executive stakeholders';
    }
    if (text.contains('architecture') ||
        text.contains('technical') ||
        text.contains('network')) {
      return 'Architecture reviewers';
    }
    if (text.contains('sales') || text.contains('business case')) {
      return 'Sales and business stakeholders';
    }
    return 'Project stakeholders';
  }

  String _deckPurposeFor(ArtifactDocument document) {
    final prompt = '${document.metadata['prompt'] ?? ''}'.toLowerCase();
    final allText =
        '${document.title} ${document.summary} ${document.sections.map((s) => s.title).join(' ')}'
            .toLowerCase();
    if (prompt.contains('proposal') || allText.contains('recommend')) {
      return 'Support a decision';
    }
    if (prompt.contains('review') || allText.contains('risk')) {
      return 'Review findings and risks';
    }
    if (prompt.contains('business case') || allText.contains('value')) {
      return 'Build business alignment';
    }
    if (prompt.contains('implementation') || allText.contains('roadmap')) {
      return 'Guide implementation';
    }
    return 'Inform and align';
  }

  String _narrativeArcFor(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final sectionText = sections.map((section) => section.title).join(' ');
    final text = '${document.title} ${document.summary} $sectionText'
        .toLowerCase();
    if (text.contains('risk') && text.contains('recommend')) {
      return 'Context -> risk -> recommendation -> action';
    }
    if (text.contains('current') && text.contains('future')) {
      return 'Current state -> future state -> path';
    }
    if (text.contains('problem') || text.contains('challenge')) {
      return 'Problem -> options -> recommendation';
    }
    if (text.contains('implementation') || text.contains('roadmap')) {
      return 'Scope -> phases -> verification -> handoff';
    }
    return 'Context -> evidence -> implication -> next step';
  }

  String _communicationJobFor(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final audience = _audienceFor(document);
    final purpose = _deckPurposeFor(document).toLowerCase();
    final takeaway =
        _firstMatchingBullet(sections, [
          'recommend',
          'solution',
          'architecture',
          'decision',
        ]) ??
        (document.summary.isNotEmpty
            ? _truncate(document.summary, 120)
            : 'the proposed path and required validation steps');
    return 'By the end, $audience should $purpose because $takeaway.';
  }

  List<String> _readinessSignals(
    ArtifactDocument document,
    Map<String, int> slideTypeCounts,
  ) {
    final signals = <String>[
      if (slideTypeCounts.containsKey(_DeckSlideKind.agenda.label)) 'Agenda',
      if (slideTypeCounts.containsKey(_DeckSlideKind.talkTrack.label))
        'Readout framing',
      if (slideTypeCounts.containsKey(_DeckSlideKind.deliveryBrief.label))
        'Delivery brief',
      if (slideTypeCounts.containsKey(_DeckSlideKind.snapshot.label))
        'Decision snapshot',
      if (slideTypeCounts.containsKey(_DeckSlideKind.recommendation.label))
        'Recommendation slides',
      if (slideTypeCounts.containsKey(_DeckSlideKind.decisionMatrix.label))
        'Decision matrix',
      if (slideTypeCounts.containsKey(
        _DeckSlideKind.stakeholderAlignment.label,
      ))
        'Stakeholder alignment',
      if (slideTypeCounts.containsKey(_DeckSlideKind.roadmap.label)) 'Roadmap',
      if (slideTypeCounts.containsKey(_DeckSlideKind.handoffReadiness.label))
        'Customer handoff readiness',
      if (slideTypeCounts.containsKey(_DeckSlideKind.closing.label))
        'Closing ask',
      if (slideTypeCounts.containsKey(_DeckSlideKind.table.label))
        'Table slides',
      if (_tableContinuationSlideCount(document) > 0)
        'Table continuation slides',
      if (document.assumptions.isNotEmpty || document.citations.isNotEmpty)
        'Assumptions/sources',
      'Speaker notes',
    ];
    return signals;
  }

  List<String> _agendaItemsFor(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    return [
      if (document.summary.isNotEmpty) 'Executive summary',
      for (final section in sections.take(7)) section.title,
      if (document.tables.isNotEmpty) 'Data tables and supporting detail',
      if (document.assumptions.isNotEmpty || document.citations.isNotEmpty)
        'Assumptions and sources',
    ];
  }

  List<String> _slideFamiliesFor(Map<String, int> slideTypeCounts) {
    return [
      if (slideTypeCounts.containsKey(_DeckSlideKind.title.label)) 'Opening',
      if (slideTypeCounts.containsKey(_DeckSlideKind.agenda.label)) 'Agenda',
      if (slideTypeCounts.containsKey(_DeckSlideKind.talkTrack.label))
        'Readout framing',
      if (slideTypeCounts.containsKey(_DeckSlideKind.deliveryBrief.label))
        'Executive delivery brief',
      if (slideTypeCounts.containsKey(_DeckSlideKind.snapshot.label))
        'Decision snapshot',
      if (slideTypeCounts.containsKey(_DeckSlideKind.recommendation.label))
        'Recommendations',
      if (slideTypeCounts.containsKey(_DeckSlideKind.decisionMatrix.label))
        'Decision matrix',
      if (slideTypeCounts.containsKey(
        _DeckSlideKind.stakeholderAlignment.label,
      ))
        'Stakeholder alignment',
      if (slideTypeCounts.containsKey(_DeckSlideKind.roadmap.label)) 'Roadmap',
      if (slideTypeCounts.containsKey(_DeckSlideKind.table.label))
        'Data tables',
      if (slideTypeCounts.containsKey(_DeckSlideKind.sources.label))
        'Assumptions/sources',
      if (slideTypeCounts.containsKey(_DeckSlideKind.handoffReadiness.label))
        'Customer handoff',
      if (slideTypeCounts.containsKey(_DeckSlideKind.publishingGate.label))
        'Publishing gate',
      if (slideTypeCounts.containsKey(_DeckSlideKind.appendix.label))
        'Appendix',
    ];
  }

  List<String> _slidePreviewFor(List<_DeckSlide> slides) {
    return [
      for (var i = 0; i < slides.length && i < 10; i++)
        '${i + 1}. ${slides[i].kind.label}: ${slides[i].title} - ${_slideRoleFor(slides[i])}',
      if (slides.length > 10) '+${slides.length - 10} additional slides',
    ];
  }

  String _slideRoleFor(_DeckSlide slide) {
    return switch (slide.kind) {
      _DeckSlideKind.title => 'Open with audience, purpose, and evidence count',
      _DeckSlideKind.agenda => 'Set the decision path',
      _DeckSlideKind.talkTrack => 'Guide presenter framing',
      _DeckSlideKind.deliveryBrief => 'Frame outcome, proof, risk, and owner',
      _DeckSlideKind.snapshot =>
        'Summarize recommendation, risk, and next step',
      _DeckSlideKind.decisionMatrix => 'Compare decision signals and actions',
      _DeckSlideKind.stakeholderAlignment => 'Map owners to follow-up actions',
      _DeckSlideKind.dataSnapshot => 'Summarize supporting tables',
      _DeckSlideKind.takeaways => 'Highlight executive takeaways',
      _DeckSlideKind.sectionDivider => 'Separate major story sections',
      _DeckSlideKind.content => 'Explain supporting detail',
      _DeckSlideKind.recommendation => 'Show recommendation or action plan',
      _DeckSlideKind.roadmap => 'Sequence phases and verification',
      _DeckSlideKind.handoffReadiness => 'Validate external sharing readiness',
      _DeckSlideKind.publishingGate =>
        'Confirm evidence, assumptions, visual QA, and sharing gate',
      _DeckSlideKind.closing => 'Close with decision ask',
      _DeckSlideKind.table => 'Preview structured data',
      _DeckSlideKind.appendix => 'Package handoff checklist',
      _DeckSlideKind.sources => 'Document assumptions and sources',
    };
  }

  List<String> _validationGapsFor(
    ArtifactDocument document,
    Map<String, int> slideTypeCounts,
  ) {
    return [
      if (!slideTypeCounts.containsKey(_DeckSlideKind.agenda.label))
        'Agenda slide missing',
      if (!slideTypeCounts.containsKey(_DeckSlideKind.talkTrack.label))
        'Readout framing missing',
      if (!slideTypeCounts.containsKey(_DeckSlideKind.deliveryBrief.label))
        'Executive delivery brief missing',
      if (!slideTypeCounts.containsKey(_DeckSlideKind.snapshot.label))
        'Decision snapshot missing',
      if (!slideTypeCounts.containsKey(_DeckSlideKind.recommendation.label))
        'Recommendation slide missing',
      if (!slideTypeCounts.containsKey(_DeckSlideKind.decisionMatrix.label))
        'Decision matrix missing',
      if (!slideTypeCounts.containsKey(
        _DeckSlideKind.stakeholderAlignment.label,
      ))
        'Stakeholder alignment missing',
      if (!slideTypeCounts.containsKey(_DeckSlideKind.roadmap.label))
        'Roadmap slide missing',
      if (!slideTypeCounts.containsKey(_DeckSlideKind.publishingGate.label))
        'Publishing gate slide missing',
      if (!slideTypeCounts.containsKey(_DeckSlideKind.handoffReadiness.label))
        'Customer handoff readiness slide missing',
      if (!slideTypeCounts.containsKey(_DeckSlideKind.closing.label))
        'Closing decision ask missing',
      if (document.assumptions.isEmpty) 'Assumptions need confirmation',
      if (document.citations.isEmpty) 'Sources need validation',
    ];
  }

  String _deckTypeFor(ArtifactDocument document) {
    final text =
        '${document.metadata['prompt'] ?? ''} ${document.title} ${document.summary} ${document.sections.map((section) => section.title).join(' ')}'
            .toLowerCase();
    if (text.contains('implementation') || text.contains('roadmap')) {
      return 'Implementation plan deck';
    }
    if (text.contains('business case') || text.contains('value')) {
      return 'Business case deck';
    }
    if (text.contains('change summary') || text.contains('diff')) {
      return 'Change summary deck';
    }
    if (text.contains('proposal') || text.contains('customer')) {
      return 'Customer proposal deck';
    }
    if (text.contains('architecture') || text.contains('review')) {
      return 'Architecture review deck';
    }
    return 'Executive briefing deck';
  }

  String _handoffStatusFor(List<String> validationGaps) {
    if (validationGaps.isEmpty) return 'Ready for stakeholder review';
    return 'Draft - ${validationGaps.length} validation gap${validationGaps.length == 1 ? '' : 's'}';
  }

  String _decisionAskFor(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final next = _firstMatchingBullet(sections, [
      'approve',
      'decision',
      'next',
      'action',
      'owner',
    ]);
    if (next != null) return _truncate(next, 140);
    if (document.summary.isNotEmpty) {
      return 'Review the recommendation, confirm assumptions, and approve the next implementation step.';
    }
    return 'Confirm scope, owners, and validation criteria before handoff.';
  }

  List<String> _reviewChecklistFor(
    ArtifactDocument document,
    Map<String, int> slideTypeCounts,
    List<String> validationGaps,
  ) {
    return [
      'Confirm deck title, audience, and decision ask match the customer conversation.',
      if (slideTypeCounts.containsKey(_DeckSlideKind.talkTrack.label))
        'Review readout framing for account-specific phrasing.'
      else
        'Add readout framing before stakeholder review.',
      if (slideTypeCounts.containsKey(_DeckSlideKind.deliveryBrief.label))
        'Confirm executive delivery brief matches the actual customer outcome and owner.'
      else
        'Add executive delivery brief before stakeholder readout.',
      if (slideTypeCounts.containsKey(_DeckSlideKind.decisionMatrix.label))
        'Validate decision matrix signals, risk posture, and next actions.'
      else
        'Add a decision matrix before customer handoff.',
      if (document.tables.isNotEmpty)
        _tableContinuationSlideCount(document) > 0
            ? 'Review table continuation slides for row order, readability, sensitive data, and clipped values.'
            : 'Review table slides for sensitive data, stale values, and column readability.'
      else
        'Attach supporting data or explain why no data table is required.',
      if (document.assumptions.isNotEmpty)
        'Confirm assumptions with the accountable owner.'
      else
        'Capture assumptions before treating the deck as final.',
      if (document.citations.isNotEmpty)
        'Check sources and dates before sharing externally.'
      else
        'Attach sources or mark the deck as unsourced draft.',
      if (validationGaps.isNotEmpty)
        'Resolve ${validationGaps.length} validation gap${validationGaps.length == 1 ? '' : 's'} before customer handoff.',
    ];
  }

  List<String> _handoffActionsFor(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final ask = _decisionAskFor(document, sections);
    return [
      'Send deck to internal reviewer with the source artifact attached.',
      'Walk through the decision ask: $ask',
      'Capture stakeholder owner, due date, and approval status.',
      if (document.citations.isNotEmpty)
        'Keep cited sources with the handoff package.'
      else
        'Add cited evidence before external handoff.',
    ];
  }

  List<String> _visualVerificationChecklistFor(
    ArtifactDocument document,
    Map<String, int> slideTypeCounts,
  ) {
    return [
      'Open the deck at 16:9 and verify title, agenda, decision, roadmap, assumptions, sources, and appendix slides are readable.',
      'Confirm visible slide copy is audience-facing; implementation detail belongs in speaker notes or appendix slides.',
      if (slideTypeCounts.containsKey(_DeckSlideKind.table.label))
        _tableContinuationSlideCount(document) > 0
            ? 'Review table continuation slides at 16:9 and confirm row ranges, headers, and column alignment stay readable.'
            : 'Review table slides for readable row count, clipped values, and column alignment.'
      else
        'Confirm no table slide is needed, or attach the supporting data artifact.',
      if (slideTypeCounts.containsKey(_DeckSlideKind.recommendation.label))
        'Check recommendation cards fit without wrapping into neighboring content.'
      else
        'Add a recommendation slide before customer handoff.',
      if (slideTypeCounts.containsKey(_DeckSlideKind.closing.label))
        'Verify the closing decision ask is visible without opening speaker notes.'
      else
        'Add a closing decision ask slide before external sharing.',
      if (document.citations.isNotEmpty)
        'Verify source and checked-date references are legible on the assumptions/sources slide.'
      else
        'Mark the deck as draft until source evidence is attached.',
    ];
  }

  List<String> _deckEvidencePolicyFor(ArtifactDocument document) {
    return [
      'Slides are presentation guidance, not source evidence by themselves.',
      'Customer handoff requires source data, checked dates, assumptions, and owner approval.',
      if (document.citations.isNotEmpty)
        'Use the cited source list as the evidence register for external review.'
      else
        'Do not represent unsupported recommendations as validated facts.',
      if (document.assumptions.isNotEmpty)
        'Review assumptions with the accountable owner before sharing externally.'
      else
        'Capture assumptions before treating this deck as decision-ready.',
    ];
  }

  List<String> _deckPublishingMetadataFor(
    ArtifactDocument document, {
    required int deliveryReadinessScore,
    required String deliveryReadinessLevel,
    required List<String> validationGaps,
    required String evidenceConfidence,
  }) {
    return [
      'Delivery readiness: $deliveryReadinessLevel',
      'Delivery score: $deliveryReadinessScore/100',
      'Evidence confidence: $evidenceConfidence',
      'Handoff status: ${_handoffStatusFor(validationGaps)}',
      if (validationGaps.isEmpty)
        'Publishing gate: ready for reviewer approval'
      else
        'Publishing gate: resolve ${validationGaps.length} validation gap${validationGaps.length == 1 ? '' : 's'}',
      if (document.citations.isEmpty)
        'External sharing: blocked until sources are attached'
      else
        'External sharing: source list must travel with the deck',
    ];
  }

  _DeckStatusStrip _deckStatusStripFor(
    ArtifactDocument document, {
    required List<_DeckSlide> slides,
    int? deliveryReadinessScore,
    String? deliveryReadinessLevel,
    List<String>? validationGaps,
    String? evidenceConfidence,
  }) {
    final slideTypeCounts = {
      for (final slide in slides)
        slide.kind.label: slides
            .where((candidate) => candidate.kind == slide.kind)
            .length,
    };
    final gaps =
        validationGaps ?? _validationGapsFor(document, slideTypeCounts);
    final score =
        deliveryReadinessScore ??
        _deliveryReadinessScore(document, slideTypeCounts, gaps);
    final readiness = deliveryReadinessLevel ?? _deliveryReadinessLevel(score);
    final evidence = evidenceConfidence ?? _evidenceConfidenceFor(document);
    final gate = gaps.isEmpty
        ? 'Gate: reviewer approval ready'
        : 'Gate: ${gaps.length} gap${gaps.length == 1 ? '' : 's'} to resolve';
    final accent = score >= 90
        ? '7FB7B2'
        : score >= 70
        ? 'C7A77B'
        : 'D08770';
    return _DeckStatusStrip(
      labels: ['Readiness: $readiness', 'Evidence: $evidence', gate],
      accent: accent,
      foreground: score >= 90 ? '111111' : '111111',
    );
  }

  List<String> _externalHandoffManifestFor(
    ArtifactDocument document,
    List<ArtifactSection> sections, {
    required String deliveryReadinessLevel,
    required List<String> validationGaps,
    required String evidenceConfidence,
  }) {
    final publishingGate = validationGaps.isEmpty
        ? 'ready for reviewer approval'
        : 'resolve ${validationGaps.length} validation gap${validationGaps.length == 1 ? '' : 's'}';
    return [
      'Review owner: ${_primarySponsorFor(document)}',
      'Delivery readiness: $deliveryReadinessLevel',
      'Evidence status: $evidenceConfidence',
      'Publishing gate: $publishingGate',
      'Decision ask: ${_decisionAskFor(document, sections)}',
      'Source package: ${document.citations.isEmpty ? 'sources missing' : '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} attached'}',
      'Assumption package: ${document.assumptions.isEmpty ? 'assumptions missing' : '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} captured'}',
    ];
  }

  String _evidenceConfidenceFor(ArtifactDocument document) {
    if (document.citations.isNotEmpty && document.assumptions.isNotEmpty) {
      return 'High - sources and assumptions captured';
    }
    if (document.citations.isNotEmpty) {
      return 'Medium - sources captured, assumptions need owner review';
    }
    if (document.assumptions.isNotEmpty) {
      return 'Medium - assumptions captured, sources need validation';
    }
    return 'Low - sources and assumptions need validation';
  }

  int _deliveryReadinessScore(
    ArtifactDocument document,
    Map<String, int> slideTypeCounts,
    List<String> validationGaps,
  ) {
    var score = 30;
    if (slideTypeCounts.containsKey(_DeckSlideKind.agenda.label)) score += 8;
    if (slideTypeCounts.containsKey(_DeckSlideKind.talkTrack.label)) score += 8;
    if (slideTypeCounts.containsKey(_DeckSlideKind.deliveryBrief.label)) {
      score += 10;
    }
    if (slideTypeCounts.containsKey(_DeckSlideKind.snapshot.label)) score += 8;
    if (slideTypeCounts.containsKey(_DeckSlideKind.decisionMatrix.label)) {
      score += 8;
    }
    if (slideTypeCounts.containsKey(
      _DeckSlideKind.stakeholderAlignment.label,
    )) {
      score += 8;
    }
    if (slideTypeCounts.containsKey(_DeckSlideKind.roadmap.label)) score += 8;
    if (slideTypeCounts.containsKey(_DeckSlideKind.publishingGate.label)) {
      score += 4;
    }
    if (slideTypeCounts.containsKey(_DeckSlideKind.closing.label)) score += 6;
    if (document.tables.isNotEmpty) score += 4;
    if (document.assumptions.isNotEmpty) score += 4;
    if (document.citations.isNotEmpty) score += 6;
    score -= validationGaps.length * 5;
    return score.clamp(0, 100);
  }

  String _deliveryReadinessLevel(int score) {
    if (score >= 90) return 'Customer handoff ready';
    if (score >= 75) return 'Stakeholder review ready';
    if (score >= 60) return 'Internal review required';
    return 'Draft - needs evidence and owner review';
  }

  List<String> _deliveryReadinessDrivers(
    ArtifactDocument document,
    Map<String, int> slideTypeCounts,
    List<String> validationGaps,
  ) {
    final drivers = <String>[
      if (slideTypeCounts.containsKey(_DeckSlideKind.deliveryBrief.label))
        'Executive delivery brief included'
      else
        'Executive delivery brief missing',
      if (slideTypeCounts.containsKey(_DeckSlideKind.decisionMatrix.label))
        'Decision matrix included',
      if (slideTypeCounts.containsKey(
        _DeckSlideKind.stakeholderAlignment.label,
      ))
        'Stakeholder ownership lanes included',
      if (document.tables.isNotEmpty)
        '${document.tables.length} supporting table${document.tables.length == 1 ? '' : 's'} included'
      else
        'Supporting data missing',
      if (document.assumptions.isNotEmpty)
        '${document.assumptions.length} assumption${document.assumptions.length == 1 ? '' : 's'} captured'
      else
        'Assumptions missing',
      if (document.citations.isNotEmpty)
        '${document.citations.length} source item${document.citations.length == 1 ? '' : 's'} captured'
      else
        'Sources missing',
      for (final gap in validationGaps.take(3)) 'Gap: $gap',
    ];
    return drivers.toSet().take(8).toList(growable: false);
  }

  String _deckReviewPriorityFor(int score, List<String> validationGaps) {
    if (score >= 90 && validationGaps.isEmpty) {
      return 'Low - ready for stakeholder review';
    }
    if (score >= 75) return 'Medium - internal review before handoff';
    return 'High - resolve evidence and structure gaps before handoff';
  }

  List<String> _audienceHandoffNotesFor(
    ArtifactDocument document,
    List<ArtifactSection> sections,
  ) {
    final audience = _audienceFor(document);
    final ask = _decisionAskFor(document, sections);
    return [
      'Audience: $audience.',
      'Lead with: ${_communicationJobFor(document, sections)}',
      'Decision ask: $ask',
      if (document.citations.isEmpty)
        'Before external sharing: attach cited evidence or mark the deck as draft.',
      if (document.assumptions.isEmpty)
        'Before external sharing: capture accountable owners for assumptions.',
    ].take(6).toList(growable: false);
  }

  List<String> _presentationRiskFlagsFor(
    ArtifactDocument document,
    List<String> validationGaps,
  ) {
    return [
      if (document.citations.isEmpty) 'No cited sources attached',
      if (document.assumptions.isEmpty) 'No assumptions captured',
      if (document.tables.isEmpty) 'No supporting data tables',
      for (final gap in validationGaps.take(3)) gap,
    ];
  }

  bool _hasCustomerReadyStructure(Map<String, int> slideTypeCounts) {
    return slideTypeCounts.containsKey(_DeckSlideKind.title.label) &&
        slideTypeCounts.containsKey(_DeckSlideKind.agenda.label) &&
        slideTypeCounts.containsKey(_DeckSlideKind.talkTrack.label) &&
        slideTypeCounts.containsKey(_DeckSlideKind.snapshot.label) &&
        slideTypeCounts.containsKey(_DeckSlideKind.recommendation.label) &&
        slideTypeCounts.containsKey(
          _DeckSlideKind.stakeholderAlignment.label,
        ) &&
        slideTypeCounts.containsKey(_DeckSlideKind.roadmap.label) &&
        slideTypeCounts.containsKey(_DeckSlideKind.handoffReadiness.label) &&
        slideTypeCounts.containsKey(_DeckSlideKind.publishingGate.label) &&
        slideTypeCounts.containsKey(_DeckSlideKind.sources.label);
  }

  String? _firstMatchingBullet(
    List<ArtifactSection> sections,
    List<String> terms,
  ) {
    for (final section in sections) {
      final title = section.title.toLowerCase();
      final titleMatches = terms.any(title.contains);
      final candidates = [
        ...section.bullets,
        ..._sentences(section.body).take(3),
      ];
      if (titleMatches && candidates.isNotEmpty) return candidates.first;
      for (final candidate in candidates) {
        final normalized = candidate.toLowerCase();
        if (terms.any(normalized.contains)) return candidate;
      }
    }
    return null;
  }

  String _sectionEyebrow(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('recommend')) return 'Recommendation';
    if (normalized.contains('risk')) return 'Risk review';
    if (normalized.contains('next')) return 'Next steps';
    if (normalized.contains('summary')) return 'Executive summary';
    return 'Section';
  }

  _DeckSlide _sectionDivider(ArtifactSection section, List<String> bullets) {
    return _DeckSlide(
      title: section.title,
      eyebrow: _sectionEyebrow(section.title),
      kind: _DeckSlideKind.sectionDivider,
      bullets: bullets.take(2).toList(growable: false),
    );
  }

  String _contentTitle(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('recommend')) return 'Recommendations';
    if (normalized.contains('next')) return 'Next Steps';
    return title;
  }

  String _contentEyebrow(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('recommend')) return 'Recommendation slide';
    if (normalized.contains('next')) return 'Action plan';
    if (normalized.contains('risk')) return 'Risk detail';
    return 'Key points';
  }

  _DeckSlideKind _sectionKind(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('recommend') ||
        normalized.contains('next') ||
        normalized.contains('decision')) {
      return _DeckSlideKind.recommendation;
    }
    return _DeckSlideKind.content;
  }

  List<String> _recommendationBullets(String title, List<String> bullets) {
    final normalized = title.toLowerCase();
    if (!normalized.contains('recommend') && !normalized.contains('next')) {
      return bullets;
    }
    return [
      for (final bullet in bullets.take(7))
        bullet.toLowerCase().startsWith('recommend') ||
                bullet.toLowerCase().startsWith('next')
            ? bullet
            : 'Recommendation: $bullet',
    ];
  }

  Iterable<String> _sentences(String body) {
    return body
        .replaceAll('\n', ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
  }

  List<String> _tableBulletsForRows(
    List<String> headers,
    Iterable<List<String>> rows,
  ) {
    return [
      for (final row in rows.take(8))
        [
          for (var i = 0; i < row.length && i < headers.length; i++)
            '${headers[i]}: ${row[i]}',
        ].join(' | '),
    ];
  }

  List<_DeckSlide> _tableSlidesFor(ArtifactTable table) {
    if (table.rows.isEmpty) return const [];
    final headers = table.rows.first;
    final dataRows = table.rows.skip(1).toList(growable: false);
    if (dataRows.isEmpty) {
      return [
        _DeckSlide(
          title: table.title,
          eyebrow: 'Data table',
          kind: _DeckSlideKind.table,
          bullets: const ['No data rows were provided for this table.'],
          tableRows: [headers],
        ),
      ];
    }

    final slides = <_DeckSlide>[];
    final chunkCount = (dataRows.length / _tableDataRowsPerSlide).ceil();
    for (var chunkIndex = 0; chunkIndex < chunkCount; chunkIndex++) {
      final start = chunkIndex * _tableDataRowsPerSlide;
      final end = math.min(start + _tableDataRowsPerSlide, dataRows.length);
      final chunk = dataRows.sublist(start, end);
      final title = chunkCount == 1
          ? table.title
          : '${table.title} (${chunkIndex + 1}/$chunkCount)';
      slides.add(
        _DeckSlide(
          title: title,
          eyebrow: chunkIndex == 0 ? 'Data table' : 'Data table continuation',
          kind: _DeckSlideKind.table,
          bullets: [
            'Rows ${start + 1}-$end of ${dataRows.length} from ${table.title}.',
            ..._tableBulletsForRows(headers, chunk).take(3),
          ],
          tableRows: [headers, ...chunk],
        ),
      );
    }
    return slides;
  }

  int _tableContinuationSlideCount(ArtifactDocument document) {
    var count = 0;
    for (final table in document.tables.take(_maxTablesInDeck)) {
      final dataRowCount = math.max(0, table.rows.length - 1);
      if (dataRowCount <= _tableDataRowsPerSlide) continue;
      count += (dataRowCount / _tableDataRowsPerSlide).ceil() - 1;
    }
    return count;
  }

  int _tableOverflowRowCount(ArtifactDocument document) {
    return document.tables
        .take(_maxTablesInDeck)
        .map((table) => math.max(0, table.rows.length - 1))
        .where((rowCount) => rowCount > _tableDataRowsPerSlide)
        .fold<int>(
          0,
          (sum, rowCount) => sum + rowCount - _tableDataRowsPerSlide,
        );
  }

  List<String> _tableContinuationSummaries(ArtifactDocument document) {
    return [
      for (final table in document.tables.take(_maxTablesInDeck))
        if (math.max(0, table.rows.length - 1) > _tableDataRowsPerSlide)
          '${table.title}: ${math.max(0, table.rows.length - 1)} rows split across ${(math.max(0, table.rows.length - 1) / _tableDataRowsPerSlide).ceil()} slides',
    ];
  }

  Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

  String _contentTypes(int count) {
    final slides = List.generate(
      count,
      (i) =>
          '<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/custom.xml" ContentType="application/vnd.openxmlformats-officedocument.custom-properties+xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '<Override PartName="/ppt/notesMasters/notesMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
        '${List.generate(count, (i) => '<Override PartName="/ppt/notesSlides/notesSlide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>').join()}'
        '$slides</Types>';
  }

  String _rootRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties" Target="docProps/custom.xml"/>'
        '</Relationships>';
  }

  String _appXml(int slideCount) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
        '<Application>CircuitCode</Application>'
        '<PresentationFormat>On-screen Show (16:9)</PresentationFormat>'
        '<Slides>$slideCount</Slides>'
        '<Company>CircuitCode</Company>'
        '</Properties>';
  }

  String _coreXml(String title) {
    final now = DateTime.now().toUtc().toIso8601String();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${_xml(title)}</dc:title>'
        '<dc:creator>CircuitCode</dc:creator>'
        '<dc:description>Enterprise presentation artifact generated by CircuitCode.</dc:description>'
        '<cp:lastModifiedBy>CircuitCode</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>'
        '</cp:coreProperties>';
  }

  String _customXml(
    ArtifactDocument document, {
    required List<_DeckSlide> slides,
    required _DeckTheme theme,
  }) {
    final sections = document.sections.take(10).toList(growable: false);
    final slideTypeCounts = {
      for (final slide in slides)
        slide.kind.label: slides
            .where((candidate) => candidate.kind == slide.kind)
            .length,
    };
    final slideFamilies = _slideFamiliesFor(slideTypeCounts).join(', ');
    final validationGaps = _validationGapsFor(document, slideTypeCounts);
    final deliveryReadinessScore = _deliveryReadinessScore(
      document,
      slideTypeCounts,
      validationGaps,
    );
    final deliveryReadinessLevel = _deliveryReadinessLevel(
      deliveryReadinessScore,
    );
    final evidenceConfidence = _evidenceConfidenceFor(document);
    final values = <String, String>{
      'CircuitDeckQualityManifest':
          'Narrative arc, audience, decision ask, agenda, readout framing, decision support, validation, handoff.',
      'CircuitCommunicationJob': _communicationJobFor(document, sections),
      'CircuitNarrativeArc': _narrativeArcFor(document, sections),
      'CircuitDecisionAsk': _decisionAskFor(document, sections),
      'CircuitExternalHandoffManifest': _externalHandoffManifestFor(
        document,
        sections,
        deliveryReadinessLevel: deliveryReadinessLevel,
        validationGaps: validationGaps,
        evidenceConfidence: evidenceConfidence,
      ).join(' | '),
      'CircuitCustomerHandoffReadiness': _customerHandoffGateStatus(document),
      'CircuitDeckTheme': theme.label,
      'CircuitSlideFamilies': slideFamilies,
      'CircuitPublishingGate':
          'Evidence, assumptions, visual QA, decision ask, and external sharing gate included.',
      'CircuitVisibleCopyPolicy':
          'Audience-facing slide copy; presenter guidance lives in speaker notes.',
    };
    var pid = 2;
    final properties = values.entries
        .map(
          (entry) =>
              '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="${pid++}" name="${_xml(entry.key)}"><vt:lpwstr>${_xml(entry.value)}</vt:lpwstr></property>',
        )
        .join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" '
        'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        '$properties</Properties>';
  }

  String _presentation(int count) {
    final ids = List.generate(
      count,
      (i) => '<p:sldId id="${256 + i}" r:id="rId${i + 3}"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:notesMasterIdLst><p:notesMasterId r:id="rId2"/></p:notesMasterIdLst>'
        '<p:sldIdLst>$ids</p:sldIdLst><p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>'
        '<p:notesSz cx="6858000" cy="9144000"/></p:presentation>';
  }

  String _presentationRels(int count) {
    final slides = List.generate(
      count,
      (i) =>
          '<Relationship Id="rId${i + 3}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" Target="notesMasters/notesMaster1.xml"/>'
        '$slides</Relationships>';
  }

  String _slide(
    _DeckSlide slide, {
    required _DeckTheme theme,
    required _DeckStatusStrip statusStrip,
    required int slideNumber,
    required int totalSlides,
  }) {
    final titleSize = slide.kind == _DeckSlideKind.title ? 5000 : 3500;
    final bodyY = slide.kind == _DeckSlideKind.title ? 2050000 : 1720000;
    final accent = theme.accentFor(slide.kind);
    final background = theme.backgroundFor(slide.kind);
    final body = slide.tableRows.isNotEmpty
        ? _tableSlideBody(slide, bodyY: bodyY, accent: accent, theme: theme)
        : _bulletSlideBody(slide, bodyY: bodyY, theme: theme);
    final panelColor =
        slide.kind == _DeckSlideKind.title ||
            slide.kind == _DeckSlideKind.sectionDivider
        ? background
        : theme.panel;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '${_shape(id: 2, name: 'Background', x: 0, y: 0, w: 12192000, h: 6858000, color: background)}'
        '${_shape(id: 3, name: 'Accent', x: 0, y: 0, w: 145000, h: 6858000, color: accent)}'
        '${_shape(id: 8, name: 'Content panel', x: 540000, y: 1640000, w: 11100000, h: 4550000, color: panelColor)}'
        '${_shape(id: 9, name: 'Header rule', x: 600000, y: 1510000, w: 2600000, h: 28000, color: accent)}'
        '${slide.kind == _DeckSlideKind.title ? _brandPill(theme: theme, accent: accent) : ''}'
        '${_textBox(id: 4, name: 'Eyebrow', x: 600000, y: 320000, w: 6500000, h: 320000, text: _xml(slide.eyebrow), size: 1200, bold: true, color: accent)}'
        '${_textBox(id: 7, name: 'Slide type', x: 9700000, y: 340000, w: 1700000, h: 280000, text: _xml(slide.kind.label), size: 1000, bold: true, color: theme.mutedText)}'
        '${_textBox(id: 5, name: 'Title', x: 600000, y: 680000, w: 10800000, h: 900000, text: _xml(slide.title), size: titleSize, bold: true)}'
        '$body'
        '${_deckStatusStrip(statusStrip, theme: theme)}'
        '${_textBox(id: 90, name: 'Footer', x: 600000, y: 6420000, w: 7600000, h: 260000, text: 'CircuitCode - Generated artifact - ${theme.label} theme', size: 1000, bold: false, color: theme.mutedText)}'
        '${_textBox(id: 91, name: 'Slide number', x: 10450000, y: 6420000, w: 1200000, h: 260000, text: 'Slide $slideNumber of $totalSlides', size: 1000, bold: false, color: theme.mutedText)}'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
  }

  String _deckStatusStrip(
    _DeckStatusStrip status, {
    required _DeckTheme theme,
  }) {
    final parts = <String>[
      _shape(
        id: 80,
        name: 'Circuit readiness strip',
        x: 600000,
        y: 6120000,
        w: 10980000,
        h: 240000,
        color: theme.statusRail,
      ),
    ];
    const startX = 790000;
    const gap = 190000;
    const widths = [2680000, 3260000, 2860000];
    var x = startX;
    for (var i = 0; i < status.labels.take(3).length; i++) {
      final label = status.labels[i];
      final width = widths[i];
      parts
        ..add(
          _shape(
            id: 81 + (i * 3),
            name: 'Circuit readiness pill',
            x: x,
            y: 6160000,
            w: width,
            h: 160000,
            color: i == 0 ? status.accent : theme.statusPill,
          ),
        )
        ..add(
          _textBox(
            id: 82 + (i * 3),
            name: 'Circuit readiness label',
            x: x + 100000,
            y: 6180000,
            w: width - 200000,
            h: 105000,
            text: _xml(label),
            size: 760,
            bold: true,
            color: i == 0 ? status.foreground : theme.secondaryText,
          ),
        );
      x += width + gap;
    }
    return parts.join();
  }

  String _bulletSlideBody(
    _DeckSlide slide, {
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final bullets = slide.bullets
        .where((bullet) => bullet.trim().isNotEmpty)
        .take(slide.kind == _DeckSlideKind.title ? 5 : 8)
        .toList(growable: false);
    if (slide.kind == _DeckSlideKind.snapshot ||
        slide.kind == _DeckSlideKind.dataSnapshot) {
      return _tileSlideBody(
        slide,
        bullets: bullets,
        bodyY: bodyY,
        theme: theme,
      );
    }
    if (slide.kind == _DeckSlideKind.agenda) {
      return _agendaSlideBody(
        slide,
        bullets: bullets,
        bodyY: bodyY,
        theme: theme,
      );
    }
    if (slide.kind == _DeckSlideKind.recommendation) {
      return _recommendationSlideBody(
        slide,
        bullets: bullets,
        bodyY: bodyY,
        theme: theme,
      );
    }
    if (slide.kind == _DeckSlideKind.roadmap) {
      return _roadmapSlideBody(
        slide,
        bullets: bullets,
        bodyY: bodyY,
        theme: theme,
      );
    }
    if (slide.kind == _DeckSlideKind.sectionDivider) {
      return _sectionDividerSlideBody(
        slide,
        bullets: bullets,
        bodyY: bodyY,
        theme: theme,
      );
    }
    final body = bullets
        .map(
          (bullet) =>
              '<a:p><a:r><a:rPr lang="en-US" sz="${slide.kind == _DeckSlideKind.title ? 2400 : 2050}"><a:solidFill><a:srgbClr val="${theme.bodyText}"/></a:solidFill></a:rPr><a:t>${_xml(bullet)}</a:t></a:r></a:p>',
        )
        .join();
    return '<p:sp><p:nvSpPr><p:cNvPr id="6" name="Body"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="760000" y="$bodyY"/><a:ext cx="10680000" cy="4300000"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>$body</p:txBody></p:sp>';
  }

  String _brandPill({required _DeckTheme theme, required String accent}) {
    return [
      _shape(
        id: 92,
        name: 'Enterprise brand pill',
        x: 8280000,
        y: 640000,
        w: 2860000,
        h: 420000,
        color: theme.tile,
      ),
      _shape(
        id: 93,
        name: 'Enterprise brand pill accent',
        x: 8280000,
        y: 640000,
        w: 90000,
        h: 420000,
        color: accent,
      ),
      _textBox(
        id: 94,
        name: 'Enterprise brand pill label',
        x: 8460000,
        y: 748000,
        w: 2440000,
        h: 180000,
        text: 'CircuitCode enterprise artifact',
        size: 1050,
        bold: true,
        color: theme.bodyText,
      ),
    ].join();
  }

  String _tileSlideBody(
    _DeckSlide slide, {
    required List<String> bullets,
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final accent = theme.accentFor(slide.kind);
    final parts = <String>[];
    const x = 760000;
    const tileWidth = 5000000;
    const tileHeight = 880000;
    var id = 120;
    for (var i = 0; i < bullets.take(4).length; i++) {
      final bullet = bullets[i];
      final tileX = x + ((i % 2) * 5360000);
      final tileY = bodyY + ((i ~/ 2) * 1120000);
      final label = i == 0
          ? '01'
          : i == 1
          ? '02'
          : i == 2
          ? '03'
          : '04';
      parts
        ..add(
          _shape(
            id: id++,
            name: 'Insight tile',
            x: tileX,
            y: tileY,
            w: tileWidth,
            h: tileHeight,
            color: theme.tile,
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Insight number',
            x: tileX + 160000,
            y: tileY + 120000,
            w: 420000,
            h: 250000,
            text: label,
            size: 1200,
            bold: true,
            color: accent,
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Insight text',
            x: tileX + 620000,
            y: tileY + 120000,
            w: tileWidth - 820000,
            h: tileHeight - 180000,
            text: _xml(_truncate(bullet, 150)),
            size: 1350,
            bold: false,
            color: theme.bodyText,
          ),
        );
    }
    return parts.join();
  }

  String _agendaSlideBody(
    _DeckSlide slide, {
    required List<String> bullets,
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final parts = <String>[];
    const x = 760000;
    const rowWidth = 10380000;
    const rowHeight = 430000;
    var id = 170;
    for (var i = 0; i < bullets.take(7).length; i++) {
      final y = bodyY + (i * 520000);
      final number = '${i + 1}'.padLeft(2, '0');
      parts
        ..add(
          _shape(
            id: id++,
            name: 'Agenda step',
            x: x,
            y: y,
            w: rowWidth,
            h: rowHeight,
            color: i.isEven ? theme.tile : theme.panel,
          ),
        )
        ..add(
          _shape(
            id: id++,
            name: 'Agenda number rail',
            x: x,
            y: y,
            w: 520000,
            h: rowHeight,
            color: theme.accentFor(slide.kind),
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Agenda number',
            x: x + 130000,
            y: y + 94000,
            w: 320000,
            h: 220000,
            text: number,
            size: 1400,
            bold: true,
            color: theme.headerText,
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Agenda item',
            x: x + 700000,
            y: y + 90000,
            w: rowWidth - 900000,
            h: 260000,
            text: _xml(_truncate(bullets[i], 95)),
            size: 1550,
            bold: true,
            color: theme.bodyText,
          ),
        );
    }
    return parts.join();
  }

  String _recommendationSlideBody(
    _DeckSlide slide, {
    required List<String> bullets,
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final labels = ['Decision', 'Rationale', 'Validation', 'Next action'];
    final parts = <String>[];
    const x = 760000;
    const cardWidth = 5000000;
    const cardHeight = 1100000;
    var id = 220;
    for (var i = 0; i < bullets.take(4).length; i++) {
      final cardX = x + ((i % 2) * 5360000);
      final cardY = bodyY + ((i ~/ 2) * 1360000);
      parts
        ..add(
          _shape(
            id: id++,
            name: 'Recommendation card',
            x: cardX,
            y: cardY,
            w: cardWidth,
            h: cardHeight,
            color: theme.tile,
          ),
        )
        ..add(
          _shape(
            id: id++,
            name: 'Recommendation card accent',
            x: cardX,
            y: cardY,
            w: 90000,
            h: cardHeight,
            color: theme.accentFor(slide.kind),
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Recommendation label',
            x: cardX + 210000,
            y: cardY + 130000,
            w: cardWidth - 420000,
            h: 220000,
            text: labels[i],
            size: 1250,
            bold: true,
            color: theme.accentFor(slide.kind),
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Recommendation text',
            x: cardX + 210000,
            y: cardY + 420000,
            w: cardWidth - 460000,
            h: 520000,
            text: _xml(_truncate(_stripLeadLabel(bullets[i]), 150)),
            size: 1350,
            bold: false,
            color: theme.bodyText,
          ),
        );
    }
    return parts.join();
  }

  String _sectionDividerSlideBody(
    _DeckSlide slide, {
    required List<String> bullets,
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final accent = theme.accentFor(slide.kind);
    final primary = bullets.isNotEmpty
        ? _truncate(bullets.first, 130)
        : 'Review this section with the stakeholder team before moving forward.';
    final secondary = bullets.length > 1
        ? _truncate(bullets[1], 130)
        : 'Confirm assumptions, evidence, and owners for the workstream.';
    return [
      _shape(
        id: 245,
        name: 'Section divider rail',
        x: 760000,
        y: bodyY + 120000,
        w: 1750000,
        h: 2550000,
        color: accent,
      ),
      _textBox(
        id: 246,
        name: 'Section divider label',
        x: 1010000,
        y: bodyY + 420000,
        w: 1260000,
        h: 330000,
        text: 'SECTION',
        size: 1250,
        bold: true,
        color: theme.headerText,
      ),
      _textBox(
        id: 247,
        name: 'Section objective',
        x: 2850000,
        y: bodyY + 300000,
        w: 7600000,
        h: 420000,
        text: 'Section objective',
        size: 1550,
        bold: true,
        color: accent,
      ),
      _textBox(
        id: 248,
        name: 'Section objective text',
        x: 2850000,
        y: bodyY + 820000,
        w: 7600000,
        h: 520000,
        text: _xml(primary),
        size: 1700,
        bold: true,
        color: theme.bodyText,
      ),
      _shape(
        id: 249,
        name: 'Section preview card',
        x: 2850000,
        y: bodyY + 1620000,
        w: 7600000,
        h: 900000,
        color: theme.tile,
      ),
      _textBox(
        id: 250,
        name: 'Section preview label',
        x: 3090000,
        y: bodyY + 1780000,
        w: 7000000,
        h: 220000,
        text: 'What to validate',
        size: 1200,
        bold: true,
        color: accent,
      ),
      _textBox(
        id: 251,
        name: 'Section preview text',
        x: 3090000,
        y: bodyY + 2100000,
        w: 7000000,
        h: 260000,
        text: _xml(secondary),
        size: 1350,
        bold: false,
        color: theme.bodyText,
      ),
      _shape(
        id: 252,
        name: 'Section progress marker',
        x: 2850000,
        y: bodyY + 2840000,
        w: 1300000,
        h: 32000,
        color: accent,
      ),
      _shape(
        id: 253,
        name: 'Section progress marker',
        x: 4260000,
        y: bodyY + 2840000,
        w: 1300000,
        h: 32000,
        color: theme.mutedText,
      ),
      _shape(
        id: 254,
        name: 'Section progress marker',
        x: 5670000,
        y: bodyY + 2840000,
        w: 1300000,
        h: 32000,
        color: theme.mutedText,
      ),
    ].join();
  }

  String _roadmapSlideBody(
    _DeckSlide slide, {
    required List<String> bullets,
    required int bodyY,
    required _DeckTheme theme,
  }) {
    final steps = bullets.take(5).toList(growable: false);
    final parts = <String>[];
    const x = 860000;
    const y = 2850000;
    const stepWidth = 1900000;
    var id = 270;
    if (steps.length > 1) {
      parts.add(
        _shape(
          id: id++,
          name: 'Roadmap timeline',
          x: x + 420000,
          y: y + 280000,
          w: ((steps.length - 1) * stepWidth),
          h: 28000,
          color: theme.accentFor(slide.kind),
        ),
      );
    }
    for (var i = 0; i < steps.length; i++) {
      final stepX = x + (i * stepWidth);
      parts
        ..add(
          _shape(
            id: id++,
            name: 'Roadmap phase marker',
            x: stepX + 300000,
            y: y + 120000,
            w: 370000,
            h: 370000,
            color: theme.accentFor(slide.kind),
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Roadmap phase number',
            x: stepX + 390000,
            y: y + 218000,
            w: 190000,
            h: 160000,
            text: '${i + 1}',
            size: 1200,
            bold: true,
            color: theme.headerText,
          ),
        )
        ..add(
          _textBox(
            id: id++,
            name: 'Roadmap phase text',
            x: stepX,
            y: y + 700000,
            w: stepWidth - 140000,
            h: 920000,
            text: _xml(_truncate(steps[i], 95)),
            size: 1250,
            bold: false,
            color: theme.bodyText,
          ),
        );
    }
    if (steps.isEmpty) {
      return _bulletSlideBody(slide, bodyY: bodyY, theme: theme);
    }
    return parts.join();
  }

  String _tableSlideBody(
    _DeckSlide slide, {
    required int bodyY,
    required String accent,
    required _DeckTheme theme,
  }) {
    final rows = slide.tableRows.take(7).toList(growable: false);
    if (rows.isEmpty) {
      return _bulletSlideBody(slide, bodyY: bodyY, theme: theme);
    }
    final columnCount = rows
        .fold<int>(0, (max, row) => row.length > max ? row.length : max)
        .clamp(1, 5);
    const x = 760000;
    final width = 10680000 ~/ columnCount;
    const height = 430000;
    final parts = <String>[];
    var id = 20;
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
        final value = columnIndex < row.length ? row[columnIndex] : '';
        final cellX = x + (columnIndex * width);
        final cellY = bodyY + (rowIndex * height);
        final fill = rowIndex == 0
            ? accent
            : (rowIndex.isEven ? theme.tile : theme.panel);
        parts
          ..add(
            _shape(
              id: id++,
              name: 'Table cell',
              x: cellX,
              y: cellY,
              w: width - 10000,
              h: height - 10000,
              color: fill,
            ),
          )
          ..add(
            _textBox(
              id: id++,
              name: 'Table text',
              x: cellX + 90000,
              y: cellY + 60000,
              w: width - 180000,
              h: height - 90000,
              text: _xml(_truncate(value, rowIndex == 0 ? 32 : 42)),
              size: rowIndex == 0 ? 1200 : 1100,
              bold: rowIndex == 0,
              color: rowIndex == 0 ? theme.headerText : theme.bodyText,
            ),
          );
      }
    }
    if (slide.bullets.isNotEmpty) {
      parts.add(
        _textBox(
          id: id++,
          name: 'Table note',
          x: 760000,
          y: bodyY + (rows.length * height) + 160000,
          w: 10680000,
          h: 360000,
          text: _xml(_truncate(slide.bullets.first, 140)),
          size: 1200,
          bold: false,
          color: theme.secondaryText,
        ),
      );
    }
    return parts.join();
  }

  String _truncate(String value, int max) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= max) return normalized;
    return '${normalized.substring(0, max - 3)}...';
  }

  String _stripLeadLabel(String value) {
    return value.replaceFirst(
      RegExp(
        r'^\s*(recommendation|validation|next action|next step|risk):\s*',
        caseSensitive: false,
      ),
      '',
    );
  }

  String _shape({
    required int id,
    required String name,
    required int x,
    required int y,
    required int w,
    required int h,
    required String color,
  }) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="$color"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>';
  }

  String _textBox({
    required int id,
    required String name,
    required int x,
    required int y,
    required int w,
    required int h,
    required String text,
    required int size,
    required bool bold,
    String color = 'FFFFFF',
  }) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="$size"${bold ? ' b="1"' : ''}><a:solidFill><a:srgbClr val="$color"/></a:solidFill></a:rPr><a:t>$text</a:t></a:r></a:p></p:txBody></p:sp>';
  }

  String _slideRels(int slideNumber) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide$slideNumber.xml"/>'
        '</Relationships>';
  }

  String _notesSlide(_DeckSlide slide, {required int slideNumber}) {
    final notes = [
      'Presenter notes for ${slide.title}.',
      if (slide.eyebrow.isNotEmpty) 'Context: ${slide.eyebrow}.',
      for (final bullet in slide.bullets.take(5)) 'Talking point: $bullet',
      if (slide.tableRows.isNotEmpty)
        'Data note: This slide includes ${math.max(0, slide.tableRows.length - 1)} supporting row${slide.tableRows.length == 2 ? '' : 's'}.',
    ].join(' ');
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Notes Placeholder $slideNumber"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="685800" y="914400"/><a:ext cx="5486400" cy="6858000"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr wrap="square"/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="1200"><a:solidFill><a:srgbClr val="111111"/></a:solidFill></a:rPr><a:t>${_xml(_truncate(notes, 900))}</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>';
  }

  String _notesSlideRels(int slideNumber) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="../slides/slide$slideNumber.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" Target="../notesMasters/notesMaster1.xml"/>'
        '</Relationships>';
  }

  String _slideMaster() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>'
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>';
  }

  String _slideMasterRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>'
        '</Relationships>';
  }

  String _notesMaster() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="CircuitCode Notes Master"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="457200" y="457200"/><a:ext cx="5943600" cy="365760"/></a:xfrm></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="1100"><a:t>CircuitCode speaker notes</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/></p:notesMaster>';
  }

  String _notesMasterRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>'
        '</Relationships>';
  }

  String _slideLayout() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank">'
        '<p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld></p:sldLayout>';
  }

  String _slideLayoutRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>'
        '</Relationships>';
  }

  String _theme() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Circuit">'
        '<a:themeElements><a:clrScheme name="Circuit"><a:dk1><a:srgbClr val="111111"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="1F2933"/></a:dk2><a:lt2><a:srgbClr val="F3F4F6"/></a:lt2><a:accent1><a:srgbClr val="7FB7B2"/></a:accent1><a:accent2><a:srgbClr val="7A9CC6"/></a:accent2><a:accent3><a:srgbClr val="C7A77B"/></a:accent3><a:accent4><a:srgbClr val="A7C080"/></a:accent4><a:accent5><a:srgbClr val="D08770"/></a:accent5><a:accent6><a:srgbClr val="B48EAD"/></a:accent6><a:hlink><a:srgbClr val="3B82F6"/></a:hlink><a:folHlink><a:srgbClr val="7C3AED"/></a:folHlink></a:clrScheme><a:fontScheme name="Circuit"><a:majorFont><a:latin typeface="Aptos Display"/></a:majorFont><a:minorFont><a:latin typeface="Aptos"/></a:minorFont></a:fontScheme><a:fmtScheme name="Circuit"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>';
  }

  String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}

class _DeckSlide {
  final String title;
  final String eyebrow;
  final _DeckSlideKind kind;
  final List<String> bullets;
  final List<List<String>> tableRows;

  const _DeckSlide({
    required this.title,
    required this.eyebrow,
    required this.kind,
    required this.bullets,
    this.tableRows = const [],
  });
}

class _DeckStatusStrip {
  final List<String> labels;
  final String accent;
  final String foreground;

  const _DeckStatusStrip({
    required this.labels,
    required this.accent,
    required this.foreground,
  });
}

enum _DeckSlideKind {
  title,
  agenda,
  talkTrack,
  deliveryBrief,
  snapshot,
  decisionMatrix,
  stakeholderAlignment,
  dataSnapshot,
  takeaways,
  sectionDivider,
  content,
  recommendation,
  roadmap,
  closing,
  handoffReadiness,
  publishingGate,
  table,
  appendix,
  sources;

  String get label {
    return switch (this) {
      _DeckSlideKind.title => 'Title',
      _DeckSlideKind.agenda => 'Agenda',
      _DeckSlideKind.talkTrack => 'Readout',
      _DeckSlideKind.deliveryBrief => 'Delivery Brief',
      _DeckSlideKind.snapshot => 'Decision',
      _DeckSlideKind.decisionMatrix => 'Decision Matrix',
      _DeckSlideKind.stakeholderAlignment => 'Stakeholders',
      _DeckSlideKind.dataSnapshot => 'Data',
      _DeckSlideKind.takeaways => 'Takeaways',
      _DeckSlideKind.sectionDivider => 'Section',
      _DeckSlideKind.content => 'Content',
      _DeckSlideKind.recommendation => 'Recommendation',
      _DeckSlideKind.roadmap => 'Roadmap',
      _DeckSlideKind.closing => 'Close',
      _DeckSlideKind.handoffReadiness => 'Handoff Readiness',
      _DeckSlideKind.publishingGate => 'Publishing Gate',
      _DeckSlideKind.table => 'Table',
      _DeckSlideKind.appendix => 'Appendix',
      _DeckSlideKind.sources => 'Sources',
    };
  }
}

class _DeckTheme {
  final String label;
  final String canvas;
  final String panel;
  final String tile;
  final String statusRail;
  final String statusPill;
  final String bodyText;
  final String secondaryText;
  final String mutedText;
  final String headerText;

  const _DeckTheme._({
    required this.label,
    required this.canvas,
    required this.panel,
    required this.tile,
    required this.statusRail,
    required this.statusPill,
    required this.bodyText,
    required this.secondaryText,
    required this.mutedText,
    required this.headerText,
  });

  factory _DeckTheme.forDocument(ArtifactDocument document) {
    final prompt = '${document.metadata['prompt'] ?? ''}'.toLowerCase();
    final explicitTheme = '${document.metadata['theme'] ?? ''}'.toLowerCase();
    final wantsLight =
        explicitTheme.contains('light') ||
        prompt.contains('light theme') ||
        prompt.contains('white background') ||
        prompt.contains('customer-facing light');
    if (wantsLight) {
      return const _DeckTheme._(
        label: 'Light',
        canvas: 'F8FAFC',
        panel: 'FFFFFF',
        tile: 'EEF2F7',
        statusRail: 'E5E7EB',
        statusPill: 'F1F5F9',
        bodyText: '111827',
        secondaryText: '475569',
        mutedText: '64748B',
        headerText: '111111',
      );
    }
    return const _DeckTheme._(
      label: 'Dark',
      canvas: '161616',
      panel: '202020',
      tile: '242424',
      statusRail: '181818',
      statusPill: '25282C',
      bodyText: 'F4F4F5',
      secondaryText: 'C4C7CC',
      mutedText: '8A8F98',
      headerText: '111111',
    );
  }

  String accentFor(_DeckSlideKind kind) {
    return switch (kind) {
      _DeckSlideKind.title => '7FB7B2',
      _DeckSlideKind.agenda => '7A9CC6',
      _DeckSlideKind.talkTrack => '7FB7B2',
      _DeckSlideKind.deliveryBrief => 'C7A77B',
      _DeckSlideKind.snapshot => '78AAA5',
      _DeckSlideKind.dataSnapshot => 'B48EAD',
      _DeckSlideKind.takeaways => '7FB7B2',
      _DeckSlideKind.sectionDivider => 'C7A77B',
      _DeckSlideKind.recommendation => 'A7C080',
      _DeckSlideKind.decisionMatrix => '7FB7B2',
      _DeckSlideKind.stakeholderAlignment => '7A9CC6',
      _DeckSlideKind.roadmap => 'A7C080',
      _DeckSlideKind.closing => '7FB7B2',
      _DeckSlideKind.handoffReadiness => '7FB7B2',
      _DeckSlideKind.publishingGate => 'C7A77B',
      _DeckSlideKind.table => 'B48EAD',
      _DeckSlideKind.appendix => '8A8F98',
      _DeckSlideKind.sources => '7A9CC6',
      _DeckSlideKind.content => '7FB7B2',
    };
  }

  String backgroundFor(_DeckSlideKind kind) {
    if (label == 'Light') {
      return switch (kind) {
        _DeckSlideKind.title || _DeckSlideKind.sectionDivider => 'F8FAFC',
        _DeckSlideKind.snapshot ||
        _DeckSlideKind.talkTrack ||
        _DeckSlideKind.deliveryBrief ||
        _DeckSlideKind.takeaways ||
        _DeckSlideKind.decisionMatrix ||
        _DeckSlideKind.stakeholderAlignment ||
        _DeckSlideKind.handoffReadiness ||
        _DeckSlideKind.roadmap => 'F1F5F9',
        _ => canvas,
      };
    }
    return switch (kind) {
      _DeckSlideKind.title || _DeckSlideKind.sectionDivider => '111111',
      _DeckSlideKind.snapshot ||
      _DeckSlideKind.talkTrack ||
      _DeckSlideKind.deliveryBrief ||
      _DeckSlideKind.takeaways ||
      _DeckSlideKind.decisionMatrix ||
      _DeckSlideKind.stakeholderAlignment ||
      _DeckSlideKind.handoffReadiness ||
      _DeckSlideKind.roadmap => '121715',
      _ => canvas,
    };
  }
}

class _PptxFile {
  final String path;
  final Uint8List bytes;

  const _PptxFile(this.path, this.bytes);
}

Uint8List _zip(List<_PptxFile> files) {
  final output = BytesBuilder(copy: false);
  final centralDirectory = BytesBuilder(copy: false);
  var offset = 0;
  for (final file in files) {
    final nameBytes = utf8.encode(file.path);
    final crc = _crc32(file.bytes);
    final local = BytesBuilder(copy: false)
      ..add(_uint32(0x04034b50))
      ..add(_uint16(20))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint32(crc))
      ..add(_uint32(file.bytes.length))
      ..add(_uint32(file.bytes.length))
      ..add(_uint16(nameBytes.length))
      ..add(_uint16(0))
      ..add(nameBytes);
    final localBytes = local.toBytes();
    output
      ..add(localBytes)
      ..add(file.bytes);
    centralDirectory
      ..add(_uint32(0x02014b50))
      ..add(_uint16(20))
      ..add(_uint16(20))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint32(crc))
      ..add(_uint32(file.bytes.length))
      ..add(_uint32(file.bytes.length))
      ..add(_uint16(nameBytes.length))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint32(0))
      ..add(_uint32(offset))
      ..add(nameBytes);
    offset += localBytes.length + file.bytes.length;
  }
  final centralBytes = centralDirectory.toBytes();
  output
    ..add(centralBytes)
    ..add(_uint32(0x06054b50))
    ..add(_uint16(0))
    ..add(_uint16(0))
    ..add(_uint16(files.length))
    ..add(_uint16(files.length))
    ..add(_uint32(centralBytes.length))
    ..add(_uint32(offset))
    ..add(_uint16(0));
  return output.toBytes();
}

List<int> _uint16(int value) => [value & 0xff, (value >> 8) & 0xff];

List<int> _uint32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
