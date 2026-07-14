import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/providers/provider_interface.dart';
import '../agent/providers/provider_registry.dart';
import '../enums/ai_provider.dart';

/// Provider-only connection state for the canonical Studio runtime.
///
/// This deliberately has no dependency on AgentService, ChatNotifier, or
/// legacy editor state. Studio can therefore use a configured provider without
/// inheriting another product surface's history or processing flags.
class StudioAgentConnection {
  final AIProvider? provider;

  const StudioAgentConnection({required this.provider});
}

class StudioAgentConnectionController extends Notifier<StudioAgentConnection> {
  final ProviderRegistry _providerRegistry = const ProviderRegistry();
  AIProvider? _provider;

  @override
  StudioAgentConnection build() {
    ref.onDispose(() {
      _provider?.disconnect();
      _provider = null;
    });
    return const StudioAgentConnection(provider: null);
  }

  Future<bool> connect({
    required AIProviderType providerType,
    required Map<String, String> credentials,
  }) async {
    final provider = _providerRegistry.create(providerType);
    try {
      await provider.connect(credentials);
      _provider?.disconnect();
      _provider = provider;
      state = StudioAgentConnection(provider: provider);
      return true;
    } catch (_) {
      provider.disconnect();
      state = const StudioAgentConnection(provider: null);
      return false;
    }
  }

  void disconnect() {
    _provider?.disconnect();
    _provider = null;
    state = const StudioAgentConnection(provider: null);
  }
}

final studioAgentConnectionProvider =
    NotifierProvider<StudioAgentConnectionController, StudioAgentConnection>(
      StudioAgentConnectionController.new,
    );
