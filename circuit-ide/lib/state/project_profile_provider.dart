import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/project_profile.dart';
import '../services/project_detector.dart';
import 'agent_run_provider.dart';
import 'file_tree_provider.dart';
import 'git_provider.dart';
import 'workspace_context_provider.dart';

class ProjectProfileController extends Notifier<ProjectProfile> {
  int _generation = 0;

  @override
  ProjectProfile build() {
    ref.listen(fileTreeProvider, (previous, next) {
      final previousRoot = previous?.rootPath;
      if (next.rootPath != null && next.rootPath != previousRoot) {
        refresh();
      }
      if (next.rootPath == null && previousRoot != null) {
        state = const ProjectProfile();
      }
    });
    ref.listen(workspaceContextProvider, (previous, next) {
      if (state.hasWorkspace) {
        state = state.copyWith(lsdfStatus: next.status.name);
      }
    });
    ref.listen(gitProvider, (previous, next) {
      if (state.hasWorkspace) {
        state = state.copyWith(
          gitBranch: next.status.branch.isEmpty ? null : next.status.branch,
          changedFiles: next.status.totalChanges,
        );
      }
    });
    ref.listen(agentRunProvider, (previous, next) {
      if (state.hasWorkspace) {
        state = state.copyWith(recentRuns: next.recentRuns.take(5).toList());
      }
    });
    return const ProjectProfile();
  }

