enum AgentPreflightSeverity { info, warning, blocking }

enum AgentPreflightRecoveryAction {
  openSettings,
  reconnect,
  waitForRequest,
  waitForWorkspace,
  reduceContext,
}

class AgentPreflightIssue {
  final AgentPreflightSeverity severity;
  final String message;
  final AgentPreflightRecoveryAction? recoveryAction;

  const AgentPreflightIssue({
    required this.severity,
    required this.message,
    this.recoveryAction,
  });
}

class AgentPreflightResult {
  final List<AgentPreflightIssue> issues;
  final int estimatedTokens;
  final int contextWindow;
  final DateTime checkedAt;

  const AgentPreflightResult({
    this.issues = const [],
    this.estimatedTokens = 0,
    this.contextWindow = 120000,
    required this.checkedAt,
  });

  bool get canSend =>
      !issues.any((issue) => issue.severity == AgentPreflightSeverity.blocking);

  bool get hasWarnings =>
      issues.any((issue) => issue.severity == AgentPreflightSeverity.warning);

  AgentPreflightIssue? get primaryIssue {
    for (final issue in issues) {
      if (issue.severity == AgentPreflightSeverity.blocking) return issue;
    }
    for (final issue in issues) {
      if (issue.severity == AgentPreflightSeverity.warning) return issue;
    }
    return issues.firstOrNull;
  }

  String get statusLabel {
    if (!canSend) return 'Blocked';
    if (hasWarnings) return 'Ready with warnings';
    return 'Ready';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
