enum AgentTaskStatus {
  queued,
  running,
  paused,
  waitingForApproval,
  completed,
  failed,
  cancelled,
}

enum AgentTaskProfile {
  investigate,
  research,
  plan,
  patch,
  review,
  verify,
  handoff,
}

/// The filesystem boundary assigned to one durable agent task.
///
/// A task starts in the current workspace unless the user explicitly selects
/// an isolated Git worktree. The worktree metadata is persisted with the task
/// so a resumed turn cannot silently fall back to a different checkout.
enum AgentTaskWorkspaceMode { currentWorkspace, isolatedWorktree }

enum AgentTaskArtifactType {
  contextPack,
  patchProposal,
  commandRun,
  checkpoint,
  verification,
  diagnostic,
}

enum AgentTaskRelationshipType { parent, child, related, supersedes }

enum WorkspacePermissionDisposition { allow, review, warn, block }

enum WorkspaceNetworkRuleDisposition { allow, ask, deny }

/// A durable, narrowly scoped public-network rule. Private, localhost, and
/// metadata-address targets are never made eligible by this configuration.
class WorkspaceNetworkRule {
  final String domain;
  final WorkspaceNetworkRuleDisposition disposition;
  final List<String> methods;
  final bool allowUpload;
  final bool allowRedirects;
  final bool allowCredentials;

  const WorkspaceNetworkRule({
    required this.domain,
    this.disposition = WorkspaceNetworkRuleDisposition.ask,
    this.methods = const ['GET'],
    this.allowUpload = false,
    this.allowRedirects = false,
    this.allowCredentials = false,
  });

  /// Normalizes a user-managed public DNS rule. Network rules intentionally
  /// never accept URLs, IP literals, localhost, or private-name suffixes: the
  /// policy evaluator must not be able to turn a project setting into an
  /// exception for a local or metadata service.
  static String? normalizePublicDomain(String value) {
    var normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || normalized.contains('://')) return null;
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final wildcard = normalized.startsWith('*.');
    final host = wildcard ? normalized.substring(2) : normalized;
    if (host.isEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.lan') ||
        host.contains(':') ||
        RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(host)) {
      return null;
    }
    final labels = host.split('.');
    if (labels.length < 2 ||
        labels.any(
          (label) =>
              label.isEmpty ||
              label.length > 63 ||
              !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
        )) {
      return null;
    }
    return wildcard ? '*.$host' : host;
  }

  Map<String, dynamic> toJson() => {
    'domain': domain,
    'disposition': disposition.name,
    'methods': methods,
    'allowUpload': allowUpload,
    'allowRedirects': allowRedirects,
    'allowCredentials': allowCredentials,
  };

  static WorkspaceNetworkRule? fromJson(Object? value) {
    if (value is! Map) return null;
    final domain = normalizePublicDomain(value['domain']?.toString() ?? '');
    if (domain == null) return null;
    return WorkspaceNetworkRule(
      domain: domain,
      disposition: WorkspaceNetworkRuleDisposition.values.firstWhere(
        (item) => item.name == value['disposition'],
        orElse: () => WorkspaceNetworkRuleDisposition.ask,
      ),
      methods:
          (value['methods'] as List?)
              ?.map((item) => item.toString().trim().toUpperCase())
              .where((item) => item.isNotEmpty)
              .toList(growable: false) ??
          const ['GET'],
      allowUpload: value['allowUpload'] == true,
      allowRedirects: value['allowRedirects'] == true,
      allowCredentials: value['allowCredentials'] == true,
    );
  }
}

enum WorkspaceToolCapability {
  readTool,
  writeTool,
  command,
  git,
  externalNetwork,
}

class AgentMascotAlias {
  final String name;

  const AgentMascotAlias(this.name);

  static const pool = [
    AgentMascotAlias('Benny'),
    AgentMascotAlias('Clark'),
    AgentMascotAlias('Staley'),
    AgentMascotAlias('Tommy'),
    AgentMascotAlias('Southpaw'),
    AgentMascotAlias('Sparky'),
    AgentMascotAlias('Skye'),
  ];
}

