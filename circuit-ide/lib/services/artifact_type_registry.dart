import '../models/generated_artifact.dart';

class ArtifactTypeDescriptor {
  final String id;
  final String label;
  final List<GeneratedArtifactKind> supportedKinds;
  final List<String> useCases;
  final List<String> requiredInputs;
  final List<String> drawerActions;
  final List<String> verificationChecks;
  final List<GeneratedArtifactKind> packageKinds;
  final String previewSurface;

  const ArtifactTypeDescriptor({
    required this.id,
    required this.label,
    required this.supportedKinds,
    this.useCases = const [],
    this.requiredInputs = const [],
    this.drawerActions = const [
      'Open',
      'Reveal in Finder',
      'Copy path',
      'Review',
    ],
    this.verificationChecks = const [
      'Generated file exists',
      'Metadata persists',
      'Drawer preview renders',
    ],
    this.packageKinds = const [],
    this.previewSurface = 'Artifact preview',
  });

  GeneratedArtifactKind get primaryKind => supportedKinds.first;

  bool get supportsCompanionPackage => packageKinds.length > 1;
}

class ArtifactRouteDecision {
  final String prompt;
  final ArtifactTypeDescriptor? descriptor;
  final GeneratedArtifactKind? requestedKind;
  final List<GeneratedArtifactKind> targetKinds;

  const ArtifactRouteDecision({
    required this.prompt,
    required this.descriptor,
    required this.requestedKind,
    required this.targetKinds,
  });

  bool get isArtifactRequest => requestedKind != null || descriptor != null;

  bool get createsPackage => targetKinds.length > 1;

  GeneratedArtifactKind? get primaryKind =>
      targetKinds.isNotEmpty ? targetKinds.first : requestedKind;

  String get label {
    final descriptorLabel = descriptor?.label;
    if (descriptorLabel != null && descriptorLabel.isNotEmpty) {
      return descriptorLabel;
    }
    final kind = primaryKind;
    if (kind == null) return 'file';
    return _artifactKindLabel(kind);
  }

  String get contractLabel {
    if (createsPackage) return '$label package';
    return label;
  }
}

