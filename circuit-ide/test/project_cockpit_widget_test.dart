import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/project_profile.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/project_profile_provider.dart';
import 'package:circuit_ide/ui/project/project_cockpit_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Project Cockpit renders a no-workspace state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ProjectCockpitPanel())),
      ),
    );

    expect(find.text('Project Cockpit'), findsOneWidget);
    expect(find.textContaining('Open a folder'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets('Project Cockpit pauses and resumes a background task', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        projectProfileProvider.overrideWith(_WorkspaceProfileController.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(children: const [ProjectCockpitPanel()]),
          ),
        ),
      ),
    );
    final task = container
        .read(agentWorkspaceProvider.notifier)
        .startTask(
          goal: 'Inspect the background task controls',
          backgroundExecutionRequested: true,
        );
    await tester.pump();

    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(
      container.read(agentWorkspaceProvider).tasks.single.status,
      AgentTaskStatus.paused,
    );
    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(
      container.read(agentWorkspaceProvider).tasks.single.status,
      AgentTaskStatus.running,
    );
    expect(container.read(agentWorkspaceProvider).tasks.single.id, task.id);
  });
}

class _WorkspaceProfileController extends ProjectProfileController {
  @override
  ProjectProfile build() => const ProjectProfile(
    rootPath: '/workspace',
    readiness: ProjectReadiness.ready,
  );
}