class AgentMascotNamePool {
  static String aliasForIndex(int index) {
    final base =
        AgentMascotAlias.pool[index % AgentMascotAlias.pool.length].name;
    final cycle = index ~/ AgentMascotAlias.pool.length;
    return cycle == 0 ? base : '$base ${cycle + 1}';
  }
}

/// Persisted user preferences for an agent workspace.
///
/// This is intentionally not an evaluator. Studio execution decisions are made
/// only by `agent/security/agent_tool_permission_policy.dart`.
class WorkspacePermissionConfiguration {
  final WorkspacePermissionDisposition readTools;
  final WorkspacePermissionDisposition writeTools;
  final WorkspacePermissionDisposition commands;
  final WorkspacePermissionDisposition gitActions;
  final WorkspacePermissionDisposition externalNetwork;
  final List<WorkspaceNetworkRule> networkRules;

  const WorkspacePermissionConfiguration({
    this.readTools = WorkspacePermissionDisposition.allow,
    this.writeTools = WorkspacePermissionDisposition.review,
    this.commands = WorkspacePermissionDisposition.review,
    this.gitActions = WorkspacePermissionDisposition.review,
    this.externalNetwork = WorkspacePermissionDisposition.block,
    this.networkRules = const [],
  });

  WorkspacePermissionConfiguration copyWith({
    WorkspacePermissionDisposition? readTools,
    WorkspacePermissionDisposition? writeTools,
    WorkspacePermissionDisposition? commands,
    WorkspacePermissionDisposition? gitActions,
    WorkspacePermissionDisposition? externalNetwork,
    List<WorkspaceNetworkRule>? networkRules,
  }) {
    return WorkspacePermissionConfiguration(
      readTools: readTools ?? this.readTools,
      writeTools: writeTools ?? this.writeTools,
      commands: commands ?? this.commands,
      gitActions: gitActions ?? this.gitActions,
      externalNetwork: externalNetwork ?? this.externalNetwork,
      networkRules: networkRules ?? this.networkRules,
    );
  }

  WorkspacePermissionDisposition dispositionFor(
    WorkspaceToolCapability target,
  ) {
    return switch (target) {
      WorkspaceToolCapability.readTool => readTools,
      WorkspaceToolCapability.writeTool => writeTools,
      WorkspaceToolCapability.command => commands,
      WorkspaceToolCapability.git => gitActions,
      WorkspaceToolCapability.externalNetwork => externalNetwork,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'readTools': readTools.name,
      'writeTools': writeTools.name,
      'commands': commands.name,
      'gitActions': gitActions.name,
      'externalNetwork': externalNetwork.name,
      'networkRules': networkRules.map((rule) => rule.toJson()).toList(),
    };
  }

  static WorkspacePermissionConfiguration fromJson(Map<String, dynamic>? json) {
    if (json == null) return const WorkspacePermissionConfiguration();
    return WorkspacePermissionConfiguration(
      readTools: _disposition(json['readTools']),
      writeTools: _disposition(json['writeTools']),
      commands: _disposition(json['commands']),
      gitActions: _disposition(json['gitActions']),
      externalNetwork: _disposition(json['externalNetwork']),
      networkRules:
          (json['networkRules'] as List?)
              ?.map(WorkspaceNetworkRule.fromJson)
              .whereType<WorkspaceNetworkRule>()
              .toList(growable: false) ??
          const [],
    );
  }

  static WorkspacePermissionDisposition _disposition(dynamic value) {
    return WorkspacePermissionDisposition.values.firstWhere(
      (disposition) => disposition.name == value,
      orElse: () => WorkspacePermissionDisposition.review,
    );
  }
}

class AgentTaskProfileSpec {
  final AgentTaskProfile profile;
  final String label;
  final String description;
  final WorkspacePermissionConfiguration policy;
  final String expectedOutput;

