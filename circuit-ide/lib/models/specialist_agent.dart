enum SpecialistAgentId {
  auto,
  topologyDesigner,
  solutionSizer,
  lifecycleValidator,
  architectureReviewer,
  businessUseCaseResearcher,
  evidenceReviewer,
}

class SpecialistAgentDescriptor {
  final SpecialistAgentId id;
  final String label;
  final String shortLabel;
  final String description;
  final List<String> keywords;

  const SpecialistAgentDescriptor({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.keywords,
  });
}

class SpecialistAgentRegistry {
  const SpecialistAgentRegistry();

  static const descriptors = <SpecialistAgentDescriptor>[
    SpecialistAgentDescriptor(
      id: SpecialistAgentId.auto,
      label: 'Auto',
      shortLabel: 'Auto',
      description: 'Route enterprise requests to the right specialist.',
      keywords: [],
    ),
    SpecialistAgentDescriptor(
      id: SpecialistAgentId.topologyDesigner,
      label: 'Topology Designer',
      shortLabel: 'Topology',
      description: 'Build network topology specs and diagrams.',
      keywords: [
        'topology',
        'diagram',
        'network map',
        'visualization',
        'site',
        'branch',
        'campus',
        'wan',
        'lan',
      ],
    ),
    SpecialistAgentDescriptor(
      id: SpecialistAgentId.solutionSizer,
      label: 'Solution Sizer',
      shortLabel: 'Sizing',
      description: 'Size architectures from clients, WAN, power, and growth.',
      keywords: [
        'size',
        'sizing',
        'clients',
        'users',
        'devices',
        'throughput',
        'bandwidth',
        'wan speed',
        'poe',
        'upoe',
        'wifi 7',
        'wi-fi 7',
        'ap',
        'model choice',
      ],
    ),
    SpecialistAgentDescriptor(
      id: SpecialistAgentId.lifecycleValidator,
      label: 'Lifecycle Validator',
      shortLabel: 'Lifecycle',
      description: 'Check EoX, EoS, EoL, LDOS, and support risk.',
      keywords: [
        'eox',
        'eol',
        'eos',
        'ldos',
        'last date of support',
        'end of sale',
        'end-of-sale',
        'replacement',
        'replace',
        'migration',
        'pid',
      ],
    ),
    SpecialistAgentDescriptor(
      id: SpecialistAgentId.architectureReviewer,
      label: 'Architecture Reviewer',
      shortLabel: 'Review',
      description: 'Validate proposed designs against architecture rules.',
      keywords: [
        'validate',
        'verify',
        'review architecture',
        'architecture review',
        'design review',
        'risk',
        'requirements',
      ],
    ),
    SpecialistAgentDescriptor(
      id: SpecialistAgentId.businessUseCaseResearcher,
      label: 'Business Use Case Researcher',
      shortLabel: 'Business',
      description: 'Research companies and create sourced business cases.',
      keywords: [
        'business case',
        'use case',
        'company',
        'customer',
        'account',
        'industry',
        'market',
        'research',
        'chart',
        'visual',
      ],
    ),
    SpecialistAgentDescriptor(
      id: SpecialistAgentId.evidenceReviewer,
      label: 'Evidence Reviewer',
      shortLabel: 'Evidence',
      description: 'Check citations, freshness, assumptions, and claims.',
      keywords: [
        'citation',
        'evidence',
        'source',
        'sources',
        'confidence',
        'assumption',
      ],
    ),
  ];

  SpecialistAgentDescriptor descriptorFor(SpecialistAgentId id) {
    return descriptors.firstWhere((descriptor) => descriptor.id == id);
  }

  List<SpecialistAgentDescriptor> get selectableDescriptors {
    return descriptors
        .where(
          (descriptor) => descriptor.id != SpecialistAgentId.evidenceReviewer,
        )
        .toList(growable: false);
  }
}

class SpecialistAgentSelection {
  final SpecialistAgentId requestedAgentId;
  final List<SpecialistAgentId> resolvedAgentIds;
  final bool isAuto;
  final String rationale;

