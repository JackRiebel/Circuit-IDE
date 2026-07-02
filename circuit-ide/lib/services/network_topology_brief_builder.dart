import '../models/artifact_document.dart';
import 'diagram_artifact_renderer.dart';

class NetworkTopologyBriefBuilder {
  final DiagramArtifactRenderer diagramRenderer;

  const NetworkTopologyBriefBuilder({
    this.diagramRenderer = const DiagramArtifactRenderer(),
  });

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(topology package|network topology|topology diagram|architecture diagram|diagram package|campus topology|wan topology)\b',
    ).hasMatch(normalized);
  }

  ArtifactDocument build({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    final diagram = diagramRenderer.render(
      document: document,
      content: content,
    );
    final spec = _map(diagram.metadata['topologySpec']);
    final summary = _map(spec['summary']);
    final inventory = _map(spec['inventory']);
    final capabilities = _map(spec['capabilities']);
    final segmentation = _listOfMaps(spec['segmentation']);
    final links = _listOfMaps(spec['links']);
    final capacityChecks = _listOfMaps(spec['capacityChecks']);
    final readinessChecks = _listOfMaps(spec['readinessChecks']);
    final handoffReadinessMatrix = _listOfMaps(spec['handoffReadinessMatrix']);
    final failureDomains = _listOfMaps(spec['failureDomains']);
    final advisories = _listOfMaps(spec['advisories']);
    final validationGaps = _stringList(spec['validationGaps']);
    final riskFlags = _stringList(spec['riskFlags']);
    final assumptions = _stringList(spec['assumptions']);

    final sections = <ArtifactSection>[
      ArtifactSection(
        title: 'Topology Executive Summary',
        body:
            '${_string(summary['type'], fallback: 'Network topology')} with ${_string(summary['nodeCount'], fallback: '${diagram.nodeCount}')} nodes and ${_string(summary['edgeCount'], fallback: '${diagram.edgeCount}')} links. '
            'Resiliency model: ${_string(summary['resiliencyModel'], fallback: 'Needs validation')}. '
            'Handoff status: ${_string(summary['handoffStatus'], fallback: _string(diagram.metadata['handoffStatus'], fallback: 'Draft - validate topology inputs'))}.',
        bullets: [
          'Sites: ${_string(summary['siteCount'], fallback: _string(diagram.metadata['siteCount'], fallback: '0'))}',
          'Switches: ${_string(inventory['switchCount'], fallback: _string(diagram.metadata['switchCount'], fallback: '0'))}',
          'Access ports: ${_string(inventory['accessPortCount'], fallback: _string(diagram.metadata['accessPortCount'], fallback: '0'))}',
          'APs: ${_string(inventory['apCount'], fallback: _string(diagram.metadata['apCount'], fallback: '0'))}',
        ],
      ),
      ArtifactSection(
        title: 'Topology Inventory',
        body:
            'Inventory counts were parsed from the topology request and should be validated against the source BOM or customer inventory before handoff.',
        bullets: [
          'MDF/core count: ${_string(inventory['mdfCount'], fallback: '0')} MDF / ${_string(inventory['coreSwitchCount'], fallback: '0')} core switches',
          'IDF/access count: ${_string(inventory['idfCount'], fallback: '0')} IDFs / ${_string(inventory['accessSwitchCount'], fallback: '0')} access switches',
          'Security edge: ${_string(inventory['firewallCount'], fallback: '0')} firewall or edge devices',
          'Wireless: ${_string(inventory['apCount'], fallback: '0')} APs',
        ],
      ),
      ArtifactSection(
        title: 'Connectivity And Validation',
        body:
            'Use the link schedule as the first review path for cabling, uplinks, routing boundaries, power, and operational ownership.',
        bullets: [
          for (final link in links.take(8))
            '${_string(link['fromLabel'], fallback: _string(link['from']))} to ${_string(link['toLabel'], fallback: _string(link['to']))}: ${_string(link['validation'], fallback: 'Confirm link ownership and monitoring.')}',
        ],
      ),
      if (segmentation.isNotEmpty)
        ArtifactSection(
          title: 'Segmentation And Policy Review',
          body:
              'Validate each VLAN, VRF, subnet, gateway, DHCP scope, and ACL boundary against customer standards before implementation.',
          bullets: [
            for (final domain in segmentation.take(8))
              '${_string(domain['name'], fallback: 'Segmentation domain')}: ${_string(domain['subnet'], fallback: _string(domain['scope'], fallback: 'subnet pending'))} - ${_string(domain['validation'], fallback: 'Confirm gateway/DHCP/ACL ownership.')}',
          ],
        ),
      ArtifactSection(
        title: 'Capacity And Readiness Checks',
        body:
            'Capacity checks capture what can be inferred from the prompt; unresolved checks should become customer discovery questions.',
        bullets: [
          for (final check in capacityChecks.take(6))
            '${_string(check['metric'])}: ${_string(check['value'])} - ${_string(check['guidance'])}',
          for (final check in readinessChecks.take(4))
            '${_string(check['check'])}: ${_string(check['state'])}',
        ],
      ),
      if (handoffReadinessMatrix.isNotEmpty)
        ArtifactSection(
          title: 'Customer Handoff Readiness',
          body:
              'Use these gates to decide whether the topology is ready for stakeholder approval, needs owner review, or should stay in discovery.',
          bullets: [
            for (final gate in handoffReadinessMatrix.take(6))
              '${_string(gate['gate'])}: ${_string(gate['status'])} - ${_string(gate['ownerAction'])}',
          ],
        ),
      ArtifactSection(
        title: 'Failure Domains And Risks',
        body:
            'Review non-ready failure domains before considering this topology customer-ready.',
        bullets: [
          for (final domain in failureDomains.where(
            (domain) => domain['ready'] != true,
          ))
            '${_string(domain['domain'])}: ${_string(domain['validation'])}',
          for (final risk in riskFlags.take(6)) risk,
        ],
      ),
      ArtifactSection(
        title: 'Assumptions And Sources',
        body:
            'Treat these assumptions as design inputs that must be confirmed before final recommendation or model selection.',
        bullets: [
          ...assumptions,
          for (final advisory in advisories.take(4))
            '${_string(advisory['topic'])}: ${_string(advisory['guidance'])}',
        ],
      ),
    ];

    final tables = <ArtifactTable>[
      ArtifactTable(
        title: 'Topology Inventory Matrix',
        rows: [
          const ['Category', 'Count', 'Review note'],
          [
            'Sites',
            _string(summary['siteCount'], fallback: '0'),
            'Confirm all branches/campuses and WAN handoffs.',
          ],
          [
            'Security edge',
            _string(inventory['firewallCount'], fallback: '0'),
            'Validate HA/warm-spare design and failover ownership.',
          ],
          [
            'MDF/core',
            _string(inventory['coreSwitchCount'], fallback: '0'),
            'Validate core redundancy and uplink model.',
          ],
          [
            'IDF/access',
            _string(inventory['accessSwitchCount'], fallback: '0'),
            'Map switches to IDFs, uplinks, and spare capacity.',
          ],
          [
            'Wireless APs',
            _string(inventory['apCount'], fallback: '0'),
            'Validate AP generation, placement, and power draw.',
          ],
        ],
      ),
      ArtifactTable(
        title: 'Link Validation Schedule',
        rows: [
          const ['From', 'To', 'Link', 'Validation'],
          for (final link in links.take(12))
            [
              _string(link['fromLabel'], fallback: _string(link['from'])),
              _string(link['toLabel'], fallback: _string(link['to'])),
              _string(link['label']),
              _string(link['validation']),
            ],
        ],
      ),
      if (segmentation.isNotEmpty)
        ArtifactTable(
          title: 'Segmentation Review Matrix',
          rows: [
            const ['Domain', 'Scope', 'Subnet', 'Validation', 'Ready'],
            for (final domain in segmentation)
              [
                _string(domain['name']),
                _string(domain['scope']),
                _string(domain['subnet'], fallback: 'Pending'),
                _string(domain['validation']),
                _string(domain['ready']),
              ],
          ],
        ),
      ArtifactTable(
        title: 'Capacity Readiness Matrix',
        rows: [
          const ['Metric', 'Value', 'Guidance', 'Ready'],
          for (final check in capacityChecks)
            [
              _string(check['metric']),
              _string(check['value']),
              _string(check['guidance']),
              _string(check['ready']),
            ],
        ],
      ),
      if (handoffReadinessMatrix.isNotEmpty)
        ArtifactTable(
          title: 'Customer Handoff Readiness Matrix',
          rows: [
            const ['Gate', 'Signal', 'Status', 'Owner Action', 'Ready'],
            for (final gate in handoffReadinessMatrix)
              [
                _string(gate['gate']),
                _string(gate['signal']),
                _string(gate['status']),
                _string(gate['ownerAction']),
                _string(gate['ready']),
              ],
          ],
        ),
      ArtifactTable(
        title: 'Failure Domain Review',
        rows: [
          const ['Domain', 'Redundancy', 'Impact', 'Validation', 'Ready'],
          for (final domain in failureDomains)
            [
              _string(domain['domain']),
              _string(domain['redundancy']),
              _string(domain['impact']),
              _string(domain['validation']),
              _string(domain['ready']),
            ],
        ],
      ),
      if (validationGaps.isNotEmpty)
        ArtifactTable(
          title: 'Validation Gaps',
          rows: [
            const ['Gap', 'Action'],
            for (final gap in validationGaps)
              [gap, 'Resolve before customer-ready handoff.'],
          ],
        ),
      ...document.tables,
    ];

    return ArtifactDocument(
      title: _title(document.title, prompt),
      summary: document.summary,
      sections: sections,
      tables: tables,
      assumptions: assumptions.isEmpty ? document.assumptions : assumptions,
      citations: document.citations,
      metadata: {
        ...document.metadata,
        'artifactTemplate': 'network_topology_brief',
        'sourcePrompt': prompt,
        'topologySpecVersion': diagram.metadata['topologySpecVersion'],
        'topologySpec': spec,
        'topologyType': diagram.metadata['topologyType'],
        'topologyReadinessScore': diagram.metadata['topologyReadinessScore'],
        'topologyReadinessLevel': diagram.metadata['topologyReadinessLevel'],
        'topologyBriefTables': tables.length,
        'topologyValidationGapCount': validationGaps.length,
        'topologyFailureDomainCount': failureDomains.length,
        'topologyCapacityCheckCount': capacityChecks.length,
        'topologyHandoffReadinessGateCount': handoffReadinessMatrix.length,
        'topologyHandoffReadinessReadyCount': handoffReadinessMatrix
            .where((gate) => gate['ready'] == true)
            .length,
        'hasTopologyHandoffReadinessMatrix': handoffReadinessMatrix.isNotEmpty,
        'topologySegmentationDomainCount': segmentation.length,
        'hasTopologySegmentationReview': segmentation.isNotEmpty,
        'topologyCapabilities': capabilities,
      },
    );
  }

  String _title(String currentTitle, String prompt) {
    final title = currentTitle.trim();
    if (title.isNotEmpty && title != 'Generated artifact') {
      return title.contains('Topology') ? title : '$title Topology Brief';
    }
    final cleaned = prompt
        .replaceAll(
          RegExp(
            r'\b(create|make|generate|build|export|save|write)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Network Topology Brief';
    final titleBase = cleaned.length > 64
        ? cleaned.substring(0, 64).trim()
        : cleaned;
    return titleBase.contains('topology') ? titleBase : '$titleBase topology';
  }

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return {
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }
    return const {};
  }

  List<Map<String, Object?>> _listOfMaps(Object? value) {
    if (value is Iterable) {
      return value
          .whereType<Map>()
          .map(
            (item) => {
              for (final entry in item.entries)
                entry.key.toString(): entry.value,
            },
          )
          .toList(growable: false);
    }
    return const [];
  }

  List<String> _stringList(Object? value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  String _string(Object? value, {String fallback = ''}) {
    final string = value?.toString().trim() ?? '';
    return string.isEmpty ? fallback : string;
  }
}
