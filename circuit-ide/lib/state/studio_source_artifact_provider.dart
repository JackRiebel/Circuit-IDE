import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/studio_feature_flags.dart';
import '../models/command_run.dart';
import '../models/generated_artifact.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_source_artifact.dart';
import '../models/studio_thread.dart';
import '../models/studio_turn.dart';
import '../services/generated_artifact_exporter.dart';
import '../services/generated_artifact_writer.dart';
import 'command_run_provider.dart';
import 'patch_proposal_provider.dart';
import 'studio_thread_provider.dart';

class StudioSourceArtifactState {
  final List<StudioSourceArtifact> artifacts;

  const StudioSourceArtifactState({this.artifacts = const []});

  StudioSourceArtifact? byId(String? id) {
    if (id == null) return null;
    for (final artifact in artifacts) {
      if (artifact.id == id) return artifact;
    }
    return null;
  }

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

class StudioSourceArtifactThreadView {
  final List<StudioSourceArtifact> artifacts;
  final String _fingerprint;

  StudioSourceArtifactThreadView(List<StudioSourceArtifact> artifacts)
    : artifacts = List.unmodifiable(artifacts),
      _fingerprint = _artifactListFingerprint(artifacts);

  bool get isEmpty => artifacts.isEmpty;

  @override
  bool operator ==(Object other) {
    return other is StudioSourceArtifactThreadView &&
        _fingerprint == other._fingerprint;
  }

