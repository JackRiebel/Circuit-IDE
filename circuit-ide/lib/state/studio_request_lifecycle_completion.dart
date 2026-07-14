part of 'studio_request_lifecycle_provider.dart';

/// Research evidence, completion summaries, and their durable turn handoff.
///
/// Kept separate from the request/event controller so the high-frequency
/// lifecycle state machine stays focused on event routing and watchdogs.
abstract class _StudioRequestLifecycleCompletionController
    extends Notifier<StudioRequestLifecycleState> {
  StudioRequestLifecycleEntry? _entryFor(Event event);

  void _finish(
    StudioRequestLifecycleEntry entry,
    StudioRequestLifecycleEventKind kind,
    String detail,
  );

  String _preview(String content);

  void _handleMessageCompleted(Event event) {
    final entry = _entryFor(event);
    if (entry == null) return;
    final content = event.data['content'] as String? ?? '';
    final researchReport = _materializeDeepResearchEvidence(entry, content);
    final completionContent = researchReport == null
        ? content
        : _researchChatHandoff(content, researchReport);
    unawaited(_addCompletionSummary(entry, content: completionContent));
    if (content.trim().isNotEmpty) {
      for (final url in detectLocalUrls(content)) {
        ref
            .read(studioThreadProvider.notifier)
            .upsertSourceArtifact(
              entry.threadId,
              StudioSourceArtifact(
                id: 'assistant-url-${entry.threadId}-${entry.requestId}-$url',
                kind: StudioSourceArtifactKind.localUrl,
                title: Uri.tryParse(url)?.host ?? 'Local preview',
                subtitle: url,
                value: url,
                threadId: entry.threadId,
                requestId: entry.requestId,
                localUrl: url,
                createdAt: DateTime.now(),
              ),
            );
      }
    }
    final usage = event.data['lastUsage'] as TokenUsage?;
    // The runner owns the durable, request-total increment once it has
    // combined every provider/tool round. This lifecycle event is emitted
    // before that result is available, so it may only refresh the
    // request-local display. Adding this partial/last-round value here would
    // count the same request a second time when the runner completes.
    if (usage != null) {
      ref
          .read(studioThreadProvider.notifier)
          .updateTokenUsage(entry.threadId, usage);
    }
    ref.read(studioThreadProvider.notifier).complete(entry.threadId);
    if (entry.taskId != null) {
      ref
          .read(agentWorkspaceProvider.notifier)
          .completeTask(entry.taskId!, result: _preview(content));
    }
    _finish(entry, StudioRequestLifecycleEventKind.completed, 'Completed.');
  }

  DeepResearchReport? _materializeDeepResearchEvidence(
    StudioRequestLifecycleEntry entry,
    String content,
  ) {
    final turn = _turnForRequest(entry.requestId);
    if (turn == null) return null;
    final report = const DeepResearchReportBuilder().build(
      turn: turn,
      content: content,
    );
    if (report == null) return null;
    ref
        .read(studioThreadProvider.notifier)
        .upsertSourceArtifact(entry.threadId, report.artifact);
    ref
        .read(studioTurnProvider.notifier)
        .completeResearch(
          entry.requestId,
          directSourceCount: report.directSourceCount,
          unsupportedClaimCount: report.unsupportedClaimCount,
          freshnessGapCount: report.freshnessGapCount,
        );
    return report;
  }

  String _researchChatHandoff(String content, DeepResearchReport report) {
    final answer = content
        .split(
          RegExp(
            r'^##\s+(?:Evidence\s+table|Sources)\b.*$',
            caseSensitive: false,
            multiLine: true,
          ),
        )
        .first
        .trim();
    final conciseAnswer = answer.length <= 2400
        ? answer
        : '${answer.substring(0, 2399).trimRight()}…';
    final gapSummary = [
      if (report.unsupportedClaimCount > 0)
        '${report.unsupportedClaimCount} unsupported ${report.unsupportedClaimCount == 1 ? 'statement' : 'statements'}',
      if (report.freshnessGapCount > 0)
        '${report.freshnessGapCount} freshness ${report.freshnessGapCount == 1 ? 'review' : 'reviews'}',
      if (report.singlePublisherClaimCount > 0)
        '${report.singlePublisherClaimCount} single-publisher ${report.singlePublisherClaimCount == 1 ? 'claim' : 'claims'}',
    ];
    return [
      if (conciseAnswer.isNotEmpty) conciseAnswer,
      'Research evidence report saved in Sources · ${report.directSourceCount} direct ${report.directSourceCount == 1 ? 'source' : 'sources'}${gapSummary.isEmpty ? '' : ' · ${gapSummary.join(' · ')}'}.',
    ].join('\n\n');
  }

  Future<void> _addCompletionSummary(
    StudioRequestLifecycleEntry entry, {
    required String content,
  }) async {
    final turn = _turnForRequest(entry.requestId);
    final rootPath = entry.contextSummary.rootPath;
    final gitSummary = await _gitChangeSummary(rootPath);
    if (!ref.mounted) return;
    final detail = const TurnCompletionSummaryBuilder().build(
      toolResults: turn?.toolResults ?? const [],
      providerDiagnostics: turn?.providerDiagnostics ?? const [],
      acceptedPlanState: turn?.acceptedPlanState ?? AcceptedPlanState.none,
      gitChangeSummary: gitSummary,
    );
    final lifecycleEntry = state.find(entry.requestId);
    final allowArchived =
        lifecycleEntry?.lastEventKind ==
        StudioRequestLifecycleEventKind.completed;
    if (!allowArchived && state.active(entry.requestId) == null) return;
    ref
        .read(studioTurnProvider.notifier)
        .complete(
          entry.requestId,
          content: content,
          summary: detail,
          allowArchived: allowArchived,
        );
  }

  StudioTurn? _turnForRequest(String requestId) {
    final turnRef = ref
        .read(studioTurnProvider)
        .archivedRefForRequest(requestId);
    if (turnRef == null) return null;
    final thread = ref
        .read(studioThreadProvider)
        .threads
        .where((candidate) => candidate.id == turnRef.threadId)
        .firstOrNull;
    return thread?.turns
        .where((candidate) => candidate.id == turnRef.turnId)
        .firstOrNull;
  }

  Future<String?> _gitChangeSummary(String? rootPath) async {
    if (rootPath == null || rootPath.trim().isEmpty) return null;
    try {
      final gitDir = Directory('$rootPath/.git');
      if (!await gitDir.exists()) return null;
      final status = await Process.run('git', [
        '-C',
        rootPath,
        'status',
        '--short',
      ]).timeout(const Duration(seconds: 2));
      final lines = (status.stdout as String)
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList(growable: false);
      if (lines.isEmpty) return 'No file changes detected.';

      final numstat = await Process.run('git', [
        '-C',
        rootPath,
        'diff',
        '--numstat',
      ]).timeout(const Duration(seconds: 2));
      var additions = 0;
      var deletions = 0;
      for (final line in (numstat.stdout as String).split('\n')) {
        final parts = line.split('\t');
        if (parts.length < 3) continue;
        additions += int.tryParse(parts[0]) ?? 0;
        deletions += int.tryParse(parts[1]) ?? 0;
      }
      final fileLabel = lines.length == 1
          ? '1 file changed'
          : '${lines.length} files changed';
      final delta = additions == 0 && deletions == 0
          ? ''
          : ' +$additions -$deletions';
      return '$fileLabel$delta';
    } catch (_) {
      return null;
    }
  }
}
