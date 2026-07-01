import '../models/generated_artifact.dart';

class ArtifactTypeDescriptor {
  final String id;
  final String label;
  final List<GeneratedArtifactKind> supportedKinds;
  final List<String> useCases;
  final List<String> requiredInputs;

  const ArtifactTypeDescriptor({
    required this.id,
    required this.label,
    required this.supportedKinds,
    this.useCases = const [],
    this.requiredInputs = const [],
  });
}

class ArtifactTypeRegistry {
  static const descriptors = <ArtifactTypeDescriptor>[
    ArtifactTypeDescriptor(
      id: 'powerpoint_deck',
      label: 'PowerPoint Deck',
      supportedKinds: [GeneratedArtifactKind.powerPoint],
      useCases: ['proposal', 'architecture review', 'business case'],
      requiredInputs: ['title', 'sections'],
    ),
    ArtifactTypeDescriptor(
      id: 'docx_report',
      label: 'Word / DOCX Report',
      supportedKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.markdown,
      ],
      useCases: ['architecture document', 'implementation report'],
    ),
    ArtifactTypeDescriptor(
      id: 'pdf_report',
      label: 'PDF Report',
      supportedKinds: [
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.markdown,
      ],
      useCases: ['customer handoff', 'final report'],
    ),
    ArtifactTypeDescriptor(
      id: 'excel_workbook',
      label: 'Excel Workbook',
      supportedKinds: [GeneratedArtifactKind.excel, GeneratedArtifactKind.csv],
      useCases: ['inventory', 'sizing', 'lifecycle data'],
      requiredInputs: ['tables'],
    ),
    ArtifactTypeDescriptor(
      id: 'csv_dataset',
      label: 'CSV Dataset',
      supportedKinds: [GeneratedArtifactKind.csv],
      useCases: ['raw export', 'data interchange'],
      requiredInputs: ['table'],
    ),
    ArtifactTypeDescriptor(
      id: 'network_topology_diagram',
      label: 'Network Topology Diagram',
      supportedKinds: [
        GeneratedArtifactKind.diagram,
        GeneratedArtifactKind.markdown,
      ],
      useCases: ['topology', 'architecture visual'],
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
    ),
    ArtifactTypeDescriptor(
      id: 'solution_sizing_workbook',
      label: 'Solution Sizing Workbook',
      supportedKinds: [GeneratedArtifactKind.excel],
      useCases: ['users', 'PoE', 'WAN', 'model sizing'],
    ),
    ArtifactTypeDescriptor(
      id: 'lifecycle_eox_report',
      label: 'Lifecycle / EoX Report',
      supportedKinds: [
        GeneratedArtifactKind.report,
        GeneratedArtifactKind.excel,
      ],
      useCases: ['LDOS', 'EoL', 'support risk'],
    ),
    ArtifactTypeDescriptor(
      id: 'product_comparison_matrix',
      label: 'Product Comparison Matrix',
      supportedKinds: [GeneratedArtifactKind.excel, GeneratedArtifactKind.csv],
      useCases: ['model comparison', 'fit scoring'],
      requiredInputs: ['candidate models', 'capabilities', 'requirements'],
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
    ),
    ArtifactTypeDescriptor(
      id: 'implementation_plan',
      label: 'Implementation Plan',
      supportedKinds: [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.markdown,
        GeneratedArtifactKind.pdf,
      ],
      useCases: ['plan mode', 'approval review'],
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
    ),
    ArtifactTypeDescriptor(
      id: 'chart_pack',
      label: 'Chart Pack',
      supportedKinds: [
        GeneratedArtifactKind.chart,
        GeneratedArtifactKind.powerPoint,
      ],
      useCases: ['timeline', 'PoE budget', 'risk scoring'],
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
    ),
  ];

  const ArtifactTypeRegistry();

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
    if (RegExp(r'\b(evidence|citations?|sources?)\b').hasMatch(normalized)) {
      return descriptors.firstWhere(
        (descriptor) => descriptor.id == 'evidence_pack',
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