  @override
  int get hashCode => _fingerprint.hashCode;
}

class StudioSourceArtifactController
    extends Notifier<StudioSourceArtifactState> {
  final Map<String, String> _threadSyncFingerprints = {};
  final Map<String, String> _patchSyncFingerprints = {};
  final Set<String> _artifactMaterializationInFlight = {};
  final GeneratedArtifactWriter _generatedArtifactWriter =
      const GeneratedArtifactWriter();
  final GeneratedArtifactExporter _generatedArtifactExporter =
      const GeneratedArtifactExporter();

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

  List<GeneratedArtifactKind> supportedExportTargets(
    GeneratedArtifact artifact,
  ) {
    return _generatedArtifactExporter.supportedTargets(artifact);
  }

  Future<GeneratedArtifact?> exportGeneratedArtifact(
    GeneratedArtifact artifact,
    GeneratedArtifactKind targetKind,
  ) async {
    final exported = await _generatedArtifactExporter.export(
      artifact: artifact,
      targetKind: targetKind,
    );
    if (exported == null) return null;
    _upsertArtifact(exported.toSourceArtifact());
    final threadId = exported.threadId;
    if (threadId != null) {
      final thread = ref
          .read(studioThreadProvider)
          .threads
          .where((thread) => thread.id == threadId)
          .firstOrNull;
      final turn = thread?.turns
          .where((turn) => turn.requestId == exported.requestId)
          .firstOrNull;
      if (turn != null) {
        ref
            .read(studioThreadProvider.notifier)
            .upsertTurnEvent(
              threadId,
              turn.id,
              StudioTurnEvent.completionSummary(
                id: 'artifact-export-${exported.id}',
                turnId: turn.id,
                requestId: turn.requestId,
                threadId: threadId,
                title: 'Exported ${exported.typeLabel} file',
                detail: '${exported.summary}\nFile: ${exported.fileName}',
              ),
            );
      }
    }
    return exported;
  }

  void _syncThreads(Iterable<StudioThread> threads) {
    final activeThreadIds = <String>{};
    for (final thread in threads) {
      activeThreadIds.add(thread.id);
      final fingerprint = _threadArtifactFingerprint(thread);
      if (_threadSyncFingerprints[thread.id] == fingerprint) continue;
      _threadSyncFingerprints[thread.id] = fingerprint;
      for (final artifact in thread.sourceArtifacts) {
        _upsertArtifact(artifact, persist: false);
      }
      _syncGeneratedArtifacts(thread);
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
    _threadSyncFingerprints.removeWhere(
      (threadId, _) => !activeThreadIds.contains(threadId),
    );
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

  void _syncGeneratedArtifacts(StudioThread thread) {
    final rootPath = thread.contextSummary?.rootPath;
    if (rootPath == null || rootPath.trim().isEmpty) return;
    final existingIds = {
      for (final artifact in thread.sourceArtifacts)
        if (artifact.kind == StudioSourceArtifactKind.generatedArtifact)
          artifact.id,
    };
    for (final turn in thread.turns) {
      final artifactId = 'generated-${turn.id}';
      if (existingIds.contains(artifactId)) continue;
      if (_artifactMaterializationInFlight.contains(turn.id)) continue;
      if (turn.status != StudioTurnStatus.completed) continue;
      if (!isGeneratedArtifactRequest(turn.prompt)) continue;
      final content = _assistantContentForTurn(turn);
      if (content.trim().isEmpty) continue;
      _artifactMaterializationInFlight.add(turn.id);
      unawaited(
        _materializeGeneratedArtifact(
          rootPath: rootPath,
          thread: thread,
          turn: turn,
          content: content,
        ),
      );
    }
  }

  Future<void> _materializeGeneratedArtifact({
    required String rootPath,
    required StudioThread thread,
    required StudioTurn turn,
    required String content,
  }) async {
    try {
      final artifact = await _generatedArtifactWriter.writeFromAssistantOutput(
        rootPath: rootPath,
        prompt: turn.prompt,
        content: content,
        turnId: turn.id,
        threadId: thread.id,
        requestId: turn.requestId,
      );
      if (artifact == null) return;
      final sourceArtifact = artifact.toSourceArtifact();
      _upsertArtifact(sourceArtifact);
      ref
          .read(studioThreadProvider.notifier)
          .upsertTurnEvent(
            thread.id,
            turn.id,
            StudioTurnEvent.completionSummary(
              id: 'artifact-${turn.id}',
              turnId: turn.id,
              requestId: turn.requestId,
              threadId: thread.id,
              title: 'Created ${artifact.typeLabel} file',
              detail: '${artifact.summary}\nFile: ${artifact.fileName}',
            ),
          );
    } finally {
      _artifactMaterializationInFlight.remove(turn.id);
    }
  }

  String _assistantContentForTurn(StudioTurn turn) {
    final events = turn.events.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    for (final event in events) {
      if (event.type != StudioTurnEventType.assistantMessage) continue;
      final content = (event.content ?? '').trim();
      if (content.isNotEmpty) return content;
    }
    return turn.assistantDraft.trim();
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
          logPath: _commandLogPathFromDetail(event.detail),
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
    String? logPath,
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
        filePath: logPath,
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
      final fingerprint = _patchArtifactFingerprint(patch);
      if (_patchSyncFingerprints[patch.id] == fingerprint) continue;
      _patchSyncFingerprints[patch.id] = fingerprint;
      _syncPatch(patch);
    }
    _patchSyncFingerprints.removeWhere((patchId, _) => !seen.contains(patchId));
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
              !trimmed.startsWith('exit code:') &&
              !trimmed.startsWith('full log:');
        })
        .join('\n')
        .trim();
  }

  String? _commandLogPathFromDetail(String detail) {
    for (final line in detail.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('full log:')) {
        final path = trimmed.substring('full log:'.length).trim();
        return path.isEmpty ? null : path;
      }
    }
    return null;
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
    if (_isQuarantinedArtifact(artifact)) return;
    final existing = state.artifacts
        .where((candidate) => candidate.id == artifact.id)
        .firstOrNull;
    if (existing != null && _sameArtifactContent(existing, artifact)) return;
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

  bool _isQuarantinedArtifact(StudioSourceArtifact artifact) {
    if (StudioFeatureFlags.advancedStudioSurfaces) return false;
    return artifact.kind == StudioSourceArtifactKind.browserComment;
  }

