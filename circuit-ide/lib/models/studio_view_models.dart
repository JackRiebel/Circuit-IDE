import '../enums/message_role.dart';
import 'agent_workspace.dart';
import 'chat_message.dart';
import 'command_run.dart';
import 'confirmation_request.dart';
import 'reviewed_edit.dart';
import 'studio_right_drawer.dart';
import 'studio_thread.dart';

enum TaskDisplayKind {
  idle,
  working,
  waitingForApproval,
  runningCommand,
  streaming,
  continuationReady,
  done,
  failed,
  cancelled,
}

class TaskDisplayState {
  final TaskDisplayKind kind;
  final String label;
  final bool isActive;
  final bool needsAttention;

  const TaskDisplayState({
    required this.kind,
    required this.label,
    this.isActive = false,
    this.needsAttention = false,
  });

  static TaskDisplayState derive({
    AgentTask? task,
    required bool isChatProcessing,
    required bool isChatStreaming,
    required bool hasAssistantResponse,
    required bool hasPendingApproval,
    required Iterable<CommandRun> commands,
    String? chatError,
  }) {
    final hasRunningCommand = commands.any(
      (command) => command.status == CommandRunStatus.running,
    );
    if (hasPendingApproval) {
      return const TaskDisplayState(
        kind: TaskDisplayKind.waitingForApproval,
        label: 'Waiting',
        isActive: true,
        needsAttention: true,
      );
    }
    if (hasRunningCommand) {
      return const TaskDisplayState(
        kind: TaskDisplayKind.runningCommand,
        label: 'Running',
        isActive: true,
      );
    }
    if (isChatStreaming) {
      return const TaskDisplayState(
        kind: TaskDisplayKind.streaming,
        label: 'Responding',
        isActive: true,
      );
    }
    if (isChatProcessing) {
      return const TaskDisplayState(
        kind: TaskDisplayKind.working,
        label: 'Working',
        isActive: true,
      );
    }
    if (chatError != null || task?.status == AgentTaskStatus.failed) {
      return const TaskDisplayState(
        kind: TaskDisplayKind.failed,
        label: 'Failed',
        needsAttention: true,
      );
    }
    if (task?.status == AgentTaskStatus.cancelled) {
      return const TaskDisplayState(
        kind: TaskDisplayKind.cancelled,
        label: 'Cancelled',
      );
    }
    if (task?.status == AgentTaskStatus.completed ||
        task?.completedAt != null ||
        (task?.result?.trim().isNotEmpty ?? false) ||
        hasAssistantResponse) {
      return const TaskDisplayState(kind: TaskDisplayKind.done, label: 'Done');
    }
    if (task != null) {
      return const TaskDisplayState(
        kind: TaskDisplayKind.working,
        label: 'Working',
        isActive: true,
      );
    }
    return const TaskDisplayState(kind: TaskDisplayKind.idle, label: 'Ready');
  }

  factory TaskDisplayState.fromLifecycle(StudioTaskLifecycleState lifecycle) {
    return TaskDisplayState(
      kind: switch (lifecycle.status) {
        StudioThreadStatus.waitingForApproval =>
          TaskDisplayKind.waitingForApproval,
        StudioThreadStatus.runningCommand => TaskDisplayKind.runningCommand,
        StudioThreadStatus.streaming => TaskDisplayKind.streaming,
        StudioThreadStatus.preflighting ||
        StudioThreadStatus.buildingContext ||
        StudioThreadStatus.reviewingPatch => TaskDisplayKind.working,
        StudioThreadStatus.continuationReady =>
          TaskDisplayKind.continuationReady,
        StudioThreadStatus.done => TaskDisplayKind.done,
        StudioThreadStatus.failed => TaskDisplayKind.failed,
        StudioThreadStatus.cancelled => TaskDisplayKind.cancelled,
        StudioThreadStatus.idle => TaskDisplayKind.idle,
      },
      label: lifecycle.label,
      isActive: lifecycle.isActive,
      needsAttention: lifecycle.needsAttention,
    );
  }
}

enum StudioTranscriptItemType {
  userMessage,
  assistantMarkdown,
  activity,
  approval,
  error,
  patchReview,
  commandRun,
}

