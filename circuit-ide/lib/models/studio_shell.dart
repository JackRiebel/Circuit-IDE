import 'agent_workspace.dart';
import 'specialist_agent.dart';

enum StudioMode { home, project, task, review, settings }

enum StudioPromptMode { ask, code, fix, review }

enum StudioExecutionMode { local, worktree }

class StudioShellState {
  final StudioMode mode;
  final String? selectedProjectPath;
  final String? selectedTaskId;
  final StudioPromptMode promptMode;
  final StudioExecutionMode executionMode;
  final SpecialistAgentId specialistAgentId;
  final String composerText;
  final bool rightProgressPanelVisible;
  final bool planModeEnabled;

  const StudioShellState({
    this.mode = StudioMode.home,
    this.selectedProjectPath,
    this.selectedTaskId,
    this.promptMode = StudioPromptMode.code,
    this.executionMode = StudioExecutionMode.local,
    this.specialistAgentId = SpecialistAgentId.auto,
    this.composerText = '',
    this.rightProgressPanelVisible = true,
    this.planModeEnabled = false,
  });

  StudioShellState copyWith({
    StudioMode? mode,
    Object? selectedProjectPath = _sentinel,
    Object? selectedTaskId = _sentinel,
    StudioPromptMode? promptMode,
    StudioExecutionMode? executionMode,
    SpecialistAgentId? specialistAgentId,
    String? composerText,
    bool? rightProgressPanelVisible,
    bool? planModeEnabled,
  }) {
    return StudioShellState(
      mode: mode ?? this.mode,
      selectedProjectPath: identical(selectedProjectPath, _sentinel)
          ? this.selectedProjectPath
          : selectedProjectPath as String?,
      selectedTaskId: identical(selectedTaskId, _sentinel)
          ? this.selectedTaskId
          : selectedTaskId as String?,
      promptMode: promptMode ?? this.promptMode,
      executionMode: executionMode ?? this.executionMode,
      specialistAgentId: specialistAgentId ?? this.specialistAgentId,
      composerText: composerText ?? this.composerText,
      rightProgressPanelVisible:
          rightProgressPanelVisible ?? this.rightProgressPanelVisible,
      planModeEnabled: planModeEnabled ?? this.planModeEnabled,
    );
  }
}

extension StudioExecutionModeLabels on StudioExecutionMode {
  String get label {
    return switch (this) {
      StudioExecutionMode.local => 'Local',
      StudioExecutionMode.worktree => 'Worktree',
    };
  }
}

extension StudioPromptModeLabels on StudioPromptMode {
  String get label {
    return switch (this) {
      StudioPromptMode.ask => 'Ask',
      StudioPromptMode.code => 'Code',
      StudioPromptMode.fix => 'Fix',
      StudioPromptMode.review => 'Review',
    };
  }

  AgentTaskProfile? get agentProfile {
    return switch (this) {
      StudioPromptMode.ask => null,
      StudioPromptMode.code => AgentTaskProfile.patch,
      StudioPromptMode.fix => AgentTaskProfile.investigate,
      StudioPromptMode.review => AgentTaskProfile.review,
    };
  }
}

class StudioTaskSummary {
  final String id;
  final String alias;
  final String title;
  final String projectLabel;
  final String statusLabel;
  final String detail;
  final int artifactCount;
  final int changeCount;
  final bool needsReview;

  const StudioTaskSummary({
    required this.id,
    required this.alias,
    required this.title,
    required this.projectLabel,
    required this.statusLabel,
    required this.detail,
    required this.artifactCount,
    required this.changeCount,
    required this.needsReview,
  });

  factory StudioTaskSummary.fromTask(
    AgentTask task, {
    String projectLabel = 'Circuit-IDE',
  }) {
    return StudioTaskSummary(
      id: task.id,
      alias: task.mascotAlias,
      title: task.goal,
      projectLabel: projectLabel,
      statusLabel: studioTaskStatusLabel(task.status),
      detail: task.result ?? task.error ?? _profileLabel(task.profile),
      artifactCount: task.artifacts.length,
      changeCount: task.patchSetIds.length,
      needsReview: task.status == AgentTaskStatus.waitingForApproval,
    );
  }
}

class StudioProgressRow {
  final String label;
  final String value;
  final bool enabled;
  final bool accent;

  const StudioProgressRow({
    required this.label,
    required this.value,
    this.enabled = true,
    this.accent = false,
  });
}

String studioTaskStatusLabel(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.queued => 'Queued',
    AgentTaskStatus.running => 'Working',
    AgentTaskStatus.waitingForApproval => 'Needs review',
    AgentTaskStatus.completed => 'Done',
    AgentTaskStatus.failed => 'Failed',
    AgentTaskStatus.cancelled => 'Cancelled',
  };
}

String _profileLabel(AgentTaskProfile profile) {
  return switch (profile) {
    AgentTaskProfile.investigate => 'Investigating the safest path',
    AgentTaskProfile.plan => 'Creating a plan',
    AgentTaskProfile.patch => 'Preparing code changes',
    AgentTaskProfile.review => 'Reviewing current work',
    AgentTaskProfile.verify => 'Preparing checks',
    AgentTaskProfile.handoff => 'Creating a handoff',
  };
}

const _sentinel = Object();
