import '../models/provider_lifecycle_event.dart';
import '../services/event_bus.dart';
import 'providers/provider_interface.dart';
import 'security/agent_tool_permission_policy.dart';

class StudioAgentEnvironment {
  final AIProvider provider;
  final String model;
  final String workspaceRoot;
  final AgentToolPermissionPolicy permissionPolicy;
  final EventBus events;
  final void Function(ProviderLifecycleEvent event) onProviderEvent;

  const StudioAgentEnvironment({
    required this.provider,
    required this.model,
    required this.workspaceRoot,
    required this.permissionPolicy,
    required this.events,
    required this.onProviderEvent,
  });
}
