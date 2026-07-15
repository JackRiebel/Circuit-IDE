import '../../models/enterprise_artifact.dart';

abstract class CiscoEoxConnector {
  EnterpriseConnectorDescriptor get descriptor;

  Future<List<LifecycleRecord>> lookupByProductIds(List<String> productIds);
}

abstract class CiscoPortfolioCatalogConnector {
  EnterpriseConnectorDescriptor get descriptor;

  Future<List<ProductCandidate>> candidatesForRequirement(
    SizingRequirement requirement,
  );
}

abstract class CiscoValidatedDesignConnector {
  EnterpriseConnectorDescriptor get descriptor;

  Future<List<ArchitectureFinding>> validateTopology(NetworkTopologySpec spec);
}

abstract class WebResearchConnector {
  EnterpriseConnectorDescriptor get descriptor;

  Future<BusinessUseCaseArtifact> researchCompanyUseCases(String companyName);
}

abstract class DiagramRendererConnector {
  EnterpriseConnectorDescriptor get descriptor;

  Future<TopologyDiagramArtifact> renderTopology(NetworkTopologySpec spec);
}

abstract class ChartRendererConnector {
  EnterpriseConnectorDescriptor get descriptor;

  Future<EnterpriseArtifact> renderChart({
    required String title,
    required String summary,
    required Map<String, num> values,
  });
}

class MermaidDiagramRendererConnector implements DiagramRendererConnector {
  @override
  EnterpriseConnectorDescriptor get descriptor =>
      const EnterpriseConnectorDescriptor(
        id: 'mermaid-diagram-renderer',
        label: 'Mermaid Diagram Renderer',
        description: 'Creates Mermaid topology diagrams from typed specs.',
        requiresNetwork: false,
      );

  @override
  Future<TopologyDiagramArtifact> renderTopology(
    NetworkTopologySpec spec,
  ) async {
    final nodes = spec.sites
        .map((site) => '  ${_id(site)}["${_escape(site)}"]')
        .join('\n');
    final links = spec.links.map(_linkToMermaid).join('\n');
    final mermaid = [
      'flowchart LR',
      nodes,
      links,
    ].where((part) => part.trim().isNotEmpty).join('\n');
    return TopologyDiagramArtifact(
      spec: spec,
      mermaid: mermaid,
      assumptions: spec.assumptions,
    );
  }

  String _linkToMermaid(String link) {
    final parts = link.split(RegExp(r'\s*->\s*|\s*--\s*'));
    if (parts.length >= 2) {
      return '  ${_id(parts.first)} --> ${_id(parts[1])}';
    }
    return '  note_${link.hashCode.abs()}["${_escape(link)}"]';
  }

  String _id(String value) {
    final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    return normalized.isEmpty ? 'node' : normalized;
  }

  String _escape(String value) {
    return value.replaceAll('"', r'\"');
  }
}
