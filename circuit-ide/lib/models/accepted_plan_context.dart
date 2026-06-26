import 'reviewed_edit.dart';

class AcceptedPlanContext {
  final String patchSetId;
  final String title;
  final String summary;
  final String markdown;
  final List<String> plannedFiles;
  final List<PlannedFileTarget> plannedTargets;
  final bool verificationRequested;

  const AcceptedPlanContext({
    required this.patchSetId,
    required this.title,
    required this.summary,
    required this.markdown,
    this.plannedFiles = const [],
    this.plannedTargets = const [],
    this.verificationRequested = false,
  });

  AcceptedPlanContext copyWith({
    String? patchSetId,
    String? title,
    String? summary,
    String? markdown,
    List<String>? plannedFiles,
    List<PlannedFileTarget>? plannedTargets,
    bool? verificationRequested,
  }) {
    return AcceptedPlanContext(
      patchSetId: patchSetId ?? this.patchSetId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      markdown: markdown ?? this.markdown,
      plannedFiles: plannedFiles ?? this.plannedFiles,
      plannedTargets: plannedTargets ?? this.plannedTargets,
      verificationRequested:
          verificationRequested ?? this.verificationRequested,
    );
  }

  factory AcceptedPlanContext.fromPatch(ProposedPatchSet patch) {
    final targets = patch.effectivePlannedTargets
        .where((target) => target.path.trim().isNotEmpty)
        .toList(growable: false);
    return AcceptedPlanContext(
      patchSetId: patch.id,
      title: patch.title,
      summary: patch.comparisonSummary ?? patch.title,
      markdown: patch.planMarkdown ?? '',
      plannedFiles: patch.plannedFiles.isNotEmpty
          ? patch.plannedFiles
          : [for (final target in targets) target.displayString],
      plannedTargets: targets,
      verificationRequested: patch.verificationRequested,
    );
  }

  Map<String, dynamic> toJson() => {
    'patchSetId': patchSetId,
    'title': title,
    'summary': summary,
    'markdown': markdown,
    'plannedFiles': plannedFiles,
    'plannedTargets': plannedTargets.map((target) => target.toJson()).toList(),
    'verificationRequested': verificationRequested,
  };

  static AcceptedPlanContext? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      final plannedFiles =
          (json['plannedFiles'] as List<dynamic>?)?.cast<String>() ??
          const <String>[];
      final plannedTargets = (json['plannedTargets'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map(PlannedFileTarget.fromJson)
          .whereType<PlannedFileTarget>()
          .where((target) => target.path.trim().isNotEmpty)
          .toList(growable: false);
      return AcceptedPlanContext(
        patchSetId: json['patchSetId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        markdown: json['markdown'] as String? ?? '',
        plannedFiles: plannedFiles,
        plannedTargets:
            plannedTargets ??
            [
              for (final file in plannedFiles)
                PlannedFileTarget.fromDisplayString(file),
            ],
        verificationRequested: json['verificationRequested'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  String toPromptBlock() {
    final promptTargets = _promptTargets();
    return [
      '<accepted_plan_context>',
      'patchSetId: $patchSetId',
      'title: $title',
      if (summary.trim().isNotEmpty) 'summary: $summary',
      if (promptTargets.isNotEmpty) ...[
        'plannedFiles:',
        for (final target in promptTargets) '- ${target.contractString}',
      ],
      if (verificationRequested) 'verificationRequested: true',
      if (markdown.trim().isNotEmpty) ...['planMarkdown:', markdown.trim()],
      '</accepted_plan_context>',
    ].join('\n');
  }

  List<PlannedFileTarget> _promptTargets() {
    if (plannedTargets.isNotEmpty) return plannedTargets;
    return [
      for (final file in plannedFiles)
        PlannedFileTarget.fromDisplayString(file),
    ];
  }
}
