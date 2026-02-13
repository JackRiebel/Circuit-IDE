import 'dart:convert';

import '../models/code_review_models.dart';

class FileDiff {
  final String filePath;
  final String diffContent;
  final List<DiffHunk> hunks;

  const FileDiff({
    required this.filePath,
    required this.diffContent,
    this.hunks = const [],
  });
}

class DiffHunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String content;

  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.content,
  });
}

class CodeReviewService {
  static final _hunkHeaderRegex =
      RegExp(r'@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@');

  /// Parse raw `git diff` output into a list of per-file diffs.
  static List<FileDiff> parseDiff(String rawDiff) {
    if (rawDiff.trim().isEmpty) return [];

    final fileDiffs = <FileDiff>[];
    // Split on "diff --git" boundaries (skip the empty first element)
    final sections = rawDiff.split('diff --git ');

    for (final section in sections) {
      if (section.trim().isEmpty) continue;

      // Extract file path from "a/path b/path" header
      final firstLine = section.split('\n').first;
      final pathMatch = RegExp(r'b/(.+)$').firstMatch(firstLine);
      if (pathMatch == null) continue;
      final filePath = pathMatch.group(1)!;

      // Parse hunks
      final hunks = <DiffHunk>[];
      final hunkMatches = _hunkHeaderRegex.allMatches(section);
      final hunkStarts = hunkMatches.toList();

      for (int i = 0; i < hunkStarts.length; i++) {
        final match = hunkStarts[i];
        final oldStart = int.parse(match.group(1)!);
        final oldCount =
            match.group(2)!.isEmpty ? 1 : int.parse(match.group(2)!);
        final newStart = int.parse(match.group(3)!);
        final newCount =
            match.group(4)!.isEmpty ? 1 : int.parse(match.group(4)!);

        // Extract hunk content (from this header to next header or end)
        final start = match.end;
        final end = (i + 1 < hunkStarts.length)
            ? hunkStarts[i + 1].start
            : section.length;
        final content = section.substring(start, end).trimRight();

        hunks.add(DiffHunk(
          oldStart: oldStart,
          oldCount: oldCount,
          newStart: newStart,
          newCount: newCount,
          content: content,
        ));
      }

      fileDiffs.add(FileDiff(
        filePath: filePath,
        diffContent: 'diff --git $section',
        hunks: hunks,
      ));
    }

    return fileDiffs;
  }

  /// Build a prompt that asks the AI to review a single file diff.
  static String buildReviewPrompt(FileDiff fileDiff) {
    return '''Review the following git diff for the file "${fileDiff.filePath}".

Analyze the changes for:
- Bugs or logic errors
- Security vulnerabilities
- Performance issues
- Code style / best practices
- Missing error handling

Return a JSON array of annotations. Each annotation should have:
- "startLine": int (line number in the new file)
- "endLine": int (line number in the new file)
- "severity": one of "critical", "warning", "suggestion", "nit"
- "message": string explaining the issue
- "suggestedFix": string with the corrected code (optional, omit if not applicable)

If the code looks good, return an empty array: []

Respond with ONLY the JSON array, no additional text.

Diff:
${fileDiff.diffContent}''';
  }

  /// Parse the AI response into a list of ReviewAnnotation objects.
  static List<ReviewAnnotation> parseReviewResponse(
      String aiResponse, String filePath) {
    try {
      // Try direct JSON parse
      final decoded = jsonDecode(aiResponse.trim());
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((json) => ReviewAnnotation.fromJson(json, filePath))
            .toList();
      }
    } catch (_) {
      // Fallback: extract JSON array via regex
      try {
        final match = RegExp(r'\[[\s\S]*\]').firstMatch(aiResponse);
        if (match != null) {
          final decoded = jsonDecode(match.group(0)!);
          if (decoded is List) {
            return decoded
                .whereType<Map<String, dynamic>>()
                .map((json) => ReviewAnnotation.fromJson(json, filePath))
                .toList();
          }
        }
      } catch (_) {
        // Could not parse — return empty
      }
    }
    return [];
  }

  /// Build a prompt for overall assessment given all file results.
  static String buildOverallPrompt(List<FileReviewResult> results) {
    final summary = StringBuffer();
    summary.writeln('Here is a summary of code review findings:\n');

    for (final result in results) {
      summary.writeln('File: ${result.filePath}');
      summary.writeln(
          '  Critical: ${result.criticalCount}, Warnings: ${result.warningCount}, '
          'Suggestions: ${result.suggestionCount}, Nits: ${result.nitCount}');
      for (final annotation in result.annotations) {
        summary.writeln(
            '  - [${annotation.severity.name}] L${annotation.startLine}: ${annotation.message}');
      }
      summary.writeln();
    }

    return '''$summary
Based on the above findings, provide:
1. A brief overall assessment (2-3 sentences)
2. A verdict: "pass", "passWithWarnings", or "needsChanges"

Respond with ONLY a JSON object:
{"assessment": "...", "verdict": "pass|passWithWarnings|needsChanges"}''';
  }

  /// Parse the overall assessment response from the AI.
  static (String assessment, ReviewVerdict verdict) parseOverallResponse(
      String aiResponse) {
    try {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(aiResponse);
      if (match != null) {
        final decoded =
            jsonDecode(match.group(0)!) as Map<String, dynamic>;
        final assessment =
            decoded['assessment'] as String? ?? 'Review complete.';
        final verdictStr = decoded['verdict'] as String? ?? 'pass';
        final verdict = ReviewVerdict.values.firstWhere(
          (v) => v.name == verdictStr,
          orElse: () => ReviewVerdict.pass,
        );
        return (assessment, verdict);
      }
    } catch (_) {
      // Fallback
    }
    return ('Review complete.', ReviewVerdict.pass);
  }
}
