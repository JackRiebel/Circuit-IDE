import 'package:circuit_ide/models/workspace_session.dart';
import 'package:circuit_ide/state/workspace_session_provider.dart';
import 'package:circuit_ide/ui/studio/studio_workspace_access_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps a failed workspace scope visible with a recovery action', (
    tester,
  ) async {
    var pickerCalls = 0;
    final container = ProviderContainer(
      overrides: [
        workspaceSessionProvider.overrideWith(
          _TestWorkspaceSessionController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: StudioWorkspaceAccessFailure(
              chooseProject: (_) async {
                pickerCalls += 1;
                return false;
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final controller =
        container.read(workspaceSessionProvider.notifier)
            as _TestWorkspaceSessionController;
    controller.fail('Workspace access expired. Reopen the project folder.');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Workspace access needs attention.'),
      findsOneWidget,
    );
    expect(find.text('Choose folder'), findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('workspace-access-failure-live-region')),
          )
          .label,
      contains('Workspace access needs attention.'),
    );

    await tester.tap(find.text('Choose folder'));
    await tester.pump();
    expect(pickerCalls, 1);
  });

  testWidgets('removes the warning after workspace access recovers', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        workspaceSessionProvider.overrideWith(
          _TestWorkspaceSessionController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: StudioWorkspaceAccessFailure(child: SizedBox.expand()),
          ),
        ),
      ),
    );

    final controller =
        container.read(workspaceSessionProvider.notifier)
            as _TestWorkspaceSessionController;
    controller.fail('Workspace access expired.');
    await tester.pumpAndSettle();
    expect(find.text('Choose folder'), findsOneWidget);

    controller.recover();
    await tester.pumpAndSettle();
    expect(find.text('Choose folder'), findsNothing);
  });
}

class _TestWorkspaceSessionController extends WorkspaceSessionController {
  @override
  WorkspaceSessionState build() => const WorkspaceSessionState();

  void fail(String error) {
    state = WorkspaceSessionState(
      status: WorkspaceSessionStatus.failed,
      error: error,
    );
  }

  void recover() {
    state = const WorkspaceSessionState(status: WorkspaceSessionStatus.ready);
  }
}