class ArtifactTypeRegistry {
  static const descriptors = <ArtifactTypeDescriptor>[
    ArtifactTypeDescriptor(
      id: 'powerpoint_deck',
      label: 'PowerPoint Deck',
      supportedKinds: [GeneratedArtifactKind.powerPoint],
      useCases: ['proposal', 'architecture review', 'business case'],
      requiredInputs: ['title', 'sections'],
      packageKinds: [
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Slide outline',
      verificationChecks: [
        'PPTX package opens/parses',
        'Slide outline metadata persists',
        'Deck readiness metadata renders',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'docx_report',
      label: 'Word / DOCX Report',
      supportedKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.markdown,
      ],
      useCases: ['architecture document', 'implementation report'],
      packageKinds: [GeneratedArtifactKind.docx, GeneratedArtifactKind.pdf],
      previewSurface: 'Report outline',
      verificationChecks: [
        'DOCX package opens/parses',
        'Report outline metadata persists',
        'Appendix and citation metadata renders',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'pdf_report',
      label: 'PDF Report',
      supportedKinds: [
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.markdown,
      ],
      useCases: ['customer handoff', 'final report'],
      previewSurface: 'PDF outline',
      verificationChecks: [
        'PDF header parses',
        'Page count metadata persists',
        'PDF outline preview renders',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'excel_workbook',
      label: 'Excel Workbook',
      supportedKinds: [GeneratedArtifactKind.excel, GeneratedArtifactKind.csv],
      useCases: ['inventory', 'sizing', 'lifecycle data'],
      requiredInputs: ['tables'],
      previewSurface: 'Workbook preview',
      verificationChecks: [
        'XLSX package opens/parses',
        'Sheet count metadata persists',
        'Table preview renders',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'csv_dataset',
      label: 'CSV Dataset',
      supportedKinds: [GeneratedArtifactKind.csv],
      useCases: ['raw export', 'data interchange'],
      requiredInputs: ['table'],
      previewSurface: 'Dataset preview',
      verificationChecks: [
        'CSV file exists',
        'Rows parse cleanly',
        'Dataset preview renders',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'network_topology_diagram',
      label: 'Network Topology Diagram',
      supportedKinds: [
        GeneratedArtifactKind.diagram,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.markdown,
      ],
      useCases: ['topology', 'architecture visual'],
      packageKinds: [
        GeneratedArtifactKind.diagram,
        GeneratedArtifactKind.markdown,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Topology readiness',
      verificationChecks: [
        'SVG root parses',
        'Editable Mermaid source is packaged',
        'Topology metadata persists',
        'Topology brief deck/report renders',
        'Readiness and assumptions preview renders',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'architecture_review_pack',
      label: 'Architecture Review Pack',
      supportedKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.powerPoint,
      ],
      useCases: ['findings', 'risks', 'recommendations'],
      packageKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Review package',
      verificationChecks: [
        'Findings matrix is present',
        'Risk and validation metadata persists',
        'Review workflow renders',
        'Architecture readout deck and PDF companion render when packaged',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'solution_sizing_workbook',
      label: 'Solution Sizing Workbook',
      supportedKinds: [GeneratedArtifactKind.excel],
      useCases: ['users', 'PoE', 'WAN', 'model sizing'],
      packageKinds: [
        GeneratedArtifactKind.excel,
        GeneratedArtifactKind.chart,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Sizing workbook',
      verificationChecks: [
        'Sizing sheets parse',
        'PoE/WAN validation metadata persists',
        'Sizing audit preview renders',
        'Sizing readout deck and PDF companion render when packaged',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'lifecycle_eox_report',
      label: 'Lifecycle / EoX Report',
      supportedKinds: [
        GeneratedArtifactKind.report,
        GeneratedArtifactKind.excel,
      ],
      useCases: ['LDOS', 'EoL', 'support risk'],
      packageKinds: [
        GeneratedArtifactKind.excel,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.json,
      ],
      previewSurface: 'Lifecycle report',
      verificationChecks: [
        'Lifecycle sheets parse',
        'EoX caveat metadata persists',
        'Replacement evidence preview renders',
        'Lifecycle readout deck renders when packaged',
        'Evidence JSON register parses',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'product_comparison_matrix',
      label: 'Product Comparison Matrix',
      supportedKinds: [GeneratedArtifactKind.excel, GeneratedArtifactKind.csv],
      useCases: ['model comparison', 'fit scoring'],
      requiredInputs: ['candidate models', 'capabilities', 'requirements'],
      packageKinds: [
        GeneratedArtifactKind.excel,
        GeneratedArtifactKind.chart,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Comparison matrix',
      verificationChecks: [
        'Comparison sheets parse',
        'Fit-score metadata persists',
        'Rejected alternatives preview renders',
        'Comparison readout deck and PDF companion render when packaged',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'business_use_case_brief',
      label: 'Business Use Case Brief',
      supportedKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.powerPoint,
      ],
      useCases: ['company research', 'use cases'],
      packageKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.chart,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Business brief package',
      verificationChecks: [
        'Brief narrative renders',
        'Use-case and evidence metadata persists',
        'Package review workflow renders',
        'PDF executive handoff renders when requested',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'implementation_plan',
      label: 'Implementation Plan',
      supportedKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.markdown,
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.powerPoint,
      ],
      useCases: ['plan mode', 'approval review'],
      packageKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Implementation plan',
      verificationChecks: [
        'Plan phases are present',
        'Verification and rollback metadata persists',
        'Approval gates preview renders',
        'Implementation readout deck and PDF companion render when packaged',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'change_summary_diff_report',
      label: 'Change Summary / Diff Report',
      supportedKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.markdown,
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.powerPoint,
      ],
      useCases: ['post-work summary', 'verification'],
      packageKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Change summary',
      verificationChecks: [
        'Changed file inventory is present',
        'Verification metadata persists',
        'Diff summary preview renders',
        'Change readout deck renders when packaged',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'chart_pack',
      label: 'Chart Pack',
      supportedKinds: [
        GeneratedArtifactKind.chart,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
      ],
      useCases: [
        'PoE budget',
        'WAN sizing',
        'lifecycle timeline',
        'product comparison',
        'cost/TCO',
        'risk scoring',
        'roadmap',
      ],
      packageKinds: [
        GeneratedArtifactKind.chart,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Chart summary',
      verificationChecks: [
        'SVG chart root parses',
        'Chart signal metadata persists',
        'Decision and threshold preview renders',
        'Chart readout deck and PDF companion render when packaged',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'evidence_pack',
      label: 'Evidence Pack',
      supportedKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.report,
        GeneratedArtifactKind.json,
        GeneratedArtifactKind.pdf,
      ],
      useCases: [
        'citations',
        'checked dates',
        'confidence',
        'visual evidence',
        'screenshot evidence',
        'UI review evidence',
      ],
      requiredInputs: [
        'claims or findings',
        'sources / checked dates',
        'assumptions',
        'screenshot metadata plus OCR, vision output, or user description for pixel-level visual claims',
      ],
      packageKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.json,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Evidence register',
      verificationChecks: [
        'Claim/source register is present',
        'Checked-date and confidence metadata persists',
        'Unsupported-claim preview renders',
        'Visual evidence trust boundary persists',
        'Evidence readout deck renders when packaged',
        'PDF handoff companion renders when requested',
      ],
    ),
  ];

  const ArtifactTypeRegistry();

  ArtifactTypeDescriptor? descriptorForId(String id) {
    for (final descriptor in descriptors) {
      if (descriptor.id == id) return descriptor;
    }
    return null;
  }

  ArtifactTypeDescriptor? descriptorForKind(GeneratedArtifactKind kind) {
    for (final descriptor in descriptors) {
      if (descriptor.supportedKinds.contains(kind)) return descriptor;
    }
    return null;
  }

  ArtifactTypeDescriptor? descriptorForPrompt(String prompt) {
    final normalized = prompt.toLowerCase();
    // Prefer the business/domain artifact over the requested export format.
    // "topology PDF" should produce a topology artifact rendered as PDF, not
    // a generic PDF report. Generic formats are resolved after domain routes.
    if (RegExp(
      r'\b(evidence pack|citation pack|source pack|source validation|claim validation|unsupported claims?|checked dates?|confidence notes?|visual evidence|screenshot evidence|screenshot review|screen capture evidence|ui evidence|ux evidence|image evidence|visual qa evidence)\b',
    ).hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'evidence_pack',
      );
    }
    if (RegExp(r'\b(sizing workbook|size|sizing)\b').hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'solution_sizing_workbook',
      );
    }
    if (RegExp(r'\b(topology|diagram|mermaid)\b').hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'network_topology_diagram',
      );
    }
    if (RegExp(
      r'\b(chart pack|charts?|graphs?|visualization|risk chart|poe budget chart|wan capacity chart|roadmap chart)\b',
    ).hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'chart_pack',
      );
    }
    if (RegExp(
      r'\b(excel workbook|xlsx workbook|spreadsheet|workbook|inventory export|tabular workbook)\b',
    ).hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'excel_workbook',
      );
    }
    if (RegExp(
      r'\b(csv dataset|csv export|comma[- ]separated|dataset export|raw dataset)\b',
    ).hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'csv_dataset',
      );
    }
    if (RegExp(r'\b(eox|eol|ldos|lifecycle)\b').hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'lifecycle_eox_report',
      );
    }
    if (RegExp(r'\b(evidence|citations?|sources?)\b').hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'evidence_pack',
      );
    }
    if (RegExp(r'\b(comparison|compare|matrix)\b').hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'product_comparison_matrix',
      );
    }
    if (RegExp(
      r'\b(business case|use cases?|company research|industry research)\b',
    ).hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'business_use_case_brief',
      );
    }
    if (RegExp(
      r'\b(architecture review|design review|review pack|risk review|findings and recommendations)\b',
    ).hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'architecture_review_pack',
      );
    }
    if (RegExp(
      r'\b(implementation plan|deployment plan|migration plan|project plan)\b',
    ).hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'implementation_plan',
      );
    }
    if (RegExp(
      r'\b(change summary|diff report|verification summary|post[- ]work summary)\b',
    ).hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'change_summary_diff_report',
      );
    }
    if (RegExp(
      r'\b(deck|slides?|powerpoint|pptx|presentation)\b',
    ).hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'powerpoint_deck',
      );
    }
    if (RegExp(
      r'\b(pdf|final handoff|customer handoff)\b',
    ).hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'pdf_report',
      );
    }
    if (RegExp(r'\b(proposal|report|brief|document)\b').hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'docx_report',
      );
    }
    return null;
  }

  ArtifactRouteDecision routeForPrompt(String prompt) {
    final descriptor = descriptorForPrompt(prompt);
    final requestedKind = detectGeneratedArtifactKind(prompt);
    return ArtifactRouteDecision(
      prompt: prompt,
      descriptor: descriptor,
      requestedKind: requestedKind,
      targetKinds: packageTargetsForPrompt(
        prompt,
        descriptor: descriptor,
        requestedKind: requestedKind,
      ),
    );
  }

  List<GeneratedArtifactKind> packageTargetsForPrompt(
    String prompt, {
    ArtifactTypeDescriptor? descriptor,
    GeneratedArtifactKind? requestedKind,
  }) {
    final resolvedDescriptor = descriptor ?? descriptorForPrompt(prompt);
    final normalized = prompt.toLowerCase();
    final primary = requestedKind ?? detectGeneratedArtifactKind(prompt);
    final requestedKinds = _explicitlyRequestedKinds(normalized);
    if (_canUseGenericMixedDeliverableRoute(resolvedDescriptor)) {
      final mixedDeliverableTargets = _mixedDeliverableTargets(
        normalized,
        requestedKinds: requestedKinds,
      );
      if (mixedDeliverableTargets.isNotEmpty) {
        return mixedDeliverableTargets;
      }
    }
    if (resolvedDescriptor?.supportsCompanionPackage == true) {
      final companionDescriptor = resolvedDescriptor!;
      final evidencePackageNeedsPdf =
          companionDescriptor.id == 'evidence_pack' &&
          _evidencePackageNeedsPdf(normalized);
      if (companionDescriptor.id == 'evidence_pack' &&
          requestedKinds.length == 1 &&
          requestedKinds.single == GeneratedArtifactKind.json &&
          !evidencePackageNeedsPdf) {
        return [GeneratedArtifactKind.json];
      }
      if (_requestsArtifactPackage(normalized) ||
          _descriptorDefaultsToPackage(companionDescriptor, normalized)) {
        if (evidencePackageNeedsPdf) {
          return _withTarget(
            companionDescriptor.packageKinds,
            GeneratedArtifactKind.pdf,
          );
        }
        return companionDescriptor.packageKinds;
      }
      final explicitKinds = companionDescriptor.packageKinds
          .where(requestedKinds.contains)
          .toList(growable: false);
      if (explicitKinds.length > 1) {
        return explicitKinds;
      }
      final explicitKind = _explicitlyRequestedKind(normalized);
      if (explicitKind != null &&
          companionDescriptor.packageKinds.contains(explicitKind)) {
        return [explicitKind];
      }
      if (evidencePackageNeedsPdf) {
        return _withTarget(
          companionDescriptor.packageKinds,
          GeneratedArtifactKind.pdf,
        );
      }
      return companionDescriptor.packageKinds;
    }
    if (resolvedDescriptor != null) {
      final explicitKinds = _explicitlyRequestedKinds(normalized)
          .where(resolvedDescriptor.supportedKinds.contains)
          .toList(growable: false);
      if (explicitKinds.isNotEmpty) {
        return [explicitKinds.first];
      }
      return [resolvedDescriptor.primaryKind];
    }
    final targets = <GeneratedArtifactKind>[];

    void add(GeneratedArtifactKind kind) {
      if (!targets.contains(kind)) targets.add(kind);
    }

    if (RegExp(
      r'\b(solution sizing|sizing workbook|sizing package|datacenter sizing|data center sizing|poe budget|wan sizing)\b',
    ).hasMatch(normalized)) {
      add(GeneratedArtifactKind.excel);
      add(GeneratedArtifactKind.chart);
    } else if (RegExp(
      r'\b(evidence pack|citation pack|source pack|source validation|claim validation|unsupported claims?|checked dates?|confidence notes?|visual evidence|screenshot evidence|screenshot review|screen capture evidence|ui evidence|ux evidence|image evidence|visual qa evidence)\b',
    ).hasMatch(normalized)) {
      add(primary ?? GeneratedArtifactKind.docx);
      add(GeneratedArtifactKind.json);
      if (normalized.contains('handoff') || normalized.contains('final')) {
        add(GeneratedArtifactKind.pdf);
      }
    } else if (RegExp(
      r'\b(product comparison|comparison matrix|model comparison|shortlist|fit score)\b',
    ).hasMatch(normalized)) {
      add(GeneratedArtifactKind.excel);
      add(GeneratedArtifactKind.chart);
    } else if (RegExp(
      r'\b(lifecycle|eox|eol|eos|ldos|replacement pid|migration pid)\b',
    ).hasMatch(normalized)) {
      add(GeneratedArtifactKind.excel);
      add(GeneratedArtifactKind.pdf);
    } else if (RegExp(
      r'\b(topology package|network topology|topology diagram|architecture diagram|diagram package)\b',
    ).hasMatch(normalized)) {
      add(GeneratedArtifactKind.diagram);
      add(GeneratedArtifactKind.pdf);
    } else if (RegExp(
      r'\b(business case|use case brief|company research|account plan|sales play|executive brief)\b',
    ).hasMatch(normalized)) {
      add(GeneratedArtifactKind.docx);
      add(GeneratedArtifactKind.powerPoint);
      add(GeneratedArtifactKind.chart);
    } else if (RegExp(
      r'\b(architecture review|design review|review pack|proposal package|customer proposal|customer handoff package)\b',
    ).hasMatch(normalized)) {
      add(primary ?? GeneratedArtifactKind.docx);
      add(GeneratedArtifactKind.powerPoint);
      add(GeneratedArtifactKind.pdf);
    } else if (RegExp(
      r'\b(implementation plan|deployment plan|migration plan|project plan)\b',
    ).hasMatch(normalized)) {
      add(primary ?? GeneratedArtifactKind.docx);
      add(GeneratedArtifactKind.powerPoint);
      add(GeneratedArtifactKind.pdf);
    } else if (RegExp(
      r'\b(change summary|diff report|verification summary|post[- ]work summary|release summary)\b',
    ).hasMatch(normalized)) {
      add(primary ?? GeneratedArtifactKind.docx);
      add(GeneratedArtifactKind.pdf);
    } else if (primary != null) {
      add(primary);
    }

    return targets;
  }
}

