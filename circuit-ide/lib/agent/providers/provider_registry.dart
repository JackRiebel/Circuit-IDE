import '../../enums/ai_provider.dart';
import 'company_connector_provider.dart';
import 'provider_interface.dart';

/// Central provider registry for the company-only connector surface.
///
/// Direct third-party providers should not be registered here. Any model family
/// exposed to the IDE must arrive through this single Circuit provider catalog.
class ProviderRegistry {
  const ProviderRegistry();

  static const ProviderDescriptor circuitDescriptor = ProviderDescriptor(
    id: 'circuit',
    displayName: 'Circuit Company AI',
    shortName: 'Circuit',
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsNativeToolCalls: true,
      supportsModelRefresh: true,
      supportsCancellation: true,
    ),
  );

  List<ProviderDescriptor> get descriptors => const [circuitDescriptor];

  ProviderDescriptor descriptorFor(AIProviderType providerType) {
    return circuitDescriptor;
  }

  AIProvider create(AIProviderType providerType) {
    return CompanyConnectorProvider();
  }
}
