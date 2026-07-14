import 'provider_interface.dart';

/// Static Circuit connector identity and advertised capability contract.
///
/// Keeping this declarative metadata outside the transport adapter makes it
/// inspectable without constructing a Dio client or touching credentials.
abstract final class CiscoProviderDescriptor {
  static const circuit = ProviderDescriptor(
    id: 'circuit',
    displayName: 'Circuit Company AI',
    shortName: 'Circuit',
    capabilities: ProviderCapabilities(
      supportsStreaming: true,
      supportsNativeToolCalls: true,
      supportsModelRefresh: true,
      supportsCancellation: true,
      supportsImageInput: true,
      supportsJsonSchema: true,
      supportsReasoning: true,
      supportedImageMimeTypes: {'image/png', 'image/jpeg', 'image/webp'},
      maxImageBytes: 5 * 1024 * 1024,
      maxImageDimension: 2048,
    ),
    protocol: ProviderProtocol(),
  );
}