bool _canUseGenericMixedDeliverableRoute(ArtifactTypeDescriptor? descriptor) {
  if (descriptor == null) return true;
  return switch (descriptor.id) {
    'powerpoint_deck' || 'docx_report' || 'pdf_report' => true,
    _ => false,
  };
}

List<GeneratedArtifactKind> _mixedDeliverableTargets(
  String normalized, {
  required List<GeneratedArtifactKind> requestedKinds,
}) {
  final asksForDeck = requestedKinds.contains(GeneratedArtifactKind.powerPoint);
  final asksForReportLike = RegExp(
    r'\b(report|brief|document|docx|word doc|word document)\b',
  ).hasMatch(normalized);
  if (!asksForDeck || !asksForReportLike) return const [];

  final targets = <GeneratedArtifactKind>[GeneratedArtifactKind.powerPoint];
  final asksForPdf = requestedKinds.contains(GeneratedArtifactKind.pdf);
  final asksForEditableDocument =
      RegExp(
        r'\b(docx|word doc|word document|editable report|editable document)\b',
      ).hasMatch(normalized) ||
      !asksForPdf;
  if (requestedKinds.contains(GeneratedArtifactKind.pdf)) {
    targets.add(GeneratedArtifactKind.pdf);
  }
  if (asksForEditableDocument) {
    targets.add(GeneratedArtifactKind.docx);
  }
  if (RegExp(
    r'\b(package|pack|bundle|deliverables?|handoff set)\b',
  ).hasMatch(normalized)) {
    if (!targets.contains(GeneratedArtifactKind.pdf)) {
      targets.add(GeneratedArtifactKind.pdf);
    }
  }
  return targets;
}

