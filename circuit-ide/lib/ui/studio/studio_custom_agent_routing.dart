import '../../models/agent_config_model.dart';
import '../../models/custom_agent_routing.dart';
import '../../models/turn_intent.dart';

AgentConfigModel? customAgentForId(
  List<AgentConfigModel> configs,
  String? selectedAgentId,
) {
  if (selectedAgentId == null || selectedAgentId.trim().isEmpty) return null;
  for (final config in configs) {
    if (config.id == selectedAgentId) return config;
  }
  return null;
}

CustomAgentSelection resolveCustomAgentSelection(
  List<AgentConfigModel> configs, {
  required String requestText,
  required TurnIntent intent,
  String? explicitAgentId,
  bool auto = false,
}) {
  return const CustomAgentRouter().route(
    prompt: requestText,
    intent: intent,
    configs: configs,
    explicitAgentId: explicitAgentId,
    auto: auto,
  );
}

String? customAgentValidationError({
  required String? selectedAgentId,
  required AgentConfigModel? customAgent,
  required TurnIntent intent,
}) {
  if (selectedAgentId == null || selectedAgentId.trim().isEmpty) return null;
  if (customAgent == null) {
    return 'The selected custom agent is unavailable. Choose General or another saved agent.';
  }
  if (!customAgent.enabled) {
    return 'Custom agent "${customAgent.name}" is disabled. Review its requested capabilities in the Agent Library before using it in Studio.';
  }
  final errors = customAgent.validate();
  if (errors.isNotEmpty) {
    return 'Custom agent "${customAgent.name}" is invalid: ${errors.first}';
  }
  if (!customAgent.allowedIntents.contains(intent)) {
    return 'Custom agent "${customAgent.name}" is not allowed to run ${intent.name} turns.';
  }
  return null;
}
