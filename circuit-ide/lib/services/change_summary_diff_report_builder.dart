import '../models/artifact_document.dart';

class ChangeSummaryDiffReportBuilder {
  const ChangeSummaryDiffReportBuilder();

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(change summary|diff report|verification summary|post[- ]work summary|post[- ]work report|work summary|completion summary|implementation summary|patch summary|checkpoint report|release summary)\b',
    ).hasMatch(normalized);
  }

  ArtifactDocument build({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    final changedFiles = _changedFiles(content, document);
    final verification = _verificationSignals(content);
    final commands = _commands(content);
    final checkpoints = _checkpoints(content);
    final blockers = _importantLines(content, const [
      'risk',
      'blocker',
      'failed',
      'conflict',
      'missing',
      'stale',
    ]);
    final nextSteps = _importantLines(content, const [
      'next',
      'follow',
      'todo',
      'remaining',
      'recommend',
    ]);
    final sections = <ArtifactSection>[
      _section(
        document,
        title: 'Outcome Summary',
        patterns: const ['summary', 'outcome', 'overview'],
        fallbackBody: document.summary,
      ),
      _section(
        document,
        title: 'Files Changed',
        patterns: const ['files changed', 'changed files', 'edited files'],
        fallbackBody: changedFiles.isEmpty
            ? 'No changed files were explicitly listed in the source summary.'
            : 'Captured ${changedFiles.length} changed file target${changedFiles.length == 1 ? '' : 's'} from the work summary.',
        fallbackBullets: changedFiles,
      ),
      _section(
        document,
        title: 'Diff / Patch Summary',
        patterns: const ['diff', 'patch', 'prepared changes', 'applied'],
        fallbackBody:
            'Summarize the prepared or applied patch, line deltas, review state, and any conflict or revision status.',
      ),
      _section(
        document,
        title: 'Verification Results',
        patterns: const ['verification', 'verified', 'tests', 'checks'],
        fallbackBody: verification.isEmpty
            ? 'Verification evidence was not explicitly listed.'
            : 'Captured ${verification.length} verification signal${verification.length == 1 ? '' : 's'} from the work summary.',
        fallbackBullets: verification,
      ),
      _section(
        document,
        title: 'Commands Run',
        patterns: const ['commands', 'ran', 'checks'],
        fallbackBody: commands.isEmpty
            ? 'No command log was explicitly listed.'
            : 'Captured ${commands.length} command${commands.length == 1 ? '' : 's'} from the work summary.',
        fallbackBullets: commands,
      ),
      _section(
        document,
        title: 'Checkpoint And Restore',
        patterns: const ['checkpoint', 'restore', 'commit'],
        fallbackBody: checkpoints.isEmpty
            ? 'No checkpoint or restore point was explicitly listed.'
            : 'Captured checkpoint and restore evidence for handoff.',
        fallbackBullets: checkpoints,
      ),
      _section(
        document,
        title: 'Failures / Blockers',
        patterns: const ['failures', 'blockers', 'risks', 'conflicts'],
        fallbackBody: blockers.isEmpty
            ? 'No open failures, blockers, or conflicts were explicitly listed.'
            : 'Capture conflicts, failed checks, stale files, missing inputs, or unresolved risks before handoff.',
        fallbackBullets: blockers,
      ),
      _section(
        document,
        title: 'Risks And Follow-Up',
        patterns: const ['risks', 'follow-up', 'next steps'],
        fallbackBody: nextSteps.isEmpty
            ? 'No follow-up items were explicitly listed.'
            : 'Track follow-up actions so the next turn starts from the right state.',
        fallbackBullets: nextSteps,
      ),
      _section(
        document,
        title: 'Sources / Evidence',
        patterns: const ['sources', 'evidence'],
        fallbackBody:
            'Attach the local diff, command output, artifacts, screenshots, citations, or test logs used to validate this summary.',
        fallbackBullets: document.citations,
      ),
    ];
    final tables = [
      ..._reportTables(
        document: document,
        changedFiles: changedFiles,
        verification: verification,
        commands: commands,
        checkpoints: checkpoints,
        blockers: blockers,
        nextSteps: nextSteps,
      ),
      ...document.tables,
    ];
    return ArtifactDocument(
      title: _title(document.title, prompt),
      summary: document.summary,
      sections: sections,
      tables: tables,
      assumptions: document.assumptions,
      citations: document.citations,
      metadata: {
        ...document.metadata,
        'artifactTemplate': 'change_summary_diff_report',
        'sourcePrompt': prompt,
        'changedFiles': changedFiles.length,
        'verificationSignals': verification.length,
        'commands': commands.length,
        'checkpoints': checkpoints.length,
      },
    );
  }

  String _title(String currentTitle, String prompt) {
    final title = currentTitle.trim();
    if (title.isNotEmpty && title != 'Generated artifact') return title;
    final cleaned = prompt
        .replaceAll(
          RegExp(
            r'\b(create|make|generate|build|export|save|write)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Change Summary / Diff Report';
    return cleaned.length > 72 ? cleaned.substring(0, 72).trim() : cleaned;
  }

  ArtifactSection _section(
    ArtifactDocument document, {
    required String title,
    required List<String> patterns,
    required String fallbackBody,
    List<String> fallbackBullets = const [],
  }) {
    final existing = _matchingSection(document.sections, patterns);
    if (existing != null) {
      return ArtifactSection(
        title: title,
        body: existing.body.trim().isEmpty ? fallbackBody : existing.body,
        bullets: existing.bullets.isEmpty ? fallbackBullets : existing.bullets,
      );
    }
    return ArtifactSection(
      title: title,
      body: fallbackBody,
      bullets: fallbackBullets,
    );
  }

  ArtifactSection? _matchingSection(
    List<ArtifactSection> sections,
    List<String> patterns,
  ) {
    for (final section in sections) {
      final normalized = section.title.toLowerCase();
      if (patterns.any(normalized.contains)) return section;
    }
    return null;
  }

  List<ArtifactTable> _reportTables({
    required ArtifactDocument document,
    required List<String> changedFiles,
    required List<String> verification,
    required List<String> commands,
    required List<String> checkpoints,
    required List<String> blockers,
    required List<String> nextSteps,
  }) {
    return [
      ArtifactTable(
        title: 'Change Outcome Summary',
        rows: [
          const ['Area', 'Count / Status', 'Handoff Note'],
          [
            'Changed files',
            changedFiles.isEmpty ? 'Not listed' : '${changedFiles.length}',
            changedFiles.isEmpty
                ? 'Attach diff or file inventory before handoff.'
                : 'Review changed-file inventory and line deltas.',
          ],
          [
            'Verification',
            verification.isEmpty ? 'Not listed' : '${verification.length}',
            verification.isEmpty
                ? 'Run or record validation before final handoff.'
                : 'Keep command evidence with the report.',
          ],
          [
            'Commands',
            commands.isEmpty ? 'Not listed' : '${commands.length}',
            'Capture stdout/stderr or CI links for important commands.',
          ],
          [
            'Open risks',
            blockers.isEmpty ? 'None listed' : '${blockers.length}',
            blockers.isEmpty
                ? 'No explicit blockers found in source text.'
                : 'Resolve or assign before closing the work.',
          ],
        ],
      ),
      ArtifactTable(
        title: 'Changed File Inventory',
        rows: [
          const ['File', 'Change Signal', 'Line Delta', 'Review Status'],
          ..._changedFileRows(changedFiles, document),
        ],
      ),
      ArtifactTable(
        title: 'Verification Result Matrix',
        rows: [
          const ['Check', 'Observed Result', 'Evidence Needed', 'Status'],
          ..._verificationRows(verification),
        ],
      ),
      ArtifactTable(
        title: 'Command Run Log',
        rows: [
          const ['Command', 'Purpose', 'Recorded Result', 'Follow-Up'],
          ..._commandRows(commands),
        ],
      ),
      ArtifactTable(
        title: 'Checkpoint Register',
        rows: [
          const ['Checkpoint / Commit', 'Purpose', 'Restore Note', 'Status'],
          ..._checkpointRows(checkpoints),
        ],
      ),
      ArtifactTable(
        title: 'Open Risk And Follow-Up Register',
        rows: [
          const ['Item', 'Type', 'Impact', 'Next Step'],
          ..._riskRows(blockers, nextSteps),
        ],
      ),
      const ArtifactTable(
        title: 'Artifact Handoff Checklist',
        rows: [
          ['Gate', 'Question', 'Expected Evidence', 'Owner'],
          [
            'Diff review',
            'Can the reviewer see exactly what changed?',
            'Changed file list and diff summary',
            'Implementation owner',
          ],
          [
            'Verification',
            'Can the reviewer prove the change works?',
            'Passed checks or explicit blockers',
            'Reviewer',
          ],
          [
            'Rollback',
            'Can the team restore prior state?',
            'Checkpoint or commit id',
            'Implementation owner',
          ],
          [
            'Follow-up',
            'Are remaining tasks assigned?',
            'Risk and next-step register',
            'Product / delivery owner',
          ],
        ],
      ),
    ];
  }

  List<List<String>> _changedFileRows(
    List<String> changedFiles,
    ArtifactDocument document,
  ) {
    if (changedFiles.isEmpty) {
      return const [
        ['Not specified', 'No file inventory found', 'Unknown', 'Needs review'],
      ];
    }
    final sourceText = _documentText(document);
    return changedFiles
        .take(40)
        .map(
          (file) => [
            file,
            _changeSignal(file, sourceText),
            _lineDelta(file, sourceText),
            'Review',
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _verificationRows(List<String> verification) {
    if (verification.isEmpty) {
      return const [
        [
          'Verification not listed',
          'No explicit result',
          'Run expected checks or attach logs',
          'Missing',
        ],
      ];
    }
    return verification
        .take(30)
        .map(
          (signal) => [
            _compact(signal, 80),
            _statusFromLine(signal),
            'Command output, CI result, screenshot, or artifact preview',
            _statusFromLine(signal),
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _commandRows(List<String> commands) {
    if (commands.isEmpty) {
      return const [
        [
          'Not listed',
          'No command run recorded',
          'Unknown',
          'Add verification command if needed',
        ],
      ];
    }
    return commands
        .take(30)
        .map(
          (command) => [
            command,
            _commandPurpose(command),
            'See verification evidence',
            _commandFollowUp(command),
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _checkpointRows(List<String> checkpoints) {
    if (checkpoints.isEmpty) {
      return const [
        [
          'Not listed',
          'Rollback evidence missing',
          'Create or reference checkpoint before risky handoff',
          'Missing',
        ],
      ];
    }
    return checkpoints
        .take(20)
        .map(
          (checkpoint) => [
            _compact(checkpoint, 90),
            'Restore / audit reference',
            'Use checkpoint or commit before applying follow-up work',
            'Recorded',
          ],
        )
        .toList(growable: false);
  }

  List<List<String>> _riskRows(List<String> blockers, List<String> nextSteps) {
    final rows = <List<String>>[];
    for (final blocker in blockers.take(16)) {
      rows.add([
        _compact(blocker, 90),
        'Risk / blocker',
        _riskImpact(blocker),
        'Resolve, re-run, or assign owner',
      ]);
    }
    for (final nextStep in nextSteps.take(16)) {
      rows.add([
        _compact(nextStep, 90),
        'Follow-up',
        'Future work / handoff clarity',
        'Schedule or execute next pass',
      ]);
    }
    if (rows.isEmpty) {
      rows.add(const [
        'None listed',
        'No explicit risk',
        'No unresolved item in source text',
        'Confirm before closeout',
      ]);
    }
    return rows;
  }

  List<String> _changedFiles(String content, ArtifactDocument document) {
    final combined = '$content\n${_documentText(document)}';
    final filePattern = RegExp(
      r'(?<![\w/.-])(?:[\w.-]+/)*[\w.-]+\.(?:dart|ts|tsx|js|jsx|py|md|json|yaml|yml|html|css|scss|swift|kt|java|go|rs|rb|php|sql|txt|csv|xlsx|pptx|docx|pdf|svg)(?![\w/.-])',
      caseSensitive: false,
    );
    final files = <String>{};
    for (final match in filePattern.allMatches(combined)) {
      final file = match.group(0)?.trim();
      if (file == null || file.isEmpty) continue;
      if (file.startsWith('http')) continue;
      files.add(file);
    }
    return files.take(80).toList(growable: false);
  }

  List<String> _verificationSignals(String content) {
    const keywords = [
      'passed',
      'failed',
      'succeeded',
      'verified',
      'analyze',
      'test',
      'build',
      'lint',
      'typecheck',
      'smoke',
      'check',
    ];
    return _importantLines(content, keywords).take(40).toList(growable: false);
  }

  List<String> _commands(String content) {
    final commands = <String>{};
    final commandPattern = RegExp(
      r'`([^`]*(?:flutter|dart|git|npm|pnpm|yarn|pytest|python|swift|xcodebuild|scripts/|make|cargo)[^`]*)`',
      caseSensitive: false,
    );
    for (final match in commandPattern.allMatches(content)) {
      final command = match.group(1)?.trim();
      if (command != null && command.isNotEmpty) commands.add(command);
    }
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim().replaceFirst(RegExp(r'^[-*]\s*'), '');
      if (RegExp(
        r'^(flutter|dart|git|npm|pnpm|yarn|pytest|python|swift|xcodebuild|scripts/|make|cargo)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        commands.add(line);
      }
    }
    return commands.take(40).toList(growable: false);
  }

  List<String> _checkpoints(String content) {
    final results = <String>{};
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (RegExp(
        r'\b(checkpoint|commit|restore|rollback)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        results.add(_compact(line.replaceFirst(RegExp(r'^[-*]\s*'), ''), 120));
      }
    }
    for (final match in RegExp(r'\b[0-9a-f]{7,40}\b').allMatches(content)) {
      results.add('Commit or checkpoint ${match.group(0)}');
    }
    return results.take(30).toList(growable: false);
  }

  List<String> _importantLines(String content, List<String> keywords) {
    final results = <String>{};
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.length < 4 || line.startsWith('|') || line.startsWith('#')) {
        continue;
      }
      final normalized = line.toLowerCase();
      if (keywords.any(normalized.contains)) {
        results.add(
          _compact(line.replaceFirst(RegExp(r'^[-*]\s*'), '').trim(), 140),
        );
      }
    }
    return results.toList(growable: false);
  }

  String _documentText(ArtifactDocument document) {
    return [
      document.title,
      document.summary,
      for (final section in document.sections) ...[
        section.title,
        section.body,
        ...section.bullets,
      ],
      for (final table in document.tables)
        for (final row in table.rows) ...row,
      ...document.assumptions,
      ...document.citations,
    ].join('\n');
  }

  String _changeSignal(String file, String text) {
    final line = _lineForFile(file, text).toLowerCase();
    if (line.contains('delete') || line.contains('removed')) return 'Deleted';
    if (line.contains('create') || line.contains('added')) return 'Created';
    if (line.contains('rename') || line.contains('move')) return 'Moved';
    if (line.contains('conflict')) return 'Conflict';
    return 'Modified';
  }

  String _lineDelta(String file, String text) {
    final line = _lineForFile(file, text);
    final add = RegExp(r'\+([0-9]+)').firstMatch(line)?.group(1);
    final del = RegExp(r'-([0-9]+)').firstMatch(line)?.group(1);
    if (add != null || del != null) {
      return '+${add ?? '0'} / -${del ?? '0'}';
    }
    return 'Unknown';
  }

  String _lineForFile(String file, String text) {
    for (final line in text.split('\n')) {
      if (line.contains(file)) return line.trim();
    }
    return '';
  }

  String _statusFromLine(String line) {
    final normalized = line.toLowerCase();
    if (normalized.contains('pass') ||
        normalized.contains('succeeded') ||
        normalized.contains('verified') ||
        normalized.contains('green')) {
      return 'Passed';
    }
    if (normalized.contains('fail') ||
        normalized.contains('error') ||
        normalized.contains('conflict')) {
      return 'Failed';
    }
    if (normalized.contains('not run') || normalized.contains('skipped')) {
      return 'Not run';
    }
    return 'Recorded';
  }

  String _commandPurpose(String command) {
    final normalized = command.toLowerCase();
    if (normalized.contains('analyze') ||
        normalized.contains('lint') ||
        normalized.contains('typecheck')) {
      return 'Static analysis';
    }
    if (normalized.contains('test') || normalized.contains('pytest')) {
      return 'Test verification';
    }
    if (normalized.contains('build')) return 'Build verification';
    if (normalized.contains('diff')) return 'Diff hygiene';
    if (normalized.contains('commit')) return 'Version control checkpoint';
    return 'Execution / inspection';
  }

  String _commandFollowUp(String command) {
    final normalized = command.toLowerCase();
    if (normalized.contains('failed')) return 'Fix failure and rerun';
    if (normalized.contains('test') || normalized.contains('build')) {
      return 'Attach result to handoff';
    }
    return 'Record result';
  }

  String _riskImpact(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('failed') || normalized.contains('conflict')) {
      return 'Blocks clean completion';
    }
    if (normalized.contains('missing') || normalized.contains('unknown')) {
      return 'Requires more context';
    }
    return 'May affect handoff confidence';
  }

  String _compact(String value, int limit) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= limit) return cleaned;
    return '${cleaned.substring(0, limit - 3).trim()}...';
  }
}
