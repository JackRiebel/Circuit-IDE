enum ToolPermissionVerdict { allow, ask, deny }

enum ToolPermissionReason {
  readOnlyInsideWorkspace,
  writeRequiresReview,
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
