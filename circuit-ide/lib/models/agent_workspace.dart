enum AgentTaskStatus {
  queued,
  running,
  waitingForApproval,
  completed,
  failed,
  cancelled,
}

enum AgentTaskProfile { investigate, plan, patch, review, verify, handoff }

enum AgentTaskArtifactType {
  contextPack,
  patchProposal,
  commandRun,
  checkpoint,
  verification,
  diagnostic,
}

enum AgentTaskRelationshipType { parent, child, related, supersedes }

enum AgentToolPermissionVerdict { allow, review, warn, block }

enum AgentToolPermissionTarget {
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

class AgentToolPermissionPolicy {
  final AgentToolPermissionVerdict readTools;
  final AgentToolPermissionVerdict writeTools;
  final AgentToolPermissionVerdict commands;
  final AgentToolPermissionVerdict gitActions;
  final AgentToolPermissionVerdict externalNetwork;

  const AgentToolPermissionPolicy({
    this.readTools = AgentToolPermissionVerdict.allow,
    this.writeTools = AgentToolPermissionVerdict.review,
    this.commands = AgentToolPermissionVerdict.review,
    this.gitActions = AgentToolPermissionVerdict.review,
    this.externalNetwork = AgentToolPermissionVerdict.block,
  });

  AgentToolPermissionVerdict verdictFor(AgentToolPermissionTarget target) {
    return switch (target) {
      AgentToolPermissionTarget.readTool => readTools,
      AgentToolPermissionTarget.writeTool => writeTools,
      AgentToolPermissionTarget.command => commands,
      AgentToolPermissionTarget.git => gitActions,
      AgentToolPermissionTarget.externalNetwork => externalNetwork,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'readTools': readTools.name,
      'writeTools': writeTools.name,
      'commands': commands.name,
      'gitActions': gitActions.name,
      'externalNetwork': externalNetwork.name,
    };
  }

  static AgentToolPermissionPolicy fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AgentToolPermissionPolicy();
    return AgentToolPermissionPolicy(
      readTools: _verdict(json['readTools']),
      writeTools: _verdict(json['writeTools']),
      commands: _verdict(json['commands']),
      gitActions: _verdict(json['gitActions']),
      externalNetwork: _verdict(json['externalNetwork']),
    );
  }

  static AgentToolPermissionVerdict _verdict(dynamic value) {
    return AgentToolPermissionVerdict.values.firstWhere(
      (verdict) => verdict.name == value,
      orElse: () => AgentToolPermissionVerdict.review,
    );
  }
}

class AgentTaskProfileSpec {
  final AgentTaskProfile profile;
  final String label;
  final String description;
  final AgentToolPermissionPolicy policy;
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
      policy: AgentToolPermissionPolicy(
        commands: AgentToolPermissionVerdict.warn,
      ),
      expectedOutput: 'Findings, risks, and next actions.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.plan,
      label: 'Plan',
      description: 'Turn a goal into a safe implementation plan.',
      policy: AgentToolPermissionPolicy(),
      expectedOutput: 'A short plan with verification steps.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.patch,
      label: 'Patch',
      description: 'Prepare a reviewed patch proposal.',
      policy: AgentToolPermissionPolicy(),
      expectedOutput: 'Patch proposal and rationale.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.review,
      label: 'Review',
      description: 'Review current changes and identify issues.',
      policy: AgentToolPermissionPolicy(
        commands: AgentToolPermissionVerdict.warn,
      ),
      expectedOutput: 'Findings ordered by severity.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.verify,
      label: 'Verify',
      description: 'Suggest and prepare verification commands.',
      policy: AgentToolPermissionPolicy(
        commands: AgentToolPermissionVerdict.review,
      ),
      expectedOutput: 'Checks to run and expected signal.',
    ),
    AgentTaskProfileSpec(
      profile: AgentTaskProfile.handoff,
      label: 'Handoff',
      description: 'Create a concise work summary.',
      policy: AgentToolPermissionPolicy(),
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
  final String? contextPackId;
  final String? activeRunId;
  final List<String> patchSetIds;
  final List<String> commandRunIds;
  final List<String> checkpointIds;
  final List<AgentTaskArtifact> artifacts;
  final List<AgentTaskRelationship> relationships;
  final String? result;
  final String? error;
  final DateTime createdAt;
  final DateTime? completedAt;

  const AgentTask({
    required this.id,
    required this.mascotAlias,
    required this.profile,
    this.status = AgentTaskStatus.queued,
    required this.goal,
    this.contextPackId,
    this.activeRunId,
    this.patchSetIds = const [],
    this.commandRunIds = const [],
    this.checkpointIds = const [],
    this.artifacts = const [],
    this.relationships = const [],
    this.result,
    this.error,
    required this.createdAt,
    this.completedAt,
  });

  AgentTask copyWith({
    AgentTaskStatus? status,
    Object? contextPackId = _sentinel,
    Object? activeRunId = _sentinel,
    List<String>? patchSetIds,
    List<String>? commandRunIds,
    List<String>? checkpointIds,
    List<AgentTaskArtifact>? artifacts,
    List<AgentTaskRelationship>? relationships,
    Object? result = _sentinel,
    Object? error = _sentinel,
    DateTime? completedAt,
  }) {
    return AgentTask(
      id: id,
      mascotAlias: mascotAlias,
      profile: profile,
      status: status ?? this.status,
      goal: goal,
      contextPackId: identical(contextPackId, _sentinel)
          ? this.contextPackId
          : contextPackId as String?,
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
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mascotAlias': mascotAlias,
      'profile': profile.name,
      'status': status.name,
      'goal': goal,
      'contextPackId': contextPackId,
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
        contextPackId: json['contextPackId'] as String?,
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
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}

class AgentWorkspaceHistory {
  final List<AgentTask> tasks;

  const AgentWorkspaceHistory({this.tasks = const []});
}

const _sentinel = Object();
