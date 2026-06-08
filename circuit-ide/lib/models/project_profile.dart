import '../services/project_detector.dart';
import 'agent_run.dart';

enum ProjectReadiness { noWorkspace, loading, ready, degraded, error }

enum ProjectRecommendationKind {
  runChecks,
  explainProject,
  summarizeChanges,
  startWork,
}

class ProjectCommand {
  final String id;
  final String name;
  final String command;
  final String source;
  final bool enabled;
  final int timeoutSeconds;

  const ProjectCommand({
    required this.id,
    required this.name,
    required this.command,
    required this.source,
    this.enabled = true,
    this.timeoutSeconds = 120,
  });
}

class ProjectRecommendation {
  final String id;
  final String title;
  final String description;
  final ProjectRecommendationKind kind;
  final int priority;

  const ProjectRecommendation({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    this.priority = 0,
  });
}

class ProjectProfile {
  final String? rootPath;
  final ProjectReadiness readiness;
  final ProjectType primaryType;
  final Set<ProjectType> projectTypes;
  final Map<String, bool> detectedFeatures;
  final List<ProjectCommand> commands;
  final List<ProjectRecommendation> recommendations;
  final List<String> entrypoints;
  final String? gitBranch;
  final int changedFiles;
  final String lsdfStatus;
  final List<AgentRun> recentRuns;
  final DateTime? refreshedAt;
  final String? error;

  const ProjectProfile({
    this.rootPath,
    this.readiness = ProjectReadiness.noWorkspace,
    this.primaryType = ProjectType.unknown,
    this.projectTypes = const {},
    this.detectedFeatures = const {},
    this.commands = const [],
    this.recommendations = const [],
    this.entrypoints = const [],
    this.gitBranch,
    this.changedFiles = 0,
    this.lsdfStatus = 'idle',
    this.recentRuns = const [],
    this.refreshedAt,
    this.error,
  });

  bool get hasWorkspace => rootPath != null;

  ProjectProfile copyWith({
    String? rootPath,
    ProjectReadiness? readiness,
    ProjectType? primaryType,
    Set<ProjectType>? projectTypes,
    Map<String, bool>? detectedFeatures,
    List<ProjectCommand>? commands,
    List<ProjectRecommendation>? recommendations,
    List<String>? entrypoints,
    Object? gitBranch = _sentinel,
    int? changedFiles,
    String? lsdfStatus,
    List<AgentRun>? recentRuns,
    Object? refreshedAt = _sentinel,
    Object? error = _sentinel,
  }) {
    return ProjectProfile(
      rootPath: rootPath ?? this.rootPath,
      readiness: readiness ?? this.readiness,
      primaryType: primaryType ?? this.primaryType,
      projectTypes: projectTypes ?? this.projectTypes,
      detectedFeatures: detectedFeatures ?? this.detectedFeatures,
      commands: commands ?? this.commands,
      recommendations: recommendations ?? this.recommendations,
      entrypoints: entrypoints ?? this.entrypoints,
      gitBranch: identical(gitBranch, _sentinel)
          ? this.gitBranch
          : gitBranch as String?,
      changedFiles: changedFiles ?? this.changedFiles,
      lsdfStatus: lsdfStatus ?? this.lsdfStatus,
      recentRuns: recentRuns ?? this.recentRuns,
      refreshedAt: identical(refreshedAt, _sentinel)
          ? this.refreshedAt
          : refreshedAt as DateTime?,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

class VerificationResultSummary {
  final String command;
  final bool passed;
  final int exitCode;
  final Duration duration;
  final String output;

  const VerificationResultSummary({
    required this.command,
    required this.passed,
    required this.exitCode,
    required this.duration,
    required this.output,
  });

  String get statusLabel => passed ? 'passed' : 'failed';
}

const _sentinel = Object();