List<GeneratedArtifactKind> _withTarget(
  List<GeneratedArtifactKind> kinds,
  GeneratedArtifactKind target,
) {
  if (kinds.contains(target)) return kinds;
  return [...kinds, target];
}

String _artifactKindLabel(GeneratedArtifactKind kind) {
  return switch (kind) {
    GeneratedArtifactKind.excel => 'Excel workbook',
    GeneratedArtifactKind.csv => 'CSV dataset',
    GeneratedArtifactKind.json => 'JSON artifact',
    GeneratedArtifactKind.markdown => 'Markdown document',
    GeneratedArtifactKind.pdf => 'PDF report',
    GeneratedArtifactKind.powerPoint => 'PowerPoint deck',
    GeneratedArtifactKind.docx => 'Word report',
    GeneratedArtifactKind.diagram => 'Network topology diagram',
    GeneratedArtifactKind.chart => 'Chart pack',
    GeneratedArtifactKind.report => 'Report',
  };
}

bool _requestsArtifactPackage(String normalized) {
  return RegExp(
    r'\b(package|pack|bundle|deliverables?|artifact set|handoff set|customer handoff package|proposal package|review pack)\b',
  ).hasMatch(normalized);
}

bool _descriptorDefaultsToPackage(
  ArtifactTypeDescriptor descriptor,
  String normalized,
) {
  if (descriptor.id == 'lifecycle_eox_report') {
    return RegExp(
      r'\b(report|review|status|matrix|assessment)\b',
    ).hasMatch(normalized);
  }
  if (descriptor.id == 'evidence_pack') {
    return _evidencePackageNeedsPdf(normalized);
  }
  return false;
}

