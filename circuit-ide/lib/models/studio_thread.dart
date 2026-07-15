import '../enums/message_role.dart';
import 'chat_message.dart';
import 'context_pack.dart';
import 'studio_source_artifact.dart';
import 'studio_turn.dart';
import 'token_usage.dart';

enum StudioThreadStatus {
  idle,
  preflighting,
  buildingContext,
  streaming,
  waitingForApproval,
  runningCommand,
  reviewingPatch,
  continuationReady,
  done,
  failed,
  cancelled,
}

enum StudioSendPhase {
  idle,
  preflighting,
  buildingContext,
  sent,
  streaming,
  waitingForApproval,
  runningCommand,
  completed,
  blocked,
  failed,
  cancelled,
}

class StudioContextSummary {
  final String? rootPath;
  final String projectLabel;
  final int includedItemCount;
  final int omittedCandidateCount;
  final int estimatedTokens;
  final List<String> selectedFiles;
  final bool includesGit;
  final bool includesTerminal;
  final List<String> warnings;
  final List<String> specialistLabels;
  final String? specialistRouting;

  const StudioContextSummary({
    this.rootPath,
    required this.projectLabel,
    this.includedItemCount = 0,
    this.omittedCandidateCount = 0,
    this.estimatedTokens = 0,
    this.selectedFiles = const [],
    this.includesGit = false,
    this.includesTerminal = false,
    this.warnings = const [],
    this.specialistLabels = const [],
    this.specialistRouting,
  });

  String get title =>
      rootPath == null ? 'No project context' : 'Project context';

  String get detail {
    final parts = [
      if (rootPath != null) rootPath! else 'No project folder selected',
      '$includedItemCount items',
      if (omittedCandidateCount > 0)
        '$omittedCandidateCount omitted high-score',
      '~$estimatedTokens tokens',
      if (selectedFiles.isNotEmpty) '${selectedFiles.length} files',
      if (includesGit) 'git',
      if (includesTerminal) 'terminal',
      if (specialistLabels.isNotEmpty)
        'specialists: ${specialistLabels.join(' + ')}',
      ...warnings,
    ];
    return parts.where((part) => part.trim().isNotEmpty).join(' · ');
  }

  Map<String, dynamic> toJson() {
    return {
      'rootPath': rootPath,
      'projectLabel': projectLabel,
      'includedItemCount': includedItemCount,
      'omittedCandidateCount': omittedCandidateCount,
      'estimatedTokens': estimatedTokens,
      'selectedFiles': selectedFiles,
      'includesGit': includesGit,
      'includesTerminal': includesTerminal,
      'warnings': warnings,
      'specialistLabels': specialistLabels,
      'specialistRouting': specialistRouting,
    };
  }

  static StudioContextSummary fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const StudioContextSummary(projectLabel: 'No project selected');
    }
    return StudioContextSummary(
      rootPath: json['rootPath'] as String?,
      projectLabel: json['projectLabel'] as String? ?? 'Project',
      includedItemCount: json['includedItemCount'] as int? ?? 0,
      omittedCandidateCount: json['omittedCandidateCount'] as int? ?? 0,
      estimatedTokens: json['estimatedTokens'] as int? ?? 0,
      selectedFiles:
          (json['selectedFiles'] as List<dynamic>?)?.cast<String>() ?? const [],
      includesGit: json['includesGit'] as bool? ?? false,
      includesTerminal: json['includesTerminal'] as bool? ?? false,
      warnings:
          (json['warnings'] as List<dynamic>?)?.cast<String>() ?? const [],
      specialistLabels:
          (json['specialistLabels'] as List<dynamic>?)?.cast<String>() ??
          const [],
      specialistRouting: json['specialistRouting'] as String?,
    );
  }
}

class StudioThreadMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;

  const StudioThreadMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  ChatMessage toChatMessage() {
    return ChatMessage(
      id: id,
      role: role,
      content: content,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.value,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  static StudioThreadMessage? fromJson(Map<String, dynamic> json) {
    try {
      return StudioThreadMessage(
        id: json['id'] as String,
        role: MessageRole.values.firstWhere(
          (value) => value.value == json['role'],
          orElse: () => MessageRole.assistant,
        ),
        content: json['content'] as String? ?? '',
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A durable, deterministic summary of older Studio turns. Source turns are
/// retained in the thread; setting [restored] merely sends them directly again
/// instead of this compact history record.
class StudioConversationCompaction {
  final String id;
  final String summary;
  final List<String> sourceTurnIds;
  final DateTime createdAt;
  final int sourceTokenEstimate;
  final bool restored;

  const StudioConversationCompaction({
    required this.id,
    required this.summary,
    required this.sourceTurnIds,
    required this.createdAt,
    this.sourceTokenEstimate = 0,
    this.restored = false,
  });

  StudioConversationCompaction copyWith({bool? restored}) {
    return StudioConversationCompaction(
      id: id,
      summary: summary,
      sourceTurnIds: sourceTurnIds,
      createdAt: createdAt,
      sourceTokenEstimate: sourceTokenEstimate,
      restored: restored ?? this.restored,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'summary': summary,
    'sourceTurnIds': sourceTurnIds,
    'createdAt': createdAt.toIso8601String(),
    'sourceTokenEstimate': sourceTokenEstimate,
    'restored': restored,
  };

  static StudioConversationCompaction? fromJson(Map<String, dynamic> json) {
    try {
      final sourceTurnIds =
          (json['sourceTurnIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .where((id) => id.trim().isNotEmpty)
              .toList(growable: false);
      final summary = json['summary'] as String? ?? '';
      if (sourceTurnIds.isEmpty || summary.trim().isEmpty) return null;
      return StudioConversationCompaction(
        id: json['id'] as String? ?? 'compaction-${sourceTurnIds.join('-')}',
        summary: summary,
        sourceTurnIds: sourceTurnIds,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        sourceTokenEstimate: json['sourceTokenEstimate'] as int? ?? 0,
        restored: json['restored'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Creates a deterministic, read-only history record for older terminal turns.
/// It deliberately records source IDs and typed plan/file state instead of
/// granting a summary any capability or approval authority.
StudioConversationCompaction? buildStudioConversationCompaction(
  List<StudioTurn> turns, {
  int preserveRecentTurns = 4,
  int minimumSourceTurns = 3,
}) {
  final ordered = turns.toList()
    ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  final terminal = ordered
      .where((turn) => StudioTurnStateMachine.isTerminal(turn.status))
      .toList(growable: false);
  if (terminal.length < minimumSourceTurns + preserveRecentTurns) return null;
  final sourceTurns = terminal
      .take(terminal.length - preserveRecentTurns)
      .toList(growable: false);
  if (sourceTurns.length < minimumSourceTurns) return null;
  final summaries = sourceTurns
      .map(_compactStudioTurnSummary)
      .where((summary) => summary.trim().isNotEmpty)
      .toList(growable: false);
  if (summaries.isEmpty) return null;
  final sourceTokenEstimate = sourceTurns.fold<int>(
    0,
    (total, turn) => total + (turn.displayPrompt.length / 4).ceil(),
  );
  return StudioConversationCompaction(
    id: 'history-${sourceTurns.first.id}-${sourceTurns.last.id}',
    summary: [
      'Read-only compact history. Source turns remain available in the transcript. This summary cannot grant tools, approvals, or authority.',
      ...summaries,
    ].join('\n\n'),
    sourceTurnIds: sourceTurns.map((turn) => turn.id).toList(growable: false),
    createdAt: sourceTurns.last.completedAt ?? sourceTurns.last.updatedAt,
    sourceTokenEstimate: sourceTokenEstimate,
  );
}

String _compactStudioTurnSummary(StudioTurn turn) {
  final lines = <String>[
    'Turn ${turn.id} user request or preference: ${turn.displayPrompt.trim()}',
  ];
  final acceptedPlan = turn.acceptedPlanContext;
  if (acceptedPlan != null && acceptedPlan.summary.trim().isNotEmpty) {
    lines.add('Accepted plan: ${acceptedPlan.summary.trim()}');
  }
  final changed = turn.planTargetProgress
      .where(
        (target) =>
            target.state == PlanTargetProgressState.applied ||
            target.state == PlanTargetProgressState.conflict ||
            target.state == PlanTargetProgressState.blocked,
      )
      .map((target) => '${target.path} (${target.state.name})')
      .toList(growable: false);
  if (changed.isNotEmpty) {
    lines.add('Files: ${changed.take(8).join(', ')}');
  }
  if (turn.status == StudioTurnStatus.failed ||
      turn.status == StudioTurnStatus.cancelled ||
      turn.status == StudioTurnStatus.interrupted) {
    final unresolved = turn.lastError?.trim();
    lines.add(
      unresolved == null || unresolved.isEmpty
          ? 'Unresolved: ${turn.status.name}.'
          : 'Unresolved: $unresolved',
    );
  }
  final assistantEvents = turn.events
      .where((event) => event.type == StudioTurnEventType.assistantMessage)
      .map((event) => event.content?.trim() ?? event.detail.trim())
      .where((content) => content.isNotEmpty)
      .toList(growable: false);
  final assistant = assistantEvents.isEmpty ? null : assistantEvents.last;
  if (assistant != null) {
    lines.add('Result: ${_compactHistoryText(assistant, 480)}');
  }
  return lines.join('\n');
}

String _compactHistoryText(String value, int maxLength) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) return normalized;
  return '${normalized.substring(0, maxLength - 1)}…';
}

class StudioThread {
  final String id;
  final String? taskId;
  final String title;
  final StudioThreadStatus status;
  final StudioSendPhase phase;
  final String? requestId;
  final String? model;
  final StudioContextSummary? contextSummary;
  final List<StudioThreadMessage> messages;
  final List<StudioSourceArtifact> sourceArtifacts;
  final List<StudioTurn> turns;
  final List<StudioConversationCompaction> conversationCompactions;
  final String streamingContent;

  /// Cumulative token usage across the durable thread.
  final TokenUsage tokenUsage;

  /// Latest request-local usage, including streamed partial updates.
  final TokenUsage lastRequestTokenUsage;
  final String? lastError;
  final bool archived;
  final DateTime? archivedAt;
  final bool pinned;
  final bool detailLoaded;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StudioThread({
    required this.id,
    this.taskId,
    required this.title,
    this.status = StudioThreadStatus.idle,
    this.phase = StudioSendPhase.idle,
    this.requestId,
    this.model,
    this.contextSummary,
    this.messages = const [],
    this.sourceArtifacts = const [],
    this.turns = const [],
    this.conversationCompactions = const [],
    this.streamingContent = '',
    this.tokenUsage = const TokenUsage(),
    this.lastRequestTokenUsage = const TokenUsage(),
    this.lastError,
    this.archived = false,
    this.archivedAt,
    this.pinned = false,
    this.detailLoaded = true,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive =>
      status == StudioThreadStatus.preflighting ||
      status == StudioThreadStatus.buildingContext ||
      status == StudioThreadStatus.streaming ||
      status == StudioThreadStatus.waitingForApproval ||
      status == StudioThreadStatus.runningCommand;

  ContextRetrievalResult? get latestContextRetrieval {
    StudioTurn? latestTurnWithContext;
    for (final turn in turns) {
      if (turn.contextRetrieval == null) continue;
      if (latestTurnWithContext == null ||
          turn.createdAt.isAfter(latestTurnWithContext.createdAt)) {
        latestTurnWithContext = turn;
      }
    }
    return latestTurnWithContext?.contextRetrieval;
  }

  StudioThread copyWith({
    Object? taskId = _sentinel,
    String? title,
    StudioThreadStatus? status,
    StudioSendPhase? phase,
    Object? requestId = _sentinel,
    Object? model = _sentinel,
    Object? contextSummary = _sentinel,
    List<StudioThreadMessage>? messages,
    List<StudioSourceArtifact>? sourceArtifacts,
    List<StudioTurn>? turns,
    List<StudioConversationCompaction>? conversationCompactions,
    String? streamingContent,
    TokenUsage? tokenUsage,
    TokenUsage? lastRequestTokenUsage,
    Object? lastError = _sentinel,
    bool? archived,
    Object? archivedAt = _sentinel,
    bool? pinned,
    bool? detailLoaded,
    DateTime? updatedAt,
  }) {
    return StudioThread(
      id: id,
      taskId: identical(taskId, _sentinel) ? this.taskId : taskId as String?,
      title: title ?? this.title,
      status: status ?? this.status,
      phase: phase ?? this.phase,
      requestId: identical(requestId, _sentinel)
          ? this.requestId
          : requestId as String?,
      model: identical(model, _sentinel) ? this.model : model as String?,
      contextSummary: identical(contextSummary, _sentinel)
          ? this.contextSummary
          : contextSummary as StudioContextSummary?,
      messages: messages ?? this.messages,
      sourceArtifacts: sourceArtifacts ?? this.sourceArtifacts,
      turns: turns ?? this.turns,
      conversationCompactions:
          conversationCompactions ?? this.conversationCompactions,
      streamingContent: streamingContent ?? this.streamingContent,
      tokenUsage: tokenUsage ?? this.tokenUsage,
      lastRequestTokenUsage:
          lastRequestTokenUsage ?? this.lastRequestTokenUsage,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
      archived: archived ?? this.archived,
      archivedAt: identical(archivedAt, _sentinel)
          ? this.archivedAt
          : archivedAt as DateTime?,
      pinned: pinned ?? this.pinned,
      detailLoaded: detailLoaded ?? this.detailLoaded,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'taskId': taskId,
      'title': title,
      'status': status.name,
      'phase': phase.name,
      'requestId': requestId,
      'model': model,
      'contextSummary': contextSummary?.toJson(),
      'messages': messages.map((message) => message.toJson()).toList(),
      'sourceArtifacts': sourceArtifacts
          .map((artifact) => artifact.toJson())
          .toList(),
      'turns': turns.map((turn) => turn.toJson()).toList(),
      'conversationCompactions': conversationCompactions
          .map((compaction) => compaction.toJson())
          .toList(),
      'streamingContent': streamingContent,
      'tokenUsage': {
        'promptTokens': tokenUsage.promptTokens,
        'cachedInputTokens': tokenUsage.cachedInputTokens,
        'completionTokens': tokenUsage.completionTokens,
        'reasoningTokens': tokenUsage.reasoningTokens,
        'toolTokens': tokenUsage.toolTokens,
        'totalTokens': tokenUsage.totalTokens,
      },
      'lastRequestTokenUsage': _usageToJson(lastRequestTokenUsage),
      'lastError': lastError,
      'archived': archived,
      'archivedAt': archivedAt?.toIso8601String(),
      'pinned': pinned,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static StudioThread? fromJson(Map<String, dynamic> json) {
    try {
      final usage = json['tokenUsage'] as Map<String, dynamic>?;
      final lastRequestUsage =
          json['lastRequestTokenUsage'] as Map<String, dynamic>?;
      return StudioThread(
        id: json['id'] as String,
        taskId: json['taskId'] as String?,
        title: json['title'] as String? ?? 'Circuit task',
        status: StudioThreadStatus.values.firstWhere(
          (value) => value.name == json['status'],
          orElse: () => StudioThreadStatus.idle,
        ),
        phase: StudioSendPhase.values.firstWhere(
          (value) => value.name == json['phase'],
          orElse: () => StudioSendPhase.idle,
        ),
        requestId: json['requestId'] as String?,
        model: json['model'] as String?,
        contextSummary: StudioContextSummary.fromJson(
          json['contextSummary'] as Map<String, dynamic>?,
        ),
        messages: (json['messages'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(StudioThreadMessage.fromJson)
            .nonNulls
            .toList(),
        sourceArtifacts: (json['sourceArtifacts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(StudioSourceArtifact.fromJson)
            .nonNulls
            .toList(),
        turns: (json['turns'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(StudioTurn.fromJson)
            .nonNulls
            .toList(),
        conversationCompactions:
            (json['conversationCompactions'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>()
                .map(StudioConversationCompaction.fromJson)
                .nonNulls
                .toList(),
        streamingContent: json['streamingContent'] as String? ?? '',
        tokenUsage: TokenUsage(
          promptTokens: usage?['promptTokens'] as int? ?? 0,
          cachedInputTokens: usage?['cachedInputTokens'] as int? ?? 0,
          completionTokens: usage?['completionTokens'] as int? ?? 0,
          reasoningTokens: usage?['reasoningTokens'] as int? ?? 0,
          toolTokens: usage?['toolTokens'] as int? ?? 0,
          totalTokens: usage?['totalTokens'] as int? ?? 0,
        ),
        lastRequestTokenUsage: _usageFromJson(lastRequestUsage),
        lastError: json['lastError'] as String?,
        archived: json['archived'] as bool? ?? false,
        archivedAt: DateTime.tryParse(json['archivedAt'] as String? ?? ''),
        pinned: json['pinned'] as bool? ?? false,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

Map<String, dynamic> _usageToJson(TokenUsage usage) => {
  'promptTokens': usage.promptTokens,
  'cachedInputTokens': usage.cachedInputTokens,
  'completionTokens': usage.completionTokens,
  'reasoningTokens': usage.reasoningTokens,
  'toolTokens': usage.toolTokens,
  'totalTokens': usage.totalTokens,
};

TokenUsage _usageFromJson(Map<String, dynamic>? usage) => TokenUsage(
  promptTokens: usage?['promptTokens'] as int? ?? 0,
  cachedInputTokens: usage?['cachedInputTokens'] as int? ?? 0,
  completionTokens: usage?['completionTokens'] as int? ?? 0,
  reasoningTokens: usage?['reasoningTokens'] as int? ?? 0,
  toolTokens: usage?['toolTokens'] as int? ?? 0,
  totalTokens: usage?['totalTokens'] as int? ?? 0,
);

class StudioTaskLifecycleState {
  final StudioThreadStatus status;
  final String label;
  final bool isActive;
  final bool needsAttention;

  const StudioTaskLifecycleState({
    required this.status,
    required this.label,
    this.isActive = false,
    this.needsAttention = false,
  });

  static StudioTaskLifecycleState fromThread(StudioThread? thread) {
    return switch (_effectiveStatus(thread)) {
      StudioThreadStatus.preflighting => const StudioTaskLifecycleState(
        status: StudioThreadStatus.preflighting,
        label: 'Waiting',
        isActive: true,
      ),
      StudioThreadStatus.buildingContext => const StudioTaskLifecycleState(
        status: StudioThreadStatus.buildingContext,
        label: 'Running',
        isActive: true,
      ),
      StudioThreadStatus.streaming => const StudioTaskLifecycleState(
        status: StudioThreadStatus.streaming,
        label: 'Running',
        isActive: true,
      ),
      StudioThreadStatus.waitingForApproval => const StudioTaskLifecycleState(
        status: StudioThreadStatus.waitingForApproval,
        label: 'Waiting',
        isActive: true,
        needsAttention: true,
      ),
      StudioThreadStatus.runningCommand => const StudioTaskLifecycleState(
        status: StudioThreadStatus.runningCommand,
        label: 'Running',
        isActive: true,
      ),
      StudioThreadStatus.reviewingPatch => const StudioTaskLifecycleState(
        status: StudioThreadStatus.reviewingPatch,
        label: 'Needs review',
        isActive: true,
        needsAttention: true,
      ),
      StudioThreadStatus.continuationReady => const StudioTaskLifecycleState(
        status: StudioThreadStatus.continuationReady,
        label: 'Needs review',
        needsAttention: true,
      ),
      StudioThreadStatus.done => const StudioTaskLifecycleState(
        status: StudioThreadStatus.done,
        label: 'Done',
      ),
      StudioThreadStatus.failed => const StudioTaskLifecycleState(
        status: StudioThreadStatus.failed,
        label: 'Failed',
        needsAttention: true,
      ),
      StudioThreadStatus.cancelled => const StudioTaskLifecycleState(
        status: StudioThreadStatus.cancelled,
        label: 'Cancelled',
      ),
      StudioThreadStatus.idle || null => const StudioTaskLifecycleState(
        status: StudioThreadStatus.idle,
        label: 'Ready',
      ),
    };
  }

  static StudioThreadStatus? _effectiveStatus(StudioThread? thread) {
    if (thread == null) return null;
    if (!_isPotentiallyStaleActiveStatus(thread.status)) {
      return thread.status;
    }

    final latestTurn = thread.turns.fold<StudioTurn?>(
      null,
      (latest, turn) =>
          latest == null || turn.createdAt.isAfter(latest.createdAt)
          ? turn
          : latest,
    );
    final turnStatus = switch (latestTurn?.status) {
      StudioTurnStatus.completed => StudioThreadStatus.done,
      StudioTurnStatus.failed => StudioThreadStatus.failed,
      StudioTurnStatus.cancelled => StudioThreadStatus.cancelled,
      StudioTurnStatus.waitingForApproval =>
        StudioThreadStatus.waitingForApproval,
      StudioTurnStatus.toolRunning => StudioThreadStatus.runningCommand,
      StudioTurnStatus.streaming => StudioThreadStatus.streaming,
      StudioTurnStatus.buildingContext => StudioThreadStatus.buildingContext,
      _ => null,
    };
    if (turnStatus != null) return turnStatus;

    if (thread.lastError?.trim().isNotEmpty ?? false) {
      return StudioThreadStatus.failed;
    }
    final hasCompletedTurn = thread.turns.any(
      (turn) => turn.status == StudioTurnStatus.completed,
    );
    if (hasCompletedTurn) {
      return StudioThreadStatus.done;
    }
    return thread.status;
  }

  static bool _isPotentiallyStaleActiveStatus(StudioThreadStatus status) {
    return switch (status) {
      StudioThreadStatus.preflighting ||
      StudioThreadStatus.buildingContext ||
      StudioThreadStatus.streaming ||
      StudioThreadStatus.runningCommand => true,
      StudioThreadStatus.idle ||
      StudioThreadStatus.waitingForApproval ||
      StudioThreadStatus.reviewingPatch ||
      StudioThreadStatus.continuationReady ||
      StudioThreadStatus.done ||
      StudioThreadStatus.failed ||
      StudioThreadStatus.cancelled => false,
    };
  }
}

const _sentinel = Object();