  const AgentTaskProfileSpec({
    required this.profile,
    required this.label,
    required this.description,
    required this.policy,
    required this.expectedOutput,
  });

  static const builtIns = [
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.investigate,
      label: 'Investigate',
      description: 'Explore the project and report findings.',
      policy: WorkspacePermissionConfiguration(
        commands: WorkspacePermissionDisposition.warn,
      ),
      expectedOutput: 'Findings, risks, and next actions.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.research,
      label: 'Research',
      description:
          'Collect and compare approved web evidence in the background.',
      policy: WorkspacePermissionConfiguration(
        readTools: WorkspacePermissionDisposition.block,
        writeTools: WorkspacePermissionDisposition.block,
        commands: WorkspacePermissionDisposition.block,
        gitActions: WorkspacePermissionDisposition.block,
      ),
      expectedOutput:
          'A concise cited answer and a reviewable evidence artifact.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.plan,
      label: 'Plan',
      description: 'Turn a goal into a safe implementation plan.',
      policy: WorkspacePermissionConfiguration(),
      expectedOutput: 'A short plan with verification steps.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.patch,
      label: 'Patch',
      description: 'Prepare a reviewed patch proposal.',
      policy: WorkspacePermissionConfiguration(),
      expectedOutput: 'Patch proposal and rationale.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.review,
      label: 'Review',
      description: 'Review current changes and identify issues.',
      policy: WorkspacePermissionConfiguration(
        commands: WorkspacePermissionDisposition.warn,
      ),
      expectedOutput: 'Findings ordered by severity.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.verify,
      label: 'Verify',
      description: 'Suggest and prepare verification commands.',
      policy: WorkspacePermissionConfiguration(
        commands: WorkspacePermissionDisposition.review,
      ),
      expectedOutput: 'Checks to run and expected signal.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.handoff,
      label: 'Handoff',
      description: 'Create a concise work summary.',
      policy: WorkspacePermissionConfiguration(),
      expectedOutput: 'Files, tests, risks, and next steps.',
    ),
  ];

  static AgentTaskProfileSpec forProfile(AgentTaskProfile profile) {
    return builtIns.firstWhere((spec) => spec.profile == profile);
  }
}

class AgentTaskArtifact {
  final String id;
  final AgentTaskArtifactType type;
  final String title;
  final String detail;
  final DateTime createdAt;

