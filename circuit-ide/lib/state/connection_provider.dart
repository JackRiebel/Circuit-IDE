import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../enums/ai_provider.dart';
import '../enums/connection_status.dart';
import '../agent/providers/provider_interface.dart';
import '../agent/providers/provider_registry.dart';
import '../services/agent_service.dart';

final agentServiceProvider = Provider<AgentService>((ref) {
  final service = AgentService();
  ref.onDispose(() => service.dispose());
  return service;
});

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

/// Studio-facing provider-only connection facade.
///
/// Studio turns consume this surface instead of legacy [AgentService] runtime
/// state so provider access cannot carry global chat history, approvals, or
/// processing flags into request-local Studio execution.
final studioAgentConnectionProvider =
    NotifierProvider<StudioAgentConnectionController, StudioAgentConnection>(
      StudioAgentConnectionController.new,
    );

class ConnectionStatusNotifier extends Notifier<ConnectionStatus> {
  @override
  ConnectionStatus build() => ConnectionStatus.disconnected;

  void set(ConnectionStatus status) {
    state = status;
  }
}

final connectionStatusProvider =
    NotifierProvider<ConnectionStatusNotifier, ConnectionStatus>(
      ConnectionStatusNotifier.new,
    );

class ActiveProviderTypeNotifier extends Notifier<AIProviderType> {
  @override
  AIProviderType build() => AIProviderType.cisco;

  void set(AIProviderType type) {
    state = type;
  }
}

final activeProviderTypeProvider =
    NotifierProvider<ActiveProviderTypeNotifier, AIProviderType>(
      ActiveProviderTypeNotifier.new,
    );
