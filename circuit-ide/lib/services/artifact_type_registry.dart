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
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.pdf,
      ],
      previewSurface: 'Topology readiness',
      verificationChecks: [
        'SVG root parses',
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
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'solution_sizing_workbook',
      label: 'Solution Sizing Workbook',
      supportedKinds: [GeneratedArtifactKind.excel],
      useCases: ['users', 'PoE', 'WAN', 'model sizing'],
      packageKinds: [GeneratedArtifactKind.excel, GeneratedArtifactKind.chart],
      previewSurface: 'Sizing workbook',
      verificationChecks: [
        'Sizing sheets parse',
        'PoE/WAN validation metadata persists',
        'Sizing audit preview renders',
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
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.json,
      ],
      previewSurface: 'Lifecycle report',
      verificationChecks: [
        'Lifecycle sheets parse',
        'EoX caveat metadata persists',
        'Replacement evidence preview renders',
        'Evidence JSON register parses',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'product_comparison_matrix',
      label: 'Product Comparison Matrix',
      supportedKinds: [GeneratedArtifactKind.excel, GeneratedArtifactKind.csv],
      useCases: ['model comparison', 'fit scoring'],
      requiredInputs: ['candidate models', 'capabilities', 'requirements'],
      packageKinds: [GeneratedArtifactKind.excel, GeneratedArtifactKind.chart],
      previewSurface: 'Comparison matrix',
      verificationChecks: [
        'Comparison sheets parse',
        'Fit-score metadata persists',
        'Rejected alternatives preview renders',
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
      ],
      previewSurface: 'Business brief package',
      verificationChecks: [
        'Brief narrative renders',
        'Use-case and evidence metadata persists',
        'Package review workflow renders',
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
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'change_summary_diff_report',
      label: 'Change Summary / Diff Report',
      supportedKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.markdown,
        GeneratedArtifactKind.pdf,
      ],
      useCases: ['post-work summary', 'verification'],
      packageKinds: [GeneratedArtifactKind.docx, GeneratedArtifactKind.pdf],
      previewSurface: 'Change summary',
      verificationChecks: [
        'Changed file inventory is present',
        'Verification metadata persists',
        'Diff summary preview renders',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'chart_pack',
      label: 'Chart Pack',
      supportedKinds: [
        GeneratedArtifactKind.chart,
        GeneratedArtifactKind.powerPoint,
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
      previewSurface: 'Chart summary',
      verificationChecks: [
        'SVG chart root parses',
        'Chart signal metadata persists',
        'Decision and threshold preview renders',
      ],
    ),
    ArtifactTypeDescriptor(
      id: 'evidence_pack',
      label: 'Evidence Pack',
      supportedKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.report,
        GeneratedArtifactKind.json,
      ],
      useCases: ['citations', 'checked dates', 'confidence'],
      packageKinds: [GeneratedArtifactKind.docx, GeneratedArtifactKind.json],
      previewSurface: 'Evidence register',
      verificationChecks: [
        'Claim/source register is present',
        'Checked-date and confidence metadata persists',
        'Unsupported-claim preview renders',
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
    if (RegExp(r'\b(evidence|citations?|sources?)\b').hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'evidence_pack',
      );
    }
    if (RegExp(r'\b(eox|eol|ldos|lifecycle)\b').hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'lifecycle_eox_report',
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
    if (RegExp(r'\b(proposal|report|brief|document)\b').hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'docx_report',
      );
    }
    return null;
  }
}
