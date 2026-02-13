import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../enums/ai_provider.dart';
import '../enums/connection_status.dart';
import '../services/agent_service.dart';

final agentServiceProvider = Provider<AgentService>((ref) {
  final service = AgentService();
  ref.onDispose(() => service.dispose());
  return service;
});

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
