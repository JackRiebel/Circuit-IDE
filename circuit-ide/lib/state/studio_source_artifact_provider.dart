import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/command_run.dart';
import '../models/reviewed_edit.dart';
import '../models/studio_source_artifact.dart';
import '../models/studio_thread.dart';
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
    ref.listen(patchProposalProvider, (_, next) {
      final patch = next.active;
      if (patch != null) _syncPatch(patch);
    });
    Future.microtask(() {
      _syncThreads(ref.read(studioThreadProvider).threads);
      _syncCommands(ref.read(commandRunProvider).values);
      final patch = ref.read(patchProposalProvider).active;
      if (patch != null) _syncPatch(patch);
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
    final thread = ref.read(studioThreadProvider).selectedThread;
    for (final command in commands) {
      _upsert(
        StudioSourceArtifact(
          id: 'command-${command.id}',
          kind: StudioSourceArtifactKind.command,
          title: command.command,
          subtitle: command.status.name,
          value: command.combinedOutput,
          threadId: thread?.id,
          requestId: thread?.requestId,
          commandRunId: command.id,
          createdAt: command.startedAt,
        ),
      );
      final urls = detectLocalUrls(
        '${command.command}\n${command.combinedOutput}',
      );
      for (final url in urls) {
        _upsert(
          StudioSourceArtifact(
            id: 'url-${command.id}-$url',
            kind: StudioSourceArtifactKind.localUrl,
            title: Uri.tryParse(url)?.host ?? 'Local preview',
            subtitle: url,
            value: url,
            threadId: thread?.id,
            requestId: thread?.requestId,
            localUrl: url,
            commandRunId: command.id,
            createdAt: command.startedAt,
          ),
        );
      }
    }
  }

  void _syncPatch(ProposedPatchSet patch) {
    final thread = ref.read(studioThreadProvider).selectedThread;
    _upsert(
      StudioSourceArtifact(
        id: 'patch-${patch.id}',
        kind: StudioSourceArtifactKind.patch,
        title: patch.title,
        subtitle: '${patch.fileCount} files',
        value: patch.comparisonSummary ?? 'Patch ready for review',
        threadId: thread?.id,
        requestId: thread?.requestId,
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
          requestId: thread?.requestId,
          filePath: edit.path,
          patchSetId: patch.id,
          createdAt: patch.createdAt,
        ),
      );
    }
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
