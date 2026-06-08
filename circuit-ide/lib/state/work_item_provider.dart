import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/project_profile.dart';
import '../models/work_item.dart';
import '../models/work_item_handoff_summary.dart';
import 'agent_run_provider.dart';
import 'chat_provider.dart';
import 'git_provider.dart';
import 'project_profile_provider.dart';

const _uuid = Uuid();

class WorkItemController extends Notifier<WorkItem?> {
  @override
  WorkItem? build() => null;

  void start(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return;
    final profile = ref.read(projectProfileProvider);
    final checks = ref
        .read(projectProfileProvider.notifier)
        .recommendedChecks();
    state = WorkItem(
      id: _uuid.v4().substring(0, 8),
      prompt: trimmed,
      status: WorkItemStatus.ready,
      steps: _defaultSteps(trimmed, profile.primaryType.label),
      verificationCommands: checks,
      createdAt: DateTime.now(),
    );
  }

  Future<void> sendToChat() async {
    final item = state;
    if (item == null) return;
    state = item.copyWith(
      status: WorkItemStatus.running,
      steps: _markStep(
        item.steps,
        0,
        completed: true,
      ).let((steps) => _markStep(steps, 1, running: true)),
    );
    await ref.read(chatProvider.notifier).sendMessage(_executionPrompt(item));
    state = state?.copyWith(
      status: WorkItemStatus.verifying,
      steps: state == null
          ? item.steps
          : _markStep(
              state!.steps,
              1,
              completed: true,
              running: false,
            ).let((steps) => _markStep(steps, 2, running: true)),
      changedFiles: _changedFiles(),
      suggestedNextSteps: const [
        'Review the changed files.',
        'Run recommended checks.',
        'Create a handoff summary.',
      ],
    );
  }

  Future<void> runVerification() async {
    final item = state;
    if (item == null) return;
    state = item.copyWith(
      status: WorkItemStatus.verifying,
      steps: _markStep(item.steps, 2, running: true),
    );
    final profileNotifier = ref.read(projectProfileProvider.notifier);
    final results = <VerificationResultSummary>[];
    for (final command in item.verificationCommands.where((c) => c.enabled)) {
      results.add(await profileNotifier.runCommand(command));
    }
    final passed =
        results.isNotEmpty && results.every((result) => result.passed);
    state = state?.copyWith(
      status: passed ? WorkItemStatus.completed : WorkItemStatus.failed,
      steps: state == null
          ? item.steps
          : _markStep(
              state!.steps,
              2,
              completed: passed,
              running: false,
              result: passed ? 'Checks passed' : null,
              error: passed ? null : 'One or more checks failed',
            ),
      verificationResults: results,
      changedFiles: _changedFiles(),
      completedAt: DateTime.now(),
      result: passed ? 'Verification passed' : 'Verification needs attention',
      suggestedNextSteps: passed
          ? const ['Create a handoff summary.', 'Commit the verified changes.']
          : const ['Inspect failed command output.', 'Retry the work item.'],
    );
  }

  void cancel() {
    final item = state;
    if (item == null) return;
    state = item.copyWith(status: WorkItemStatus.cancelled);
  }

  void clear() {
    state = null;
  }

  String handoffSummary() {
    final item = state;
    if (item == null) return 'No active work item.';
    final profile = ref.read(projectProfileProvider);
    final run = ref.read(agentRunProvider).latestRun;
    final errors = [
      for (final step in item.steps)
        if (step.error != null) step.error!,
      if (run?.error != null) run!.error!,
    ];
    return WorkItemHandoffSummary(
      goal: item.prompt,
      status: item.status.name,
      context: [
        if (profile.rootPath != null) profile.rootPath!,
        profile.primaryType.label,
        ...profile.projectTypes.map((type) => type.label).take(4),
      ],
      changedFiles: item.changedFiles,
      commandsRun: run?.commandSummaries ?? const [],
      verificationResults: item.verificationResults,
      run: run,
      errors: errors,
      nextSteps: item.suggestedNextSteps,
    ).serialize();
  }

  List<WorkItemStep> _defaultSteps(String prompt, String projectType) {
    return [
      WorkItemStep(
        id: _uuid.v4().substring(0, 8),
        title: 'Understand scope',
        detail:
            'Use the project profile and visible files for $projectType context.',
      ),
      WorkItemStep(
        id: _uuid.v4().substring(0, 8),
        title: 'Execute change',
        detail: prompt,
      ),
      WorkItemStep(
        id: _uuid.v4().substring(0, 8),
        title: 'Verify and summarize',
        detail: 'Run recommended checks and prepare a handoff summary.',
      ),
    ];
  }

  List<WorkItemStep> _markStep(
    List<WorkItemStep> steps,
    int index, {
    bool? completed,
    bool? running,
    String? result,
    String? error,
  }) {
    if (index < 0 || index >= steps.length) return steps;
    return [
      for (var i = 0; i < steps.length; i++)
        if (i == index)
          steps[i].copyWith(
            completed: completed,
            running: running,
            result: result,
            error: error,
          )
        else
          steps[i],
    ];
  }

  String _executionPrompt(WorkItem item) {
    return [
      'Guided work item:',
      item.prompt,
      '',
      'Use the current project profile and visible context.',
      'After making changes, explain files changed and verification commands to run.',
    ].join('\n');
  }

  List<String> _changedFiles() {
    final git = ref.read(gitProvider).status;
    return {
      ...git.staged.map((change) => change.path),
      ...git.unstaged.map((change) => change.path),
      ...git.untracked.map((change) => change.path),
    }.toList();
  }
}

final workItemProvider = NotifierProvider<WorkItemController, WorkItem?>(
  WorkItemController.new,
);

extension _Pipe<T> on T {
  R let<R>(R Function(T value) transform) => transform(this);
}