  const AgentTaskArtifact({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'detail': detail,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static AgentTaskArtifact? fromJson(Map<String, dynamic> json) {
    try {
      return AgentTaskArtifact(
        id: json['id'] as String,
        type: AgentTaskArtifactType.values.firstWhere(
          (type) => type.name == json['type'],
          orElse: () => AgentTaskArtifactType.diagnostic,
        ),
        title: json['title'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

class AgentTaskRelationship {
  final String taskId;
  final AgentTaskRelationshipType type;

  const AgentTaskRelationship({required this.taskId, required this.type});

  Map<String, dynamic> toJson() => {'taskId': taskId, 'type': type.name};

  static AgentTaskRelationship? fromJson(Map<String, dynamic> json) {
    try {
      return AgentTaskRelationship(
        taskId: json['taskId'] as String,
        type: AgentTaskRelationshipType.values.firstWhere(
          (type) => type.name == json['type'],
          orElse: () => AgentTaskRelationshipType.related,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

class AgentTask {
  final String id;
  final String mascotAlias;
  final AgentTaskProfile profile;
  final AgentTaskStatus status;
  final String goal;
  final AgentTaskWorkspaceMode workspaceMode;
  final WorkspacePermissionConfiguration policy;
  final String? workspaceRoot;
  final String? worktreePath;
  final String? worktreeBranch;
  final String? worktreeBaseRevision;
  final String? contextPackId;

  /// A user-started task may be picked up by the Studio background dispatcher.
  /// Older task records remain inert until explicitly started again.
  final bool backgroundExecutionRequested;
  final String? activeRunId;
  final List<String> patchSetIds;
  final List<String> commandRunIds;
  final List<String> checkpointIds;
  final List<AgentTaskArtifact> artifacts;
  final List<AgentTaskRelationship> relationships;
  final String? result;
  final String? error;
  final DateTime createdAt;

  /// The durable FIFO position for tasks waiting on a shared workspace.
  ///
  /// This differs from [createdAt] when a paused task is resumed behind work
  /// that was already waiting. Older persisted records intentionally fall
  /// back to [createdAt] while they are migrated in place.
  final DateTime? queuedAt;
  final DateTime? completedAt;

  const AgentTask({
    required this.id,
    required this.mascotAlias,
    required this.profile,
    this.status = AgentTaskStatus.queued,
    required this.goal,
    this.workspaceMode = AgentTaskWorkspaceMode.currentWorkspace,
    this.policy = const WorkspacePermissionConfiguration(),
    this.workspaceRoot,
    this.worktreePath,
    this.worktreeBranch,
    this.worktreeBaseRevision,
    this.contextPackId,
    this.backgroundExecutionRequested = false,
    this.activeRunId,
    this.patchSetIds = const [],
    this.commandRunIds = const [],
    this.checkpointIds = const [],
    this.artifacts = const [],
    this.relationships = const [],
    this.result,
    this.error,
    required this.createdAt,
    this.queuedAt,
    this.completedAt,
  });

  AgentTask copyWith({
    AgentTaskStatus? status,
    AgentTaskWorkspaceMode? workspaceMode,
    WorkspacePermissionConfiguration? policy,
    Object? workspaceRoot = _sentinel,
    Object? worktreePath = _sentinel,
    Object? worktreeBranch = _sentinel,
    Object? worktreeBaseRevision = _sentinel,
    Object? contextPackId = _sentinel,
    bool? backgroundExecutionRequested,
    Object? activeRunId = _sentinel,
    List<String>? patchSetIds,
    List<String>? commandRunIds,
    List<String>? checkpointIds,
    List<AgentTaskArtifact>? artifacts,
    List<AgentTaskRelationship>? relationships,
    Object? result = _sentinel,
    Object? error = _sentinel,
    Object? queuedAt = _sentinel,
    Object? completedAt = _sentinel,
  }) {
    return AgentTask(
      id: id,
      mascotAlias: mascotAlias,
      profile: profile,
      status: status ?? this.status,
      goal: goal,
      workspaceMode: workspaceMode ?? this.workspaceMode,
      policy: policy ?? this.policy,
      workspaceRoot: identical(workspaceRoot, _sentinel)
          ? this.workspaceRoot
          : workspaceRoot as String?,
      worktreePath: identical(worktreePath, _sentinel)
          ? this.worktreePath
          : worktreePath as String?,
      worktreeBranch: identical(worktreeBranch, _sentinel)
          ? this.worktreeBranch
          : worktreeBranch as String?,
      worktreeBaseRevision: identical(worktreeBaseRevision, _sentinel)
          ? this.worktreeBaseRevision
          : worktreeBaseRevision as String?,
      contextPackId: identical(contextPackId, _sentinel)
          ? this.contextPackId
          : contextPackId as String?,
      backgroundExecutionRequested:
          backgroundExecutionRequested ?? this.backgroundExecutionRequested,
      activeRunId: identical(activeRunId, _sentinel)
          ? this.activeRunId
          : activeRunId as String?,
      patchSetIds: patchSetIds ?? this.patchSetIds,
      commandRunIds: commandRunIds ?? this.commandRunIds,
      checkpointIds: checkpointIds ?? this.checkpointIds,
      artifacts: artifacts ?? this.artifacts,
      relationships: relationships ?? this.relationships,
      result: identical(result, _sentinel) ? this.result : result as String?,
      error: identical(error, _sentinel) ? this.error : error as String?,
      createdAt: createdAt,
      queuedAt: identical(queuedAt, _sentinel)
          ? this.queuedAt
          : queuedAt as DateTime?,
      completedAt: identical(completedAt, _sentinel)
          ? this.completedAt
          : completedAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mascotAlias': mascotAlias,
      'profile': profile.name,
      'status': status.name,
      'goal': goal,
      'workspaceMode': workspaceMode.name,
      'policy': policy.toJson(),
      'workspaceRoot': workspaceRoot,
      'worktreePath': worktreePath,
      'worktreeBranch': worktreeBranch,
      'worktreeBaseRevision': worktreeBaseRevision,
      'contextPackId': contextPackId,
      'backgroundExecutionRequested': backgroundExecutionRequested,
      'activeRunId': activeRunId,
      'patchSetIds': patchSetIds,
      'commandRunIds': commandRunIds,
      'checkpointIds': checkpointIds,
      'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
      'relationships': relationships
          .map((relationship) => relationship.toJson())
          .toList(),
      'result': result,
      'error': error,
      'createdAt': createdAt.toIso8601String(),
      'queuedAt': queuedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  static AgentTask? fromJson(Map<String, dynamic> json) {
    try {
      return AgentTask(
        id: json['id'] as String,
        mascotAlias: json['mascotAlias'] as String? ?? 'Benny',
        profile: AgentTaskProfile.values.firstWhere(
          (profile) => profile.name == json['profile'],
          orElse: () => AgentTaskProfile.investigate,
        ),
        status: AgentTaskStatus.values.firstWhere(
          (status) => status.name == json['status'],
          orElse: () => AgentTaskStatus.queued,
        ),
        goal: json['goal'] as String? ?? '',
        workspaceMode: AgentTaskWorkspaceMode.values.firstWhere(
          (mode) => mode.name == json['workspaceMode'],
          orElse: () => AgentTaskWorkspaceMode.currentWorkspace,
        ),
        policy: WorkspacePermissionConfiguration.fromJson(
          (json['policy'] as Map?)?.cast<String, dynamic>(),
        ),
        workspaceRoot: json['workspaceRoot'] as String?,
        worktreePath: json['worktreePath'] as String?,
        worktreeBranch: json['worktreeBranch'] as String?,
        worktreeBaseRevision: json['worktreeBaseRevision'] as String?,
        contextPackId: json['contextPackId'] as String?,
        backgroundExecutionRequested:
            json['backgroundExecutionRequested'] as bool? ?? false,
        activeRunId: json['activeRunId'] as String?,
        patchSetIds:
            (json['patchSetIds'] as List<dynamic>?)?.cast<String>() ?? const [],
        commandRunIds:
            (json['commandRunIds'] as List<dynamic>?)?.cast<String>() ??
            const [],
        checkpointIds:
            (json['checkpointIds'] as List<dynamic>?)?.cast<String>() ??
            const [],
        artifacts: (json['artifacts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AgentTaskArtifact.fromJson)
            .nonNulls
            .toList(),
        relationships: (json['relationships'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AgentTaskRelationship.fromJson)
            .nonNulls
            .toList(),
        result: json['result'] as String?,
        error: json['error'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        queuedAt: DateTime.tryParse(json['queuedAt'] as String? ?? ''),
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  /// The only root a task turn is permitted to use for files and tools.
  String? get effectiveWorkspaceRoot {
    return switch (workspaceMode) {
      AgentTaskWorkspaceMode.currentWorkspace => workspaceRoot,
      AgentTaskWorkspaceMode.isolatedWorktree => worktreePath,
    };
  }

  bool get hasUsableIsolatedWorktree =>
      workspaceMode == AgentTaskWorkspaceMode.isolatedWorktree &&
      worktreePath != null &&
      worktreePath!.trim().isNotEmpty &&
      worktreeBranch != null &&
      worktreeBranch!.trim().isNotEmpty;
}

class AgentWorkspaceHistory {
  final List<AgentTask> tasks;

  const AgentWorkspaceHistory({this.tasks = const []});
}

const _sentinel = Object();
