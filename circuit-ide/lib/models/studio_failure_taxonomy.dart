/// Stable, support-safe categories for user-visible turn failures.
///
/// These category names, owners, and targets are product contracts. They are
/// intentionally independent of provider-specific error strings so release
/// reports and support bundles can aggregate failures without retaining the
/// original sensitive detail.
enum StudioFailureCategory {
  provider,
  policy,
  context,
  tool,
  patch,
  command,
  persistence,
  artifact,
  ui,
  unknown,
}

class StudioFailureSlo {
  final StudioFailureCategory category;
  final String owner;
  final double minimumSuccessRate;
  final Duration maximumP95Latency;
  final Duration maximumStuckDuration;

  const StudioFailureSlo({
    required this.category,
    required this.owner,
    this.minimumSuccessRate = 0.995,
    this.maximumP95Latency = const Duration(seconds: 45),
    this.maximumStuckDuration = const Duration(minutes: 5),
  });
}

class StudioFailureTaxonomy {
  const StudioFailureTaxonomy._();

  static const targets = <StudioFailureSlo>[
    StudioFailureSlo(
      category: StudioFailureCategory.provider,
      owner: 'Runtime',
    ),
    StudioFailureSlo(category: StudioFailureCategory.policy, owner: 'Security'),
    StudioFailureSlo(category: StudioFailureCategory.context, owner: 'Context'),
    StudioFailureSlo(category: StudioFailureCategory.tool, owner: 'Runtime'),
    StudioFailureSlo(category: StudioFailureCategory.patch, owner: 'Editing'),
    StudioFailureSlo(category: StudioFailureCategory.command, owner: 'Editing'),
    StudioFailureSlo(
      category: StudioFailureCategory.persistence,
      owner: 'Platform',
    ),
    StudioFailureSlo(
      category: StudioFailureCategory.artifact,
      owner: 'Artifacts',
    ),
    StudioFailureSlo(category: StudioFailureCategory.ui, owner: 'Studio UI'),
    StudioFailureSlo(category: StudioFailureCategory.unknown, owner: 'Runtime'),
  ];

  static StudioFailureCategory? classify({
    required String statusName,
    String? error,
  }) {
    if (statusName != 'failed' && statusName != 'interrupted') return null;
    final value = error?.toLowerCase() ?? '';
    if (value.contains('permission') ||
        value.contains('approval') ||
        value.contains('policy') ||
        value.contains('denied')) {
      return StudioFailureCategory.policy;
    }
    if (value.contains('patch') ||
        value.contains('conflict') ||
        value.contains('rebase') ||
        value.contains('diff')) {
      return StudioFailureCategory.patch;
    }
    if (value.contains('command') ||
        value.contains('process') ||
        value.contains('exit code')) {
      return StudioFailureCategory.command;
    }
    if (value.contains('artifact') ||
        value.contains('render') ||
        value.contains('export')) {
      return StudioFailureCategory.artifact;
    }
    if (value.contains('persist') ||
        value.contains('storage') ||
        value.contains('journal') ||
        value.contains('json')) {
      return StudioFailureCategory.persistence;
    }
    if (value.contains('context') ||
        value.contains('workspace') ||
        value.contains('index') ||
        value.contains('attachment')) {
      return StudioFailureCategory.context;
    }
    if (value.contains('tool')) return StudioFailureCategory.tool;
    if (value.contains('widget') ||
        value.contains('ui ') ||
        value.contains('focus')) {
      return StudioFailureCategory.ui;
    }
    if (value.contains('provider') ||
        value.contains('model') ||
        value.contains('connect') ||
        value.contains('network') ||
        value.contains('timeout')) {
      return StudioFailureCategory.provider;
    }
    return StudioFailureCategory.unknown;
  }

  static StudioFailureSlo targetFor(StudioFailureCategory category) {
    return targets.firstWhere((target) => target.category == category);
  }
}
