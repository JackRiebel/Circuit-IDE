import 'turn_intent.dart';

enum ToolPermissionVerdict { allow, ask, deny }

enum ToolPermissionReason {
  readOnlyInsideWorkspace,
  writeRequiresReview,
  patchTransactionApproved,
  approvalGranted,
  commandRequiresReview,
  gitMutationRequiresReview,
  networkRequiresReview,
  mcpRequiresReview,
  pathOutsideWorkspace,
  dangerousCommand,
  secretPath,
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
  final CommandCategory commandCategory;
  final NetworkAccessKind networkAccessKind;
  final String? networkDomain;
  final McpToolRisk mcpToolRisk;
  final String? mcpToolName;

  const ToolPermissionRequest({
    required this.intent,
    required this.phase,
    this.approvalGrant = ApprovalGrant.none,
    this.hasAcceptedPlan = false,
    this.allowPatchTransaction = false,
    this.commandCategory = CommandCategory.unknown,
    this.networkAccessKind = NetworkAccessKind.none,
    this.networkDomain,
    this.mcpToolRisk = McpToolRisk.unknown,
    this.mcpToolName,
  });
}
