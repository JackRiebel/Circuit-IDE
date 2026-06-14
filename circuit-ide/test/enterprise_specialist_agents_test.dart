import 'package:circuit_ide/agent/connectors/enterprise_connectors.dart';
import 'package:circuit_ide/models/enterprise_artifact.dart';
import 'package:circuit_ide/models/specialist_agent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpecialistAgentRouter', () {
    const router = SpecialistAgentRouter();

    test('routes topology prompts to topology designer', () {
      final selection = router.route(
        'Create a topology diagram for 3 branches and dual WAN.',
      );

      expect(selection.isAuto, isTrue);
      expect(
        selection.resolvedAgentIds,
        contains(SpecialistAgentId.topologyDesigner),
      );
      expect(
        selection.resolvedAgentIds,
        contains(SpecialistAgentId.evidenceReviewer),
      );
    });

    test('routes WAN/client sizing prompts to solution sizer', () {
      final selection = router.route(
        'Size a solution for 2000 clients, 1 Gbps WAN, and UPOE access.',
      );

      expect(
        selection.resolvedAgentIds,
        contains(SpecialistAgentId.solutionSizer),
      );
    });

    test('routes lifecycle replacement prompts to lifecycle and sizing', () {
      final selection = router.route(
        'Replace these EoL switches and check LDOS, but account for Wi-Fi 7 APs.',
      );

      expect(
        selection.resolvedAgentIds,
        contains(SpecialistAgentId.lifecycleValidator),
      );
      expect(
        selection.resolvedAgentIds,
        contains(SpecialistAgentId.solutionSizer),
      );
    });

    test('routes company research prompts to business use case researcher', () {
      final selection = router.route(
        'Research Acme Corp and create business use case charts.',
      );

      expect(
        selection.resolvedAgentIds,
        contains(SpecialistAgentId.businessUseCaseResearcher),
      );
    });

    test('explicit specialist selection overrides auto routing', () {
      final selection = router.route(
        'Please make a topology diagram.',
        explicitAgentId: SpecialistAgentId.lifecycleValidator,
      );

      expect(selection.isAuto, isFalse);
      expect(
        selection.resolvedAgentIds,
        contains(SpecialistAgentId.lifecycleValidator),
      );
      expect(
        selection.resolvedAgentIds,
        isNot(contains(SpecialistAgentId.topologyDesigner)),
      );
    });
  });

  group('ReplacementRecommendationEngine', () {
    const engine = ReplacementRecommendationEngine();
    final checkedAt = DateTime(2026, 6, 12);
    const requirement = SizingRequirement(
      clientCount: 500,
      wanMbps: 1000,
      wifiGeneration: WifiGeneration.wifi7,
      powerRequirement: PowerRequirement(
        minimumStandard: PowerDeliveryStandard.upoe,
        portCount: 48,
        wattsPerPort: 45,
      ),
    );

    test('treats EoX replacement PID as a migration hint only', () {
      final recommendation = engine.recommend(
        requirement: requirement,
        migrationHint: const MigrationHint(
          sourcePid: 'OLD-SWITCH',
          suggestedMigrationPid: 'NEXT-RELEASED-SWITCH',
        ),
        checkedAt: checkedAt,
        candidates: const [
          ProductCandidate(
            pid: 'NEXT-RELEASED-SWITCH',
            name: 'Next Released Switch',
            supportedWifiGenerations: [WifiGeneration.wifi6],
            powerStandard: PowerDeliveryStandard.poePlus,
            poeBudgetWatts: 740,
            hasMultigigAccess: false,
            uplinkGbps: 10,
            sourceUrls: ['https://www.cisco.com/next'],
          ),
          ProductCandidate(
            pid: 'CURRENT-WIFI7-SWITCH',
            name: 'Current Wi-Fi 7 Ready Switch',
            supportedWifiGenerations: [WifiGeneration.wifi7],
            powerStandard: PowerDeliveryStandard.upoe,
            poeBudgetWatts: 2400,
            hasMultigigAccess: true,
            uplinkGbps: 25,
            sourceUrls: ['https://www.cisco.com/current'],
          ),
        ],
      );

      expect(recommendation.selectedCandidate?.pid, 'CURRENT-WIFI7-SWITCH');
      expect(recommendation.warnings.single, contains('treated as a hint'));
      final hinted = recommendation.evaluations.firstWhere(
        (evaluation) => evaluation.candidate.pid == 'NEXT-RELEASED-SWITCH',
      );
      expect(hinted.recommended, isFalse);
      expect(hinted.reasons.join(' '), contains('Wi-Fi 7'));
    });

    test('rejects candidates with insufficient UPOE budget', () {
      final recommendation = engine.recommend(
        requirement: requirement,
        checkedAt: checkedAt,
        candidates: const [
          ProductCandidate(
            pid: 'LOW-POWER-SWITCH',
            name: 'Low Power Switch',
            supportedWifiGenerations: [WifiGeneration.wifi7],
            powerStandard: PowerDeliveryStandard.upoe,
            poeBudgetWatts: 1200,
            hasMultigigAccess: true,
            uplinkGbps: 25,
            sourceUrls: ['https://www.cisco.com/low-power'],
          ),
        ],
      );

      expect(recommendation.hasRecommendation, isFalse);
      expect(
        recommendation.evaluations.single.reasons.join(' '),
        contains('PoE budget'),
      );
    });
  });

  test('Mermaid renderer creates a diagram with assumptions', () async {
    final renderer = MermaidDiagramRendererConnector();
    final artifact = await renderer.renderTopology(
      const NetworkTopologySpec(
        sites: ['HQ', 'Branch A'],
        links: ['HQ -> Branch A'],
        assumptions: ['Dual WAN is available at both sites.'],
      ),
    );

    expect(artifact.mermaid, contains('flowchart LR'));
    expect(artifact.mermaid, contains('HQ --> Branch_A'));
    expect(artifact.assumptions, isNotEmpty);
  });
}
