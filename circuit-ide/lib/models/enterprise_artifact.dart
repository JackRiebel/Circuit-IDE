enum EnterpriseArtifactKind {
  topology,
  sizing,
  lifecycle,
  replacementRecommendation,
  architectureFinding,
  businessUseCase,
  evidence,
  chart,
}

enum WifiGeneration { unknown, wifi5, wifi6, wifi6e, wifi7 }

enum PowerDeliveryStandard { none, poe, poePlus, upoe, upoePlus }

extension PowerDeliveryStandardRank on PowerDeliveryStandard {
  int get rank => switch (this) {
    PowerDeliveryStandard.none => 0,
    PowerDeliveryStandard.poe => 1,
    PowerDeliveryStandard.poePlus => 2,
    PowerDeliveryStandard.upoe => 3,
    PowerDeliveryStandard.upoePlus => 4,
  };

  bool satisfies(PowerDeliveryStandard requirement) {
    return rank >= requirement.rank;
  }

  String get label => switch (this) {
    PowerDeliveryStandard.none => 'No PoE',
    PowerDeliveryStandard.poe => 'PoE',
    PowerDeliveryStandard.poePlus => 'PoE+',
    PowerDeliveryStandard.upoe => 'UPOE',
    PowerDeliveryStandard.upoePlus => 'UPOE+',
  };
}

class EnterpriseConnectorDescriptor {
  final String id;
  final String label;
  final String description;
  final bool requiresNetwork;

  const EnterpriseConnectorDescriptor({
    required this.id,
    required this.label,
    required this.description,
    this.requiresNetwork = true,
  });
}

class NetworkTopologySpec {
  final List<String> sites;
  final List<String> links;
  final List<String> assumptions;

  const NetworkTopologySpec({
    required this.sites,
    required this.links,
    this.assumptions = const [],
  });

  bool get isValid => sites.isNotEmpty && assumptions.isNotEmpty;
}

class PowerRequirement {
  final PowerDeliveryStandard minimumStandard;
  final int portCount;
  final double wattsPerPort;

  const PowerRequirement({
    required this.minimumStandard,
    required this.portCount,
    required this.wattsPerPort,
  });

  double get totalWatts => portCount * wattsPerPort;
}

class SizingRequirement {
  final int? clientCount;
  final int? wanMbps;
  final WifiGeneration wifiGeneration;
  final PowerRequirement? powerRequirement;
  final double growthFactor;

  const SizingRequirement({
    this.clientCount,
    this.wanMbps,
    this.wifiGeneration = WifiGeneration.unknown,
    this.powerRequirement,
    this.growthFactor = 1.2,
  });

  bool get needsWifi7 => wifiGeneration == WifiGeneration.wifi7;
}

class LifecycleRecord {
  final String pid;
  final DateTime? endOfSaleDate;
  final DateTime? lastDateOfSupport;
  final String? sourceUrl;
  final DateTime checkedAt;

  const LifecycleRecord({
    required this.pid,
    this.endOfSaleDate,
    this.lastDateOfSupport,
    this.sourceUrl,
    required this.checkedAt,
  });
}

class MigrationHint {
  final String sourcePid;
  final String? suggestedMigrationPid;
  final String source;

  const MigrationHint({
    required this.sourcePid,
    this.suggestedMigrationPid,
    this.source = 'Cisco EoX',
  });
}

class ProductCandidate {
  final String pid;
  final String name;
  final List<WifiGeneration> supportedWifiGenerations;
  final PowerDeliveryStandard powerStandard;
  final double poeBudgetWatts;
  final bool hasMultigigAccess;
  final double uplinkGbps;
  final LifecycleRecord? lifecycle;
  final List<String> sourceUrls;

  const ProductCandidate({
    required this.pid,
    required this.name,
    this.supportedWifiGenerations = const [],
    this.powerStandard = PowerDeliveryStandard.none,
    this.poeBudgetWatts = 0,
    this.hasMultigigAccess = false,
    this.uplinkGbps = 0,
    this.lifecycle,
    this.sourceUrls = const [],
  });

  bool get hasSourceEvidence => sourceUrls.isNotEmpty;
}

class ProductEvaluation {
  final ProductCandidate candidate;
  final bool recommended;
  final List<String> reasons;

  const ProductEvaluation({
    required this.candidate,
    required this.recommended,
    required this.reasons,
  });
}

class ReplacementRecommendation {
  final ProductCandidate? selectedCandidate;
  final MigrationHint? migrationHint;
  final List<ProductEvaluation> evaluations;
  final List<String> warnings;
  final DateTime checkedAt;

  const ReplacementRecommendation({
    this.selectedCandidate,
    this.migrationHint,
    required this.evaluations,
    required this.warnings,
    required this.checkedAt,
  });

