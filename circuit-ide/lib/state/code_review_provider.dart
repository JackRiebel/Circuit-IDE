import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/platform_utils.dart';
import '../models/code_review_models.dart';
import '../services/code_review_service.dart';
import '../state/connection_provider.dart';
import '../state/file_tree_provider.dart';
import '../state/git_provider.dart';

class CodeReviewState {
  final CodeReview? currentReview;
  final List<CodeReview> history;
  final bool isReviewing;

  const CodeReviewState({
    this.currentReview,
    this.history = const [],
    this.isReviewing = false,
  });

  CodeReviewState copyWith({
    CodeReview? currentReview,
    bool clearCurrentReview = false,
    List<CodeReview>? history,
    bool? isReviewing,
  }) {
    return CodeReviewState(
      currentReview: clearCurrentReview
          ? null
          : (currentReview ?? this.currentReview),
      history: history ?? this.history,
      isReviewing: isReviewing ?? this.isReviewing,
    );
  }
}

class CodeReviewNotifier extends Notifier<CodeReviewState> {
  @override
  CodeReviewState build() => const CodeReviewState();

  /// Start an AI code review on the current diff.
  /// If [staged] is true, reviews staged changes; otherwise reviews all
  /// unstaged changes.
  Future<void> startReview({bool staged = true}) async {
    final agentService = ref.read(agentServiceProvider);
    if (!agentService.isConnected) return;

    final workingDir =
        ref.read(fileTreeProvider).rootPath ?? PlatformUtils.scratchDir;
    final git = ref.read(gitProvider);

    state = state.copyWith(isReviewing: true);

    try {
      // Get the diff
      final diffArg = staged && git.status.staged.isNotEmpty ? '--cached' : '';
      final result = await Process.run('git', [
        'diff',
        if (diffArg.isNotEmpty) diffArg,
      ], workingDirectory: workingDir);

      final rawDiff = (result.stdout as String).trim();
      if (rawDiff.isEmpty) {
        state = state.copyWith(isReviewing: false);
        return;
      }

      // Parse into per-file diffs
      final fileDiffs = CodeReviewService.parseDiff(rawDiff);
      if (fileDiffs.isEmpty) {
        state = state.copyWith(isReviewing: false);
        return;
      }

      // Create the in-progress review
      final review = CodeReview(branch: git.status.branch, isReviewing: true);
      state = state.copyWith(currentReview: review, isReviewing: true);

      // Review each file
      final fileResults = <FileReviewResult>[];
      for (final fileDiff in fileDiffs) {
        final prompt = CodeReviewService.buildReviewPrompt(fileDiff);

        // Truncate very large diffs to stay within token limits
        final truncatedPrompt = prompt.length > 8000
            ? prompt.substring(0, 8000)
            : prompt;

        final aiResponse = await agentService.sendOneShot(
          truncatedPrompt,
          systemPrompt:
              'You are a senior code reviewer. Be concise and precise. '
              'Return only valid JSON.',
        );

        final annotations = aiResponse != null
            ? CodeReviewService.parseReviewResponse(
                aiResponse,
                fileDiff.filePath,
              )
            : <ReviewAnnotation>[];

        fileResults.add(
          FileReviewResult(
            filePath: fileDiff.filePath,
            diffContent: fileDiff.diffContent,
            annotations: annotations,
          ),
        );
      }

      // Get overall assessment
      String? overallAssessment;
      ReviewVerdict verdict = ReviewVerdict.pass;

      if (fileResults.any((f) => f.annotations.isNotEmpty)) {
        final overallPrompt = CodeReviewService.buildOverallPrompt(fileResults);
        final overallResponse = await agentService.sendOneShot(
          overallPrompt,
          systemPrompt:
              'You are a senior code reviewer. Be concise. Return only valid JSON.',
        );

        if (overallResponse != null) {
          final (assessment, v) = CodeReviewService.parseOverallResponse(
            overallResponse,
          );
          overallAssessment = assessment;
          verdict = v;
        }
      } else {
        overallAssessment = 'All changes look good. No issues found.';
        verdict = ReviewVerdict.pass;
      }

      // Finalize review
      final completedReview = review.copyWith(
        fileResults: fileResults,
        overallAssessment: overallAssessment,
        verdict: verdict,
        isReviewing: false,
      );

      state = state.copyWith(
        currentReview: completedReview,
        history: [completedReview, ...state.history],
        isReviewing: false,
      );
    } catch (e) {
      state = state.copyWith(isReviewing: false);
    }
  }

  /// Apply a suggested fix for a specific annotation.
  Future<void> applyFix(String annotationId) async {
    final review = state.currentReview;
    if (review == null) return;

    final workingDir =
        ref.read(fileTreeProvider).rootPath ?? PlatformUtils.scratchDir;

    for (final fileResult in review.fileResults) {
      for (final annotation in fileResult.annotations) {
        if (annotation.id != annotationId) continue;
        if (annotation.suggestedFix == null || annotation.isFixed) return;

        try {
          final filePath = '$workingDir/${annotation.filePath}';
          final file = File(filePath);
          if (!await file.exists()) return;

          final lines = await file.readAsLines();

          // Replace the line range with the suggested fix
          final start = (annotation.startLine - 1).clamp(0, lines.length);
          final end = annotation.endLine.clamp(start, lines.length);

          final fixLines = annotation.suggestedFix!.split('\n');
          lines.replaceRange(start, end, fixLines);

          await file.writeAsString('${lines.join('\n')}\n');

          // Mark annotation as fixed and update state
          final updatedFileResults = review.fileResults.map((fr) {
            if (fr.filePath != fileResult.filePath) return fr;
            return FileReviewResult(
              filePath: fr.filePath,
              diffContent: fr.diffContent,
              annotations: fr.annotations
                  .map(
                    (a) => a.id == annotationId ? a.copyWith(isFixed: true) : a,
                  )
                  .toList(),
            );
          }).toList();

          state = state.copyWith(
            currentReview: review.copyWith(fileResults: updatedFileResults),
          );

          // Refresh git status
          ref.read(gitProvider.notifier).refresh();
        } catch (_) {
          // Silently fail
        }
        return;
      }
    }
  }

  /// Dismiss the current review (go back to changes view).
  void dismissReview() {
    state = state.copyWith(clearCurrentReview: true, isReviewing: false);
  }

  /// Dismiss (remove) a single annotation from the current review.
  void dismissAnnotation(String annotationId) {
    final review = state.currentReview;
    if (review == null) return;

    final updatedFileResults = review.fileResults.map((fr) {
      return FileReviewResult(
        filePath: fr.filePath,
        diffContent: fr.diffContent,
        annotations: fr.annotations.where((a) => a.id != annotationId).toList(),
      );
    }).toList();

    state = state.copyWith(
      currentReview: review.copyWith(fileResults: updatedFileResults),
    );
  }

  /// View a past review by setting it as the current review.
  void viewHistoryItem(CodeReview review) {
    state = state.copyWith(currentReview: review);
  }
}

final codeReviewProvider =
    NotifierProvider<CodeReviewNotifier, CodeReviewState>(
      CodeReviewNotifier.new,
    );