class StudioTranscriptItem {
  final StudioTranscriptItemType type;
  final String? threadId;
  final String? requestId;
  final DateTime? timestamp;
  final String? relatedMessageId;
  final ChatMessage? message;
  final AgentTaskArtifact? artifact;
  final CommandRun? commandRun;
  final ProposedPatchSet? patch;
  final ConfirmationRequest? confirmation;
  final StudioContextSummary? contextSummary;
  final String? commandRunId;
  final String? patchSetId;
  final String? approvalId;
  final String? sourceArtifactId;
  final StudioDrawerMode? drawerTarget;
  final String? filePath;
  final String? diffId;
  final String? localUrl;
  final String? error;

  const StudioTranscriptItem._({
    required this.type,
    this.threadId,
    this.requestId,
    this.timestamp,
    this.relatedMessageId,
    this.message,
    this.artifact,
    this.commandRun,
    this.patch,
    this.confirmation,
    this.contextSummary,
    this.commandRunId,
    this.patchSetId,
    this.approvalId,
    this.sourceArtifactId,
    this.drawerTarget,
    this.filePath,
    this.diffId,
    this.localUrl,
    this.error,
  });

  factory StudioTranscriptItem.userMessage(
    ChatMessage message, {
    String? threadId,
    String? requestId,
  }) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.userMessage,
      threadId: threadId,
      requestId: requestId,
      timestamp: message.timestamp,
      message: message,
    );
  }

  factory StudioTranscriptItem.assistantMarkdown(
    ChatMessage message, {
    String? threadId,
    String? requestId,
  }) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.assistantMarkdown,
      threadId: threadId,
      requestId: requestId,
      timestamp: message.timestamp,
      message: message,
    );
  }

  factory StudioTranscriptItem.activity(
    AgentTaskArtifact artifact, {
    String? threadId,
    String? requestId,
    String? relatedMessageId,
    StudioContextSummary? contextSummary,
    String? sourceArtifactId,
    String? filePath,
    String? localUrl,
  }) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.activity,
      threadId: threadId,
      requestId: requestId,
      timestamp: artifact.createdAt,
      relatedMessageId: relatedMessageId,
      artifact: artifact,
      contextSummary: contextSummary,
      sourceArtifactId: sourceArtifactId,
      drawerTarget: StudioDrawerMode.sources,
      filePath: filePath,
      localUrl: localUrl,
    );
  }

  factory StudioTranscriptItem.approval(
    ConfirmationRequest request, {
    String? threadId,
    String? requestId,
  }) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.approval,
      threadId: threadId,
      requestId: requestId,
      timestamp: request.timestamp,
      approvalId: request.id,
      confirmation: request,
    );
  }

  factory StudioTranscriptItem.error(
    String error, {
    String? threadId,
    String? requestId,
  }) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.error,
      threadId: threadId,
      requestId: requestId,
      timestamp: DateTime.now(),
      error: error,
    );
  }

  factory StudioTranscriptItem.patchReview(
    ProposedPatchSet patch, {
    String? threadId,
    String? requestId,
  }) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.patchReview,
      threadId: threadId,
      requestId: requestId,
      timestamp: patch.createdAt,
      patchSetId: patch.id,
      patch: patch,
      diffId: patch.id,
      drawerTarget: StudioDrawerMode.diff,
    );
  }

  factory StudioTranscriptItem.commandRun(
    CommandRun commandRun, {
    String? threadId,
    String? requestId,
  }) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.commandRun,
      threadId: threadId,
      requestId: requestId,
      timestamp: commandRun.startedAt,
      commandRunId: commandRun.id,
      commandRun: commandRun,
      drawerTarget: StudioDrawerMode.terminal,
    );
  }
}

class StudioRailProjectSummary {
  final String path;
  final String name;
  final bool selected;
  final int taskCount;

  const StudioRailProjectSummary({
    required this.path,
    required this.name,
    required this.selected,
    required this.taskCount,
  });
}

class StudioRailTaskSummary {
  final String id;
  final String title;
  final bool selected;
  final TaskDisplayState displayState;
  final DateTime? updatedAt;

  const StudioRailTaskSummary({
    required this.id,
    required this.title,
    required this.selected,
    required this.displayState,
    this.updatedAt,
  });
}

bool hasAssistantResponse(Iterable<ChatMessage> messages) {
  return messages.any(
    (message) =>
        message.role == MessageRole.assistant &&
        message.content.trim().isNotEmpty,
  );
}
