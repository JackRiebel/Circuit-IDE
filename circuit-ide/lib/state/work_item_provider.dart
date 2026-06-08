import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/utils/platform_utils.dart';
import '../models/project_profile.dart';
import '../models/reviewed_edit.dart';
import '../models/work_item.dart';
import '../models/work_item_handoff_summary.dart';
import 'agent_run_provider.dart';
import 'chat_provider.dart';
import 'context_pack_provider.dart';
import 'file_tree_provider.dart';
import 'git_provider.dart';
import 'project_profile_provider.dart';

const _uuid = Uuid();

class WorkItemHistory {
  final List<WorkItem> items;
  final bool isLoading;
  final String? error;

  const WorkItemHistory({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  WorkItemHistory copyWith({
    List<WorkItem>? items,
    bool? isLoading,
    Object? error = _sentinel,
  }) {
    return WorkItemHistory(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

class WorkItemStore {
  final String baseDir;

  WorkItemStore({String? baseDir})
    : baseDir = baseDir ?? p.join(PlatformUtils.configDir, 'work_items');

  static String projectKey(String? rootPath) {
    if (rootPath == null || rootPath.isEmpty) return 'scratch';
    return base64Url.encode(utf8.encode(rootPath)).replaceAll('=', '');
  }

  String historyPath(String? rootPath) =>
      p.join(baseDir, '${projectKey(rootPath)}.json');

  Future<List<WorkItem>> load(String? rootPath) async {
    final file = File(historyPath(rootPath));
    if (!await file.exists()) return const [];
    final json = jsonDecode(await file.readAsString()) as List<dynamic>;
    return json
        .whereType<Map<String, dynamic>>()
        .map(WorkItem.fromJson)
        .nonNulls
        .toList();
  }

  Future<void> save(String? rootPath, List<WorkItem> items) async {
    final file = File(historyPath(rootPath));
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(items.take(30).map((item) => item.toJson()).toList()),
    );
  }
}

class WorkItemHistoryController extends Notifier<WorkItemHistory> {
  final _store = WorkItemStore();

  @override
  WorkItemHistory build() {
    Future.microtask(_load);
    ref.listen(fileTreeProvider, (previous, next) {
      if (previous?.rootPath != next.rootPath) _load();
    });
    return const WorkItemHistory(isLoading: true);
  }

  Future<void> _load() async {
    if (!ref.mounted) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final rootPath = ref.read(fileTreeProvider).rootPath;
      final items = await _store.load(rootPath);
      if (!ref.mounted) return;
      state = WorkItemHistory(items: items);
    } catch (error) {
      if (!ref.mounted) return;
      state = WorkItemHistory(error: error.toString());
    }
  }

  Future<void> upsert(WorkItem item) async {
    final items = [
      item,
      ...state.items.where((candidate) => candidate.id != item.id),
    ].take(30).toList();
    state = state.copyWith(items: items, isLoading: false, error: null);
    await _store.save(ref.read(fileTreeProvider).rootPath, items);
  }

  Future<void> clearProjectHistory() async {
    state = const WorkItemHistory();
    await _store.save(ref.read(fileTreeProvider).rootPath, const []);
  }
}

class WorkItemController extends Notifier<WorkItem?> {
  @override
  WorkItem? build() {
    ref.listen(fileTreeProvider, (previous, next) {
      if (previous?.rootPath != next.rootPath) {
        state = null;
      }
    });
    return null;
  }

  void start(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return;
    final profile = ref.read(projectProfileProvider);
    final contextPack = ref
        .read(contextPackProvider.notifier)
        .buildForCodingTask(prompt: trimmed);
    final checks = ref
        .read(projectProfileProvider.notifier)
        .recommendedChecks();
    state = WorkItem(
      id: _uuid.v4().substring(0, 8),
      prompt: trimmed,
      status: WorkItemStatus.ready,
      steps: _defaultSteps(trimmed, profile.primaryType.label),
      contextPreview: contextPack.visibleItems
          .map((item) => '${item.title}: ${item.detail}')
          .take(8)
          .toList(),
      artifacts: [
        WorkItemArtifact(
          id: contextPack.id,
          type: WorkItemArtifactType.context,
          title: 'Context pack',
          detail:
              '${contextPack.visibleItems.length} items · ~${contextPack.estimatedTokens} tokens',
          createdAt: DateTime.now(),
        ),
      ],
      verificationCommands: checks,
      createdAt: DateTime.now(),
    );
    _persist();
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
    _persist();
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
    _persist();
  }

  void cancel() {
    final item = state;
    if (item == null) return;
    state = item.copyWith(status: WorkItemStatus.cancelled);
    _persist();
  }

  void clear() {
    state = null;
  }

  void recordPatchSet(ProposedPatchSet patchSet) {
    final item = state;
    if (item == null) return;
    final checkpointIds = {
      ...item.checkpointIds,
      if (patchSet.checkpointId != null) patchSet.checkpointId!,
    }.toList();
    state = item.copyWith(
      patchSetIds: {...item.patchSetIds, patchSet.id}.toList(),
      checkpointIds: checkpointIds,
      changedFiles: {...item.changedFiles, ...patchSet.changedFiles}.toList(),
      artifacts: _upsertArtifact(
        item.artifacts,
        WorkItemArtifact(
          id: patchSet.id,
          type: WorkItemArtifactType.patchSet,
          title: patchSet.title,
          detail:
              '${patchSet.approvalStatus.name} · ${patchSet.fileCount} files',
          createdAt: DateTime.now(),
        ),
      ),
    );
    _persist();
  }

  void recordCommandRun(String commandRunId, String command) {
    final item = state;
    if (item == null) return;
    state = item.copyWith(
      commandRunIds: {...item.commandRunIds, commandRunId}.toList(),
      artifacts: _upsertArtifact(
        item.artifacts,
        WorkItemArtifact(
          id: commandRunId,
          type: WorkItemArtifactType.commandRun,
          title: 'Command run',
          detail: command,
          createdAt: DateTime.now(),
        ),
      ),
    );
    _persist();
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
        ...item.contextPreview.take(6),
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
    final contextPack = ref.read(contextPackProvider);
    final contextPrompt = contextPack?.serializePrompt();
    return [
      'Guided work item:',
      item.prompt,
      '',
      if (contextPrompt != null && contextPrompt.isNotEmpty) contextPrompt,
      '',
      'Use review-first autonomy. Prefer proposing patches before writing files.',
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

  void _persist() {
    final item = state;
    if (item == null) return;
    ref.read(workItemHistoryProvider.notifier).upsert(item);
  }
}

final workItemProvider = NotifierProvider<WorkItemController, WorkItem?>(
  WorkItemController.new,
);

final workItemHistoryProvider =
    NotifierProvider<WorkItemHistoryController, WorkItemHistory>(
      WorkItemHistoryController.new,
    );

extension _Pipe<T> on T {
  R let<R>(R Function(T value) transform) => transform(this);
}

List<WorkItemArtifact> _upsertArtifact(
  List<WorkItemArtifact> artifacts,
  WorkItemArtifact artifact,
) {
  return [
    artifact,
    ...artifacts.where((candidate) => candidate.id != artifact.id),
  ];
}

const _sentinel = Object();