bool _evidencePackageNeedsPdf(String normalized) {
  return RegExp(
    r'\b(final|handoff|customer handoff|external|share|visual evidence|screenshot evidence|screenshot review|screen capture evidence|ui evidence|ux evidence|image evidence|visual qa evidence)\b',
  ).hasMatch(normalized);
}

List<GeneratedArtifactKind> _explicitlyRequestedKinds(String normalized) {
  final kinds = <GeneratedArtifactKind>[];

  void addIf(bool condition, GeneratedArtifactKind kind) {
    if (condition && !kinds.contains(kind)) kinds.add(kind);
  }

  addIf(RegExp(r'\b(pdf)\b').hasMatch(normalized), GeneratedArtifactKind.pdf);
  addIf(RegExp(r'\b(json)\b').hasMatch(normalized), GeneratedArtifactKind.json);
  addIf(
    RegExp(r'\b(excel|xlsx|spreadsheet|workbook)\b').hasMatch(normalized),
    GeneratedArtifactKind.excel,
  );
  addIf(
    RegExp(r'\b(csv|comma[- ]separated)\b').hasMatch(normalized),
    GeneratedArtifactKind.csv,
  );
  addIf(
    RegExp(
      r'\b(powerpoint|pptx|presentation|slide deck|deck|slides?)\b',
    ).hasMatch(normalized),
    GeneratedArtifactKind.powerPoint,
  );
  addIf(
    RegExp(
      r'\b(docx|word document|word report|word doc|report|brief)\b',
    ).hasMatch(normalized),
    GeneratedArtifactKind.docx,
  );
  addIf(
    RegExp(r'\b(diagram|mermaid)\b').hasMatch(normalized),
    GeneratedArtifactKind.diagram,
  );
  addIf(
    RegExp(
      r'\b(chart|charts|graph|graphs|visualization)\b',
    ).hasMatch(normalized),
    GeneratedArtifactKind.chart,
  );
  addIf(
    RegExp(r'\b(markdown|md|readme)\b').hasMatch(normalized),
    GeneratedArtifactKind.markdown,
  );
  return kinds;
}

GeneratedArtifactKind? _explicitlyRequestedKind(String normalized) {
  final kinds = _explicitlyRequestedKinds(normalized);
  return kinds.isEmpty ? null : kinds.first;
}
