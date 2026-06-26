import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/command_run.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_source_artifact.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import 'command_run_provider.dart';
import 'patch_proposal_provider.dart';
import 'studio_thread_provider.dart';

class StudioSourceArtifactState {
  final List<StudioSourceArtifact> artifacts;

  const StudioSourceArtifactState({this.artifacts = const []});

  List<StudioSourceArtifact> forThread(String? threadId) {
    return artifacts
        .where(
          (artifact) =>
              artifact.threadId == null || artifact.threadId == threadId,
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}

class StudioSourceArtifactController
    extends Notifier<StudioSourceArtifactState> {
  @override
  StudioSourceArtifactState build() {
    ref.listen(studioThreadProvider, (_, next) => _syncThreads(next.threads));
    ref.listen(commandRunProvider, (_, next) => _syncCommands(next.values));
    ref.listen(patchProposalProvider, (_, next) => _syncPatches(next));
    Future.microtask(() {
      _syncThreads(ref.read(studioThreadProvider).threads);
      _syncCommands(ref.read(commandRunProvider).values);
      _syncPatches(ref.read(patchProposalProvider));
    });
    return const StudioSourceArtifactState();
  }

  void add(StudioSourceArtifact artifact) {
    _upsert(artifact);
  }

  void _syncThreads(Iterable<StudioThread> threads) {
    for (final thread in threads) {
      for (final artifact in thread.sourceArtifacts) {
        _upsertArtifact(artifact, persist: false);
      }
      _syncPersistedCommandEvents(thread);
      final summary = thread.contextSummary;
      if (summary == null) continue;
      _upsertArtifact(
        StudioSourceArtifact(
          id: 'context-${thread.id}',
          kind: StudioSourceArtifactKind.toolResult,
          title: summary.title,
          subtitle: summary.projectLabel,
          value: summary.detail,
          threadId: thread.id,
          requestId: thread.requestId,
          createdAt: thread.updatedAt,
        ),
        persist: false,
      );
      for (final file in summary.selectedFiles) {
        _upsertArtifact(
          StudioSourceArtifact(
            id: 'file-${thread.id}-$file',
            kind: StudioSourceArtifactKind.file,
            title: file,
            subtitle: 'Context file',
            value: file,
            threadId: thread.id,
            requestId: thread.requestId,
            filePath: file,
            createdAt: thread.updatedAt,
          ),
          persist: false,
        );
      }
    }
  }

  void _syncCommands(Iterable<CommandRun> commands) {
    for (final command in commands) {
      final thread = _threadForCommand(command);
      _upsertCommandArtifact(
        id: command.id,
        command: command.command,
        status: command.status.name,
        output: command.combinedOutput,
        thread: thread,
        requestId: command.requestId,
        createdAt: command.startedAt,
      );
    }
  }

  void _syncPersistedCommandEvents(StudioThread thread) {
    for (final turn in thread.turns) {
      for (final event in turn.events) {
        if (event.type != StudioTurnEventType.completionSummary) continue;
        if (!event.id.startsWith('command-run-')) continue;
        final command = _commandLineFromDetail(event.detail);
        if (command == null) continue;
        final commandRunId = _commandRunIdFromEvent(turn, event);
        _upsertCommandArtifact(
          id: commandRunId,
          command: command,
          status: _commandRunStatusFromTitle(event.title),
          output: _commandOutputFromDetail(event.detail),
          thread: thread,
          requestId: event.requestId,
          createdAt: event.timestamp,
          persist: false,
        );
      }
    }
  }

  void _upsertCommandArtifact({
    required String id,
    required String command,
    required String status,
    required String output,
    required StudioThread? thread,
    required String? requestId,
    required DateTime createdAt,
    bool persist = true,
  }) {
    _upsertArtifact(
      StudioSourceArtifact(
        id: 'command-$id',
        kind: StudioSourceArtifactKind.command,
        title: command,
        subtitle: status,
        value: output,
        threadId: thread?.id,
        requestId: requestId ?? thread?.requestId,
        commandRunId: id,
        createdAt: createdAt,
      ),
      persist: persist,
    );
    final urls = detectLocalUrls('$command\n$output');
    for (final url in urls) {
      _upsertArtifact(
        StudioSourceArtifact(
          id: 'url-$id-$url',
          kind: StudioSourceArtifactKind.localUrl,
          title: Uri.tryParse(url)?.host ?? 'Local preview',
          subtitle: url,
          value: url,
          threadId: thread?.id,
          requestId: requestId ?? thread?.requestId,
          localUrl: url,
          commandRunId: id,
          createdAt: createdAt,
        ),
        persist: persist,
      );
    }
  }

  void _syncPatches(PatchProposalState patchState) {
    final seen = <String>{};
    final patches = [
      if (patchState.active != null) patchState.active!,
      ...patchState.history,
    ];
    for (final patch in patches) {
      if (!seen.add(patch.id)) continue;
      _syncPatch(patch);
    }
  }

  void _syncPatch(ProposedPatchSet patch) {
    final thread = _threadForPatch(patch);
    final requestId = patch.runId ?? thread?.requestId;
    _upsert(
      StudioSourceArtifact(
        id: 'patch-${patch.id}',
        kind: StudioSourceArtifactKind.patch,
        title: patch.title,
        subtitle: '${patch.fileCount} files',
        value: patch.comparisonSummary ?? 'Patch ready for review',
        threadId: thread?.id,
        requestId: requestId,
        patchSetId: patch.id,
        createdAt: patch.createdAt,
      ),
    );
    for (final edit in patch.edits) {
      _upsert(
        StudioSourceArtifact(
          id: 'diff-${patch.id}-${edit.path}',
          kind: StudioSourceArtifactKind.diff,
          title: edit.path,
          subtitle: edit.type.name,
          value: edit.unifiedDiff ?? edit.after ?? edit.before ?? '',
          threadId: thread?.id,
          requestId: requestId,
          filePath: edit.path,
          patchSetId: patch.id,
          createdAt: patch.createdAt,
        ),
      );
    }
  }

  StudioThread? _threadForPatch(ProposedPatchSet patch) {
    final threadState = ref.read(studioThreadProvider);
    final runId = patch.runId?.trim();
    if (runId != null && runId.isNotEmpty) {
      for (final thread in threadState.threads) {
        if (thread.requestId == runId ||
            thread.turns.any((turn) => turn.requestId == runId)) {
          return thread;
        }
      }
    }
    final taskId = patch.agentTaskId?.trim();
    if (taskId != null && taskId.isNotEmpty) {
      final thread = threadState.threadForTask(taskId);
      if (thread != null) return thread;
    }
    return threadState.selectedThread;
  }

  StudioThread? _threadForCommand(CommandRun command) {
    final threadState = ref.read(studioThreadProvider);
    final requestId = command.requestId?.trim();
    final turnId = command.turnId?.trim();
    if ((requestId != null && requestId.isNotEmpty) ||
        (turnId != null && turnId.isNotEmpty)) {
      for (final thread in threadState.threads) {
        if (requestId != null &&
            requestId.isNotEmpty &&
            thread.requestId == requestId) {
          return thread;
        }
        if (thread.turns.any(
          (turn) =>
              (requestId != null &&
                  requestId.isNotEmpty &&
                  turn.requestId == requestId) ||
              (turnId != null && turnId.isNotEmpty && turn.id == turnId),
        )) {
          return thread;
        }
      }
    }
    final taskId = command.taskId?.trim();
    if (taskId != null && taskId.isNotEmpty) {
      final thread = threadState.threadForTask(taskId);
      if (thread != null) return thread;
    }
    return threadState.selectedThread;
  }

  String _commandRunIdFromEvent(StudioTurn turn, StudioTurnEvent event) {
    final prefix = 'command-run-${turn.id}-';
    if (event.id.startsWith(prefix) && event.id.length > prefix.length) {
      return event.id.substring(prefix.length);
    }
    return event.id;
  }

  String? _commandLineFromDetail(String detail) {
    for (final line in detail.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('command:')) {
        final command = trimmed.substring('command:'.length).trim();
        return command.isEmpty ? null : command;
      }
    }
    return null;
  }

  String _commandOutputFromDetail(String detail) {
    final lines = detail.split('\n');
    return lines
        .where((line) {
          final trimmed = line.trimLeft().toLowerCase();
          return !trimmed.startsWith('command:') &&
              !trimmed.startsWith('exit code:');
        })
        .join('\n')
        .trim();
  }

  String _commandRunStatusFromTitle(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('cancel')) return 'cancelled';
    if (normalized.contains('timeout') || normalized.contains('timed out')) {
      return 'timedOut';
    }
    if (normalized.contains('blocked')) return 'blocked';
    if (normalized.contains('failed') || normalized.contains('error')) {
      return 'failed';
    }
    return 'succeeded';
  }

  void _upsert(StudioSourceArtifact artifact) {
    _upsertArtifact(artifact);
  }

  void _upsertArtifact(StudioSourceArtifact artifact, {bool persist = true}) {
    final artifacts = [
      artifact,
      ...state.artifacts.where((candidate) => candidate.id != artifact.id),
    ];
    state = StudioSourceArtifactState(artifacts: artifacts);
    final threadId = artifact.threadId;
    if (!persist || threadId == null) return;
    ref
        .read(studioThreadProvider.notifier)
        .upsertSourceArtifact(threadId, artifact);
  }
}

final studioSourceArtifactProvider =
    NotifierProvider<StudioSourceArtifactController, StudioSourceArtifactState>(
      StudioSourceArtifactController.new,
    );
