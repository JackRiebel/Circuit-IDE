import '../enums/message_role.dart';
import 'agent_workspace.dart';
import 'chat_message.dart';
import 'command_run.dart';
import 'confirmation_request.dart';
import 'reviewed_edit.dart';

enum TaskDisplayKind {
  idle,
  working,
  waitingForApproval,
  runningCommand,
  streaming,
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
    if (task?.status == AgentTaskStatus.completed || hasAssistantResponse) {
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
  final ChatMessage? message;
  final AgentTaskArtifact? artifact;
  final CommandRun? commandRun;
  final ProposedPatchSet? patch;
  final ConfirmationRequest? confirmation;
  final String? error;

  const StudioTranscriptItem._({
    required this.type,
    this.message,
    this.artifact,
    this.commandRun,
    this.patch,
    this.confirmation,
    this.error,
  });

  factory StudioTranscriptItem.userMessage(ChatMessage message) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.userMessage,
      message: message,
    );
  }

  factory StudioTranscriptItem.assistantMarkdown(ChatMessage message) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.assistantMarkdown,
      message: message,
    );
  }

  factory StudioTranscriptItem.activity(AgentTaskArtifact artifact) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.activity,
      artifact: artifact,
    );
  }

  factory StudioTranscriptItem.approval(ConfirmationRequest request) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.approval,
      confirmation: request,
    );
  }

  factory StudioTranscriptItem.error(String error) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.error,
      error: error,
    );
  }

  factory StudioTranscriptItem.patchReview(ProposedPatchSet patch) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.patchReview,
      patch: patch,
    );
  }

  factory StudioTranscriptItem.commandRun(CommandRun commandRun) {
    return StudioTranscriptItem._(
      type: StudioTranscriptItemType.commandRun,
      commandRun: commandRun,
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

  const StudioRailTaskSummary({
    required this.id,
    required this.title,
    required this.selected,
    required this.displayState,
  });
}

bool hasAssistantResponse(Iterable<ChatMessage> messages) {
  return messages.any(
    (message) =>
        message.role == MessageRole.assistant &&
        message.content.trim().isNotEmpty,
  );
}
