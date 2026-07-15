import 'turn_intent.dart';

enum ToolPermissionVerdict { allow, ask, deny }

enum ToolPermissionReason {
  readOnlyInsideWorkspace,
  artifactOutputApproved,
  writeRequiresReview,
  patchTransactionApproved,
  approvalGranted,
  commandRequiresReview,
  gitMutationRequiresReview,
  networkRequiresReview,
  mcpRequiresReview,
  delegationRequiresReview,
  pathOutsideWorkspace,
  dangerousCommand,
  secretPath,
  computerUseDisabled,
  unknownTool,
}

class ToolPermissionDecision {
  final ToolPermissionVerdict verdict;
  final ToolPermissionReason reason;
  final String message;
  final bool isReadOnly;

  const ToolPermissionDecision({
    required this.verdict,
    required this.reason,
    required this.message,
    this.isReadOnly = false,
  });

  bool get allowed => verdict == ToolPermissionVerdict.allow;
  bool get requiresApproval => verdict == ToolPermissionVerdict.ask;
  bool get denied => verdict == ToolPermissionVerdict.deny;
}

enum ToolPermissionPhase { inspect, propose, apply, verify }

enum ApprovalGrant { none, once, turn }

enum CommandCategory {
  unknown,
  readOnly,
  test,
  build,
  devServer,
  git,
  install,
  network,
  compound,
  secretAccess,
  privileged,
  destructive,
}

enum NetworkAccessKind { none, localhost, privateNetwork, publicInternet }

enum McpToolRisk { unknown, readOnly, mutation }

class ToolPermissionRequest {
  final TurnIntent intent;
  final ToolPermissionPhase phase;
  final ApprovalGrant approvalGrant;
  final bool hasAcceptedPlan;
  final bool allowPatchTransaction;
  final bool allowArtifactOutput;
  final CommandCategory commandCategory;
  final NetworkAccessKind networkAccessKind;
  final String? networkDomain;
  final String networkMethod;
  final bool networkUpload;
  final bool networkFollowsRedirect;
  final bool networkUsesCredentials;
  final McpToolRisk mcpToolRisk;
  final String? mcpToolName;
  final String? approvalGrantKey;

  const ToolPermissionRequest({
    required this.intent,
    required this.phase,
    this.approvalGrant = ApprovalGrant.none,
    this.hasAcceptedPlan = false,
    this.allowPatchTransaction = false,
    this.allowArtifactOutput = false,
    this.commandCategory = CommandCategory.unknown,
    this.networkAccessKind = NetworkAccessKind.none,
    this.networkDomain,
    this.networkMethod = 'GET',
    this.networkUpload = false,
    this.networkFollowsRedirect = false,
    this.networkUsesCredentials = false,
    this.mcpToolRisk = McpToolRisk.unknown,
    this.mcpToolName,
    this.approvalGrantKey,
  });
}