  const SpecialistAgentSelection({
    required this.requestedAgentId,
    required this.resolvedAgentIds,
    required this.isAuto,
    required this.rationale,
  });

  bool get hasEnterpriseRouting => resolvedAgentIds.isNotEmpty;

  List<SpecialistAgentDescriptor> descriptors(
    SpecialistAgentRegistry registry,
  ) {
    return resolvedAgentIds.map(registry.descriptorFor).toList(growable: false);
  }

  String label(SpecialistAgentRegistry registry) {
    if (resolvedAgentIds.isEmpty) {
      return registry.descriptorFor(requestedAgentId).label;
    }
    return descriptors(
      registry,
    ).map((descriptor) => descriptor.label).join(' + ');
  }

  String toPromptBlock(SpecialistAgentRegistry registry) {
    final labels = label(registry);
    return [
      'Enterprise specialist routing: $labels',
      if (rationale.trim().isNotEmpty) 'Routing rationale: $rationale',
      '',
      'Enterprise evidence rules:',
      '- Cisco EoX is authoritative for lifecycle dates only.',
      '- Treat EoX replacement PIDs as migration hints, not final recommendations.',
      '- Validate replacements against current requirements such as Wi-Fi 7, UPOE/UPOE+, multigig ports, uplinks, stacking, redundancy, throughput, licensing, and expected lifecycle.',
      '- Do not recommend a product/model without sourced capability facts or clearly labeled assumptions.',
      '- Include checked date, sources, unknowns, confidence, and follow-up inputs in final enterprise outputs.',
    ].join('\n');
  }
}

class SpecialistAgentRouter {
  final SpecialistAgentRegistry registry;

  const SpecialistAgentRouter({
    this.registry = const SpecialistAgentRegistry(),
  });

  SpecialistAgentSelection route(
    String prompt, {
    SpecialistAgentId explicitAgentId = SpecialistAgentId.auto,
  }) {
    if (explicitAgentId != SpecialistAgentId.auto) {
      return SpecialistAgentSelection(
        requestedAgentId: explicitAgentId,
        resolvedAgentIds: _withEvidence([explicitAgentId]),
        isAuto: false,
        rationale:
            'User explicitly selected ${registry.descriptorFor(explicitAgentId).label}.',
      );
    }

    final normalized = prompt.toLowerCase();
    final scores = <SpecialistAgentId, int>{};
    for (final descriptor in SpecialistAgentRegistry.descriptors) {
      if (descriptor.id == SpecialistAgentId.auto ||
          descriptor.id == SpecialistAgentId.evidenceReviewer) {
        continue;
      }
      final score = descriptor.keywords
          .where((keyword) => normalized.contains(keyword))
          .length;
      if (score > 0) scores[descriptor.id] = score;
    }

    final ordered = scores.entries.toList()
      ..sort((a, b) {
        final score = b.value.compareTo(a.value);
        if (score != 0) return score;
        return a.key.index.compareTo(b.key.index);
      });
    final selected = ordered.take(3).map((entry) => entry.key).toList();

    if (selected.isEmpty) {
      return const SpecialistAgentSelection(
        requestedAgentId: SpecialistAgentId.auto,
        resolvedAgentIds: [],
        isAuto: true,
        rationale: 'No enterprise specialist routing was needed.',
      );
    }

    return SpecialistAgentSelection(
      requestedAgentId: SpecialistAgentId.auto,
      resolvedAgentIds: _withEvidence(selected),
      isAuto: true,
      rationale: 'Auto matched enterprise keywords in the prompt.',
    );
  }

  List<SpecialistAgentId> _withEvidence(List<SpecialistAgentId> selected) {
    final unique = <SpecialistAgentId>{
      ...selected,
      SpecialistAgentId.evidenceReviewer,
    }.where((id) => id != SpecialistAgentId.auto).toList();
    return unique;
  }
}
