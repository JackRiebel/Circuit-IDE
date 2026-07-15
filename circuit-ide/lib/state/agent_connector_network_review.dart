import '../agent/providers/provider_interface.dart';
import '../models/agent_tool_permission.dart';
import '../models/confirmation_request.dart';
import '../models/tool_call_info.dart';

/// Converts provider-declared connector origins into the existing Studio
/// approval contract. The returned policy is a fresh, request-local snapshot;
/// no approval is written into project preferences or shared provider state.
Future<ProviderConnectorNetworkPolicy> reviewProviderConnectorNetworkPolicy({
  required String requestId,
  required AIProvider provider,
  required ProviderConnectorNetworkPolicy policy,
  required Future<bool> Function(ConfirmationRequest request)
  onConfirmationNeeded,
}) async {
  if (provider is! ProviderConnectorNetworkPolicyAware) return policy;
  final policyAwareProvider = provider as ProviderConnectorNetworkPolicyAware;
  final evaluations = [
    for (final requirement in policyAwareProvider.connectorNetworkRequirements)
      (requirement: requirement, access: policy.evaluate(requirement)),
  ];
  final denied = evaluations
      .where(
        (evaluation) =>
            evaluation.access.decision == ProviderConnectorNetworkDecision.deny,
      )
      .firstOrNull;
  if (denied != null) {
    throw ProviderConnectorNetworkPolicyException(denied.access.message);
  }
  final approvals = evaluations
      .where(
        (evaluation) =>
            evaluation.access.decision == ProviderConnectorNetworkDecision.ask,
      )
      .toList(growable: false);
  if (approvals.isEmpty) return policy;

  final approvalKeys = <String>{
    for (final approval in approvals)
      if (approval.access.approvalKey != null) approval.access.approvalKey!,
  };
  if (approvalKeys.length != approvals.length) {
    throw const ProviderConnectorNetworkPolicyException(
      'Circuit connector review could not validate the configured HTTPS origin.',
    );
  }
  final sortedOrigins = approvalKeys.toList()..sort();
  final labels = approvals
      .map((approval) => approval.requirement.label)
      .toSet()
      .join(', ');
  final approvalId = '$requestId:connector-network';
  final request = ConfirmationRequest(
    id: approvalId,
    toolCall: ToolCallInfo(
      id: approvalId,
      name: 'connector_network',
      arguments: {'origins': sortedOrigins},
      requiresConfirmation: true,
    ),
    preview: 'Allow $labels for this Studio turn?',
    warnings: [
      'Project network policy requires review before Circuit connects to ${sortedOrigins.join(', ')}.',
      'Approval is scoped to this turn and expires after 5 minutes.',
    ],
    risk: ToolPermissionReason.networkRequiresReview,
    normalizedAction: 'connector-network:${sortedOrigins.join('|')}',
  );
  final approved = await onConfirmationNeeded(request);
  if (!approved) {
    throw ProviderConnectorNetworkPolicyException(
      request.isExpired
          ? 'Connector network approval expired before Circuit could connect.'
          : 'Connector network approval was declined.',
    );
  }
  return policy.approveConnectorOrigins(sortedOrigins);
}
