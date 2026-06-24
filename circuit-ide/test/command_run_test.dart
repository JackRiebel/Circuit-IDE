import 'package:circuit_ide/agent/tools/command_tools.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/models/command_run.dart';
import 'package:circuit_ide/state/agent_turn_runtime_provider.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/command_run_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CommandTools streams stdout and stderr before exit', () async {
    final events = <CommandRunEvent>[];
    final output = await CommandTools(workingDir: '.').runCommand({
      'command': 'printf out; printf err >&2',
      'timeout': 5,
    }, onEvent: events.add);

    expect(output, contains('out'));
    expect(output, contains('[stderr] err'));
    expect(
      events.map((event) => event.type),
      contains(CommandRunEventType.stdout),
    );
    expect(
      events.map((event) => event.type),
      contains(CommandRunEventType.stderr),
    );
    expect(
      events.map((event) => event.type),
      contains(CommandRunEventType.exited),
    );
  });

  test('CommandTools blocks dangerous commands', () async {
    final events = <CommandRunEvent>[];
    final output = await CommandTools(
      workingDir: '.',
    ).runCommand({'command': 'rm -rf /'}, onEvent: events.add);

    expect(output, contains('Potentially dangerous command blocked'));
    expect(events.single.type, CommandRunEventType.blocked);
  });

  test('CommandTools blocks secret and environment file access', () async {
    for (final command in [
      'cat .env',
      'printenv',
      'python -c "print(open(\'.env\').read())"',
      'node -e "require(\'fs\').readFileSync(\'.npmrc\', \'utf8\')"',
      'tar czf secrets.tgz .aws/credentials',
      'cp ~/.netrc /tmp/netrc-copy',
    ]) {
      final events = <CommandRunEvent>[];
      final output = await CommandTools(
        workingDir: '.',
      ).runCommand({'command': command}, onEvent: events.add);

      expect(
        output,
        contains('Potentially dangerous command blocked'),
        reason: command,
      );
      expect(events.single.type, CommandRunEventType.blocked, reason: command);
    }
  });

  test(
    'CommandTools blocks reverse-order recursive force delete flags',
    () async {
      final events = <CommandRunEvent>[];
      final output = await CommandTools(
        workingDir: '.',
      ).runCommand({'command': 'rm -fr build'}, onEvent: events.add);

      expect(output, contains('Potentially dangerous command blocked'));
      expect(events.single.type, CommandRunEventType.blocked);
    },
  );

  test('CommandTools blocks split recursive force delete flags', () async {
    final firstOrderEvents = <CommandRunEvent>[];
    final firstOrderOutput = await CommandTools(
      workingDir: '.',
    ).runCommand({'command': 'rm -r -f build'}, onEvent: firstOrderEvents.add);
    final secondOrderEvents = <CommandRunEvent>[];
    final secondOrderOutput = await CommandTools(
      workingDir: '.',
    ).runCommand({'command': 'rm -f -r build'}, onEvent: secondOrderEvents.add);

    expect(firstOrderOutput, contains('Potentially dangerous command blocked'));
    expect(firstOrderEvents.single.type, CommandRunEventType.blocked);
    expect(
      secondOrderOutput,
      contains('Potentially dangerous command blocked'),
    );
    expect(secondOrderEvents.single.type, CommandRunEventType.blocked);
  });

  test(
    'CommandTools blocks uppercase and long recursive force flags',
    () async {
      final uppercaseEvents = <CommandRunEvent>[];
      final uppercaseOutput = await CommandTools(
        workingDir: '.',
      ).runCommand({'command': 'rm -R -f build'}, onEvent: uppercaseEvents.add);
      final longEvents = <CommandRunEvent>[];
      final longOutput = await CommandTools(workingDir: '.').runCommand({
        'command': 'rm --recursive --force build',
      }, onEvent: longEvents.add);
      final longReverseEvents = <CommandRunEvent>[];
      final longReverseOutput = await CommandTools(workingDir: '.').runCommand({
        'command': 'rm --force --recursive build',
      }, onEvent: longReverseEvents.add);

      expect(
        uppercaseOutput,
        contains('Potentially dangerous command blocked'),
      );
      expect(uppercaseEvents.single.type, CommandRunEventType.blocked);
      expect(longOutput, contains('Potentially dangerous command blocked'));
      expect(longEvents.single.type, CommandRunEventType.blocked);
      expect(
        longReverseOutput,
        contains('Potentially dangerous command blocked'),
      );
      expect(longReverseEvents.single.type, CommandRunEventType.blocked);
    },
  );

  test('CommandTools emits timeout events', () async {
    final events = <CommandRunEvent>[];
    final output = await CommandTools(
      workingDir: '.',
    ).runCommand({'command': 'sleep 6', 'timeout': 1}, onEvent: events.add);

    expect(output, contains('Command timed out'));
    expect(
      events.map((event) => event.type),
      contains(CommandRunEventType.timedOut),
    );
  });

  test('CommandRunController tracks streamed chunks', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(commandRunProvider.notifier);

    controller.start(id: 'cmd-1', command: 'echo hello');
    controller.append('cmd-1', CommandRunEventType.stdout, 'hello\n');
    controller.finish('cmd-1', status: CommandRunStatus.succeeded, exitCode: 0);

    final run = container.read(commandRunProvider)['cmd-1']!;
    expect(run.status, CommandRunStatus.succeeded);
    expect(run.stdout, 'hello\n');
    expect(run.combinedOutput, 'hello');
    expect(run.exitCode, 0);
  });

  test('CommandRunController attaches to active Studio task session', () {
    final container = ProviderContainer(
      overrides: [
        agentTurnRuntimeProvider.overrideWith(_MutableAgentTurnRuntime.new),
      ],
    );
    addTearDown(container.dispose);
    final task = container
        .read(agentWorkspaceProvider.notifier)
        .startTask(goal: 'Verify patch', profile: AgentTaskProfile.verify);
    (container.read(agentTurnRuntimeProvider.notifier)
            as _MutableAgentTurnRuntime)
        .activate(taskId: task.id);
    container
        .read(commandRunProvider.notifier)
        .start(id: 'cmd-studio', command: 'flutter test');

    final updatedTask = container.read(agentWorkspaceProvider).tasks.single;
    expect(updatedTask.commandRunIds, ['cmd-studio']);
    expect(
      updatedTask.artifacts
          .where(
            (artifact) => artifact.type == AgentTaskArtifactType.commandRun,
          )
          .single
          .detail,
      'flutter test',
    );
  });

  test(
    'CommandRunController does not attach thread-only Studio commands to legacy selected task',
    () {
      final container = ProviderContainer(
        overrides: [
          agentTurnRuntimeProvider.overrideWith(_MutableAgentTurnRuntime.new),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(agentWorkspaceProvider.notifier)
          .startTask(
            goal: 'Legacy selected task',
            profile: AgentTaskProfile.verify,
          );
      (container.read(agentTurnRuntimeProvider.notifier)
              as _MutableAgentTurnRuntime)
          .activate();
      container
          .read(commandRunProvider.notifier)
          .start(id: 'cmd-thread-only', command: 'flutter test');

      final task = container.read(agentWorkspaceProvider).tasks.single;
      expect(task.commandRunIds, isEmpty);
      expect(
        task.artifacts.where(
          (artifact) => artifact.type == AgentTaskArtifactType.commandRun,
        ),
        isEmpty,
      );
    },
  );
}

class _MutableAgentTurnRuntime extends AgentTurnRuntime {
  @override
  AgentTurnRuntimeState build() => const AgentTurnRuntimeState();

  void activate({String? taskId}) {
    state = AgentTurnRuntimeState(
      activeSessions: {
        'request-1': AgentTurnSession(
          requestId: 'request-1',
          threadId: 'thread-1',
          taskId: taskId,
          model: 'gpt-5-nano',
          intent: TurnIntent.verify,
          phase: AgentTurnPhase.toolExecution,
          startedAt: DateTime(2026),
        ),
      },
    );
  }
}