  String _threadArtifactFingerprint(StudioThread thread) {
    final buffer = StringBuffer()
      ..write(thread.id)
      ..write('|')
      ..write(thread.sourceArtifacts.length)
      ..write('|')
      ..write(thread.contextSummary?.title ?? '')
      ..write('|')
      ..write(thread.contextSummary?.detail ?? '')
      ..write('|')
      ..write(thread.contextSummary?.selectedFiles.join(',') ?? '')
      ..write('|')
      ..write(thread.turns.length);
    for (final artifact in thread.sourceArtifacts) {
      buffer
        ..write('|a:')
        ..write(artifact.id)
        ..write(':')
        ..write(artifact.value.hashCode);
    }
    for (final turn in thread.turns) {
      buffer
        ..write('|t:')
        ..write(turn.id)
        ..write(':')
        ..write(turn.events.length);
      for (final event in turn.events) {
        if (event.type != StudioTurnEventType.completionSummary) continue;
        if (!event.id.startsWith('command-run-')) continue;
        buffer
          ..write(':c:')
          ..write(event.id)
          ..write(':')
          ..write(event.title.hashCode)
          ..write(':')
          ..write(event.detail.hashCode);
      }
    }
    return buffer.toString();
  }

  String _patchArtifactFingerprint(ProposedPatchSet patch) {
    final buffer = StringBuffer()
      ..write(patch.id)
      ..write('|')
      ..write(patch.title)
      ..write('|')
      ..write(patch.runId ?? '')
      ..write('|')
      ..write(patch.agentTaskId ?? '')
      ..write('|')
      ..write(patch.comparisonSummary ?? '')
      ..write('|')
      ..write(patch.edits.length);
    for (final edit in patch.edits) {
      buffer
        ..write('|e:')
        ..write(edit.path)
        ..write(':')
        ..write(edit.type.name)
        ..write(':')
        ..write((edit.unifiedDiff ?? edit.after ?? edit.before ?? '').hashCode);
    }
    return buffer.toString();
  }

  bool _sameArtifactContent(
    StudioSourceArtifact existing,
    StudioSourceArtifact next,
  ) {
    return existing.kind == next.kind &&
        existing.title == next.title &&
        existing.subtitle == next.subtitle &&
        existing.value == next.value &&
        existing.threadId == next.threadId &&
        existing.requestId == next.requestId &&
        existing.relatedMessageId == next.relatedMessageId &&
        existing.filePath == next.filePath &&
        existing.localUrl == next.localUrl &&
        existing.commandRunId == next.commandRunId &&
        existing.patchSetId == next.patchSetId;
  }
}

final studioSourceArtifactProvider =
    NotifierProvider<StudioSourceArtifactController, StudioSourceArtifactState>(
      StudioSourceArtifactController.new,
    );

final studioSourceArtifactsForThreadProvider =
    Provider.family<StudioSourceArtifactThreadView, String?>((ref, threadId) {
      final artifacts = ref.watch(
        studioSourceArtifactProvider.select(
          (state) => state.forThread(threadId),
        ),
      );
      return StudioSourceArtifactThreadView(artifacts);
    });

final studioSourceArtifactByIdProvider =
    Provider.family<StudioSourceArtifact?, String?>((ref, artifactId) {
      return ref.watch(
        studioSourceArtifactProvider.select((state) => state.byId(artifactId)),
      );
    });

String _artifactListFingerprint(List<StudioSourceArtifact> artifacts) {
  final buffer = StringBuffer()..write(artifacts.length);
  for (final artifact in artifacts) {
    buffer
      ..write('|')
      ..write(artifact.id)
      ..write(':')
      ..write(artifact.kind.name)
      ..write(':')
      ..write(artifact.title.hashCode)
      ..write(':')
      ..write(artifact.subtitle.hashCode)
      ..write(':')
      ..write(artifact.value.hashCode)
      ..write(':')
      ..write(artifact.filePath ?? '')
      ..write(':')
      ..write(artifact.patchSetId ?? '')
      ..write(':')
      ..write(artifact.commandRunId ?? '');
  }
  return buffer.toString();
}