  Future<void> refresh() async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) {
      state = const ProjectProfile();
      return;
    }

    final generation = ++_generation;
    state = state.copyWith(
      rootPath: rootPath,
      readiness: ProjectReadiness.loading,
      error: null,
    );

    try {
      final detection = await ProjectDetector(rootPath: rootPath).detect();
      if (generation != _generation) return;
      final scripts = await _packageScripts(rootPath);
      final entrypoints = await _entrypoints(rootPath, detection.primaryType);
      final commands = _commandsFromDetection(detection, scripts);

      await ref.read(gitProvider.notifier).refresh();
      final git = ref.read(gitProvider);
      final workspace = ref.read(workspaceContextProvider);
      final runs = ref.read(agentRunProvider);

      final readiness = workspace.error != null
          ? ProjectReadiness.degraded
          : ProjectReadiness.ready;

      state = ProjectProfile(
        rootPath: rootPath,
        readiness: readiness,
        primaryType: detection.primaryType,
        projectTypes: detection.allTypes,
        detectedFeatures: detection.detectedFeatures,
        commands: commands,
        recommendations: _recommendations(commands, git.status.totalChanges),
        entrypoints: entrypoints,
        gitBranch: git.status.branch.isEmpty ? null : git.status.branch,
        changedFiles: git.status.totalChanges,
        lsdfStatus: workspace.status.name,
        recentRuns: runs.recentRuns.take(5).toList(),
        refreshedAt: DateTime.now(),
        error: workspace.error,
      );
    } catch (e) {
      if (generation != _generation) return;
      state = state.copyWith(
        readiness: ProjectReadiness.error,
        error: e.toString(),
        refreshedAt: DateTime.now(),
      );
    }
  }

  List<ProjectCommand> recommendedChecks() {
    return state.commands.where((command) => command.enabled).take(4).toList();
  }

  Future<VerificationResultSummary> runCommand(ProjectCommand command) async {
    final rootPath = state.rootPath;
    if (rootPath == null) {
      return VerificationResultSummary(
        command: command.command,
        passed: false,
        exitCode: -1,
        duration: Duration.zero,
        output: 'No workspace is open.',
      );
    }

    final started = DateTime.now();
    try {
      final result = await Process.run(
        '/bin/zsh',
        ['-lc', command.command],
        workingDirectory: rootPath,
      ).timeout(Duration(seconds: command.timeoutSeconds));
      final output = [
        (result.stdout as String).trim(),
        (result.stderr as String).trim(),
      ].where((part) => part.isNotEmpty).join('\n');
      return VerificationResultSummary(
        command: command.command,
        passed: result.exitCode == 0,
        exitCode: result.exitCode,
        duration: DateTime.now().difference(started),
        output: output,
      );
    } catch (e) {
      return VerificationResultSummary(
        command: command.command,
        passed: false,
        exitCode: -1,
        duration: DateTime.now().difference(started),
        output: e.toString(),
      );
    }
  }

  List<ProjectCommand> _commandsFromDetection(
    ProjectDetectionResult detection,
    Map<String, String> scripts,
  ) {
    final commands = <ProjectCommand>[
      for (final check in detection.suggestedChecks)
        ProjectCommand(
          id: check.id,
          name: check.name,
          command: check.command,
          source: 'Detected check',
          enabled: check.enabled,
          timeoutSeconds: check.timeoutSeconds,
        ),
    ];

    for (final entry in scripts.entries) {
      final scriptName = entry.key;
      if (commands.any((command) => command.command == 'npm run $scriptName')) {
        continue;
      }
      final important = _importantScript(scriptName);
      commands.add(
        ProjectCommand(
          id: 'npm:$scriptName',
          name: 'npm run $scriptName',
          command: scriptName == 'test' ? 'npm test' : 'npm run $scriptName',
          source: 'package.json',
          enabled: important,
          timeoutSeconds: important ? 120 : 60,
        ),
      );
    }

    return commands.take(12).toList();
  }

  List<ProjectRecommendation> _recommendations(
    List<ProjectCommand> commands,
    int changedFiles,
  ) {
    final recommendations = <ProjectRecommendation>[
      const ProjectRecommendation(
        id: 'explain-project',
        title: 'Explain this project',
        description:
            'Summarize architecture, entrypoints, and safe next steps.',
        kind: ProjectRecommendationKind.explainProject,
        priority: 90,
      ),
      const ProjectRecommendation(
        id: 'start-work',
        title: 'Start a guided work item',
        description: 'Turn a goal into steps, runs, verification, and handoff.',
        kind: ProjectRecommendationKind.startWork,
        priority: 80,
      ),
    ];

    if (commands.any((command) => command.enabled)) {
      recommendations.add(
        const ProjectRecommendation(
          id: 'run-checks',
          title: 'Run recommended checks',
          description: 'Use detected test, lint, or build commands.',
          kind: ProjectRecommendationKind.runChecks,
          priority: 70,
        ),
      );
    }
    if (changedFiles > 0) {
      recommendations.add(
        const ProjectRecommendation(
          id: 'summarize-changes',
          title: 'Summarize current changes',
          description: 'Create a clean handoff from the working tree.',
          kind: ProjectRecommendationKind.summarizeChanges,
          priority: 75,
        ),
      );
    }

    recommendations.sort((a, b) => b.priority.compareTo(a.priority));
    return recommendations;
  }

  Future<Map<String, String>> _packageScripts(String rootPath) async {
    final packageJson = File(p.join(rootPath, 'package.json'));
    if (!await packageJson.exists()) return {};
    try {
      final json =
          jsonDecode(await packageJson.readAsString()) as Map<String, dynamic>;
      final scripts = json['scripts'] as Map<String, dynamic>? ?? {};
      return scripts.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<List<String>> _entrypoints(String rootPath, ProjectType type) async {
    final candidates = switch (type) {
      ProjectType.flutter ||
      ProjectType.dart => ['lib/main.dart', 'bin/main.dart'],
      ProjectType.node || ProjectType.typescript => [
        'src/index.ts',
        'src/index.js',
        'index.ts',
        'index.js',
        'server.js',
      ],
      ProjectType.python => ['main.py', 'app.py', 'src/main.py'],
      ProjectType.rust => ['src/main.rs', 'src/lib.rs'],
      ProjectType.go => ['main.go', 'cmd/main.go'],
      ProjectType.swift => ['Sources/main.swift', 'Package.swift'],
      _ => ['README.md'],
    };
    final found = <String>[];
    for (final candidate in candidates) {
      if (await File(p.join(rootPath, candidate)).exists()) {
        found.add(candidate);
      }
    }
    return found.take(5).toList();
  }

  bool _importantScript(String name) {
    final lower = name.toLowerCase();
    return lower == 'test' ||
        lower.contains('lint') ||
        lower.contains('type') ||
        lower.contains('check') ||
        lower.contains('build');
  }
}

final projectProfileProvider =
    NotifierProvider<ProjectProfileController, ProjectProfile>(
      ProjectProfileController.new,
    );
