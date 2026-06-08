import 'cisco_provider.dart';
import 'provider_registry.dart';
import 'provider_interface.dart';

/// Company connector facade.
///
/// The transport still reuses the existing Circuit gateway implementation while
/// the app-facing provider is now explicitly company-only and registry-backed.
class CompanyConnectorProvider extends CiscoProvider {
  @override
  String get name => ProviderRegistry.circuitDescriptor.displayName;

  @override
  ProviderDescriptor get descriptor => ProviderRegistry.circuitDescriptor;
}
