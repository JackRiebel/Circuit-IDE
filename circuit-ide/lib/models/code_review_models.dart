import 'package:uuid/uuid.dart';

enum ReviewSeverity { critical, warning, suggestion, nit }

enum ReviewVerdict { pass, passWithWarnings, needsChanges }

class ReviewAnnotation {
  final String id;
  final String filePath;
  final int startLine;
  final int endLine;
  final ReviewSeverity severity;
  final String message;
  final String? suggestedFix;
  final bool isFixed;

  const ReviewAnnotation({
    required this.id,
    required this.filePath,
    required this.startLine,
    required this.endLine,
    required this.severity,
    required this.message,
    this.suggestedFix,
    this.isFixed = false,
  });

  ReviewAnnotation copyWith({bool? isFixed}) {
    return ReviewAnnotation(
      id: id,
      filePath: filePath,
      startLine: startLine,
      endLine: endLine,
      severity: severity,
      message: message,
      suggestedFix: suggestedFix,
      isFixed: isFixed ?? this.isFixed,
    );
  }

  factory ReviewAnnotation.fromJson(
      Map<String, dynamic> json, String filePath) {
    return ReviewAnnotation(
      id: const Uuid().v4(),
      filePath: filePath,
      startLine: json['startLine'] ?? 1,
      endLine: json['endLine'] ?? json['startLine'] ?? 1,
      severity: ReviewSeverity.values.firstWhere(
        (s) => s.name == (json['severity'] ?? 'suggestion'),
        orElse: () => ReviewSeverity.suggestion,
      ),
      message: json['message'] ?? '',
      suggestedFix: json['suggestedFix'],
    );
  }
}

class FileReviewResult {
  final String filePath;
  final String diffContent;
  final List<ReviewAnnotation> annotations;

  const FileReviewResult({
    required this.filePath,
    required this.diffContent,
    this.annotations = const [],
  });

  int get criticalCount =>
      annotations.where((a) => a.severity == ReviewSeverity.critical).length;
  int get warningCount =>
      annotations.where((a) => a.severity == ReviewSeverity.warning).length;
  int get suggestionCount =>
      annotations.where((a) => a.severity == ReviewSeverity.suggestion).length;
  int get nitCount =>
      annotations.where((a) => a.severity == ReviewSeverity.nit).length;
}

class CodeReview {
  final String id;
  final DateTime timestamp;
  final String? branch;
  final List<FileReviewResult> fileResults;
  final String? overallAssessment;
  final ReviewVerdict verdict;
  final bool isReviewing;

  CodeReview({
    String? id,
    DateTime? timestamp,
    this.branch,
    this.fileResults = const [],
    this.overallAssessment,
    this.verdict = ReviewVerdict.pass,
    this.isReviewing = false,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  CodeReview copyWith({
    List<FileReviewResult>? fileResults,
    String? overallAssessment,
    ReviewVerdict? verdict,
    bool? isReviewing,
  }) {
    return CodeReview(
      id: id,
      timestamp: timestamp,
      branch: branch,
      fileResults: fileResults ?? this.fileResults,
      overallAssessment: overallAssessment ?? this.overallAssessment,
      verdict: verdict ?? this.verdict,
      isReviewing: isReviewing ?? this.isReviewing,
    );
  }

  int get totalAnnotations =>
      fileResults.fold(0, (sum, f) => sum + f.annotations.length);
  int get totalCritical =>
      fileResults.fold(0, (sum, f) => sum + f.criticalCount);
  int get totalWarnings =>
      fileResults.fold(0, (sum, f) => sum + f.warningCount);
}
