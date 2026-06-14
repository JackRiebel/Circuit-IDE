import '../enums/message_role.dart';
import 'chat_message.dart';
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
  final String streamingContent;
  final TokenUsage tokenUsage;
  final String? lastError;
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
    this.streamingContent = '',
    this.tokenUsage = const TokenUsage(),
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive =>
      status == StudioThreadStatus.preflighting ||
      status == StudioThreadStatus.buildingContext ||
      status == StudioThreadStatus.streaming ||
      status == StudioThreadStatus.waitingForApproval ||
      status == StudioThreadStatus.runningCommand;

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
    String? streamingContent,
    TokenUsage? tokenUsage,
    Object? lastError = _sentinel,
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
      streamingContent: streamingContent ?? this.streamingContent,
      tokenUsage: tokenUsage ?? this.tokenUsage,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
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
      'streamingContent': streamingContent,
      'tokenUsage': {
        'promptTokens': tokenUsage.promptTokens,
        'completionTokens': tokenUsage.completionTokens,
        'totalTokens': tokenUsage.totalTokens,
      },
      'lastError': lastError,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static StudioThread? fromJson(Map<String, dynamic> json) {
    try {
      final usage = json['tokenUsage'] as Map<String, dynamic>?;
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
        streamingContent: json['streamingContent'] as String? ?? '',
        tokenUsage: TokenUsage(
          promptTokens: usage?['promptTokens'] as int? ?? 0,
          completionTokens: usage?['completionTokens'] as int? ?? 0,
          totalTokens: usage?['totalTokens'] as int? ?? 0,
        ),
        lastError: json['lastError'] as String?,
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
    return switch (thread?.status) {
      StudioThreadStatus.preflighting => const StudioTaskLifecycleState(
        status: StudioThreadStatus.preflighting,
        label: 'Checking',
        isActive: true,
      ),
      StudioThreadStatus.buildingContext => const StudioTaskLifecycleState(
        status: StudioThreadStatus.buildingContext,
        label: 'Context',
        isActive: true,
      ),
      StudioThreadStatus.streaming => const StudioTaskLifecycleState(
        status: StudioThreadStatus.streaming,
        label: 'Working',
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
        label: 'Review',
        isActive: true,
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
}

const _sentinel = Object();