  bool get hasRecommendation => selectedCandidate != null;
}

class ArchitectureFinding {
  final String severity;
  final String title;
  final String detail;
  final List<String> sourceUrls;

  const ArchitectureFinding({
    required this.severity,
    required this.title,
    required this.detail,
    this.sourceUrls = const [],
  });
}

class TopologyDiagramArtifact {
  final NetworkTopologySpec spec;
  final String mermaid;
  final List<String> assumptions;

  const TopologyDiagramArtifact({
    required this.spec,
    required this.mermaid,
    required this.assumptions,
  });
}

class BusinessUseCaseArtifact {
  final String companyName;
  final List<String> useCases;
  final List<String> sourceUrls;

  const BusinessUseCaseArtifact({
    required this.companyName,
    required this.useCases,
    required this.sourceUrls,
  });
}

class EvidencePack {
  final List<String> sourceUrls;
  final List<String> warnings;
  final List<String> unsupportedClaims;
  final DateTime checkedAt;

  const EvidencePack({
    this.sourceUrls = const [],
    this.warnings = const [],
    this.unsupportedClaims = const [],
    required this.checkedAt,
  });
}

class EnterpriseArtifact {
  final String id;
  final EnterpriseArtifactKind kind;
  final String title;
  final String summary;
  final List<String> sourceUrls;
  final DateTime createdAt;

  const EnterpriseArtifact({
    required this.id,
    required this.kind,
    required this.title,
    required this.summary,
    this.sourceUrls = const [],
    required this.createdAt,
  });
}

class ReplacementRecommendationEngine {
  const ReplacementRecommendationEngine();

  ReplacementRecommendation recommend({
    required SizingRequirement requirement,
    required List<ProductCandidate> candidates,
    MigrationHint? migrationHint,
    DateTime? checkedAt,
  }) {
    final evaluations = candidates
        .map((candidate) => _evaluate(candidate, requirement, migrationHint))
        .toList();
    ProductCandidate? recommended;
    for (final evaluation in evaluations) {
      if (evaluation.recommended) {
        recommended = evaluation.candidate;
        break;
      }
    }
    final warnings = <String>[
      if (migrationHint?.suggestedMigrationPid != null)
        'Cisco EoX migration PID ${migrationHint!.suggestedMigrationPid} was treated as a hint, not the final recommendation.',
      if (recommended == null)
        'No candidate satisfied all sourced capability requirements.',
      if (candidates.any((candidate) => !candidate.hasSourceEvidence))
        'One or more candidates lacked source-backed capability facts.',
    ];
    return ReplacementRecommendation(
      selectedCandidate: recommended,
      migrationHint: migrationHint,
      evaluations: evaluations,
      warnings: warnings,
      checkedAt: checkedAt ?? DateTime.now(),
    );
  }

  ProductEvaluation _evaluate(
    ProductCandidate candidate,
    SizingRequirement requirement,
    MigrationHint? migrationHint,
  ) {
    final reasons = <String>[];
    var passes = true;

    if (!candidate.hasSourceEvidence) {
      passes = false;
      reasons.add('Missing source-backed capability facts.');
    }
    if (requirement.needsWifi7 &&
        !candidate.supportedWifiGenerations.contains(WifiGeneration.wifi7)) {
      passes = false;
      reasons.add('Does not document Wi-Fi 7 support.');
    }
    final power = requirement.powerRequirement;
    if (power != null) {
      if (!candidate.powerStandard.satisfies(power.minimumStandard)) {
        passes = false;
        reasons.add(
          'Power standard ${candidate.powerStandard.label} does not satisfy ${power.minimumStandard.label}.',
        );
      }
      if (candidate.poeBudgetWatts < power.totalWatts) {
        passes = false;
        reasons.add(
          'PoE budget ${candidate.poeBudgetWatts.toStringAsFixed(0)}W is below required ${power.totalWatts.toStringAsFixed(0)}W.',
        );
      }
      if (requirement.needsWifi7 && !candidate.hasMultigigAccess) {
        passes = false;
        reasons.add('Wi-Fi 7 access design requires multigig access ports.');
      }
    }
    if (requirement.wanMbps != null &&
        candidate.uplinkGbps > 0 &&
        candidate.uplinkGbps * 1000 < requirement.wanMbps!) {
      passes = false;
      reasons.add('Uplink capacity is below requested WAN speed.');
    }
    if (migrationHint?.suggestedMigrationPid == candidate.pid) {
      reasons.add(
        'Matches Cisco EoX migration hint, but still validated against current requirements.',
      );
    }
    if (passes && reasons.isEmpty) {
      reasons.add('Satisfies current sourced sizing requirements.');
    }
    return ProductEvaluation(
      candidate: candidate,
      recommended: passes,
      reasons: reasons,
    );
  }
}
