import 'dart:io';

import 'package:circuit_ide/agent/tools/command_tools.dart';
import 'package:circuit_ide/agent/tools/tool_executor.dart';
import 'package:circuit_ide/enums/event_type.dart';
import 'package:circuit_ide/enums/tool_status.dart';
import 'package:circuit_ide/models/agent_tool_permission.dart';
import 'package:circuit_ide/models/agent_workspace.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/models/command_run.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/models/studio_turn.dart';
import 'package:circuit_ide/models/tool_call_info.dart';
import 'package:circuit_ide/state/agent_turn_runtime_provider.dart';
import 'package:circuit_ide/state/agent_workspace_provider.dart';
import 'package:circuit_ide/state/command_run_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:circuit_ide/services/event_bus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CommandTools streams stdout and stderr before exit', () async {
    final events = <CommandRunEvent>[];
    final output = await CommandTools(workingDir: '.').runCommand({
      'command':
          'python3 -c "import sys; print(\'out\'); print(\'err\', file=sys.stderr)"',
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

  test('CommandTools blocks unquoted shell control syntax', () async {
    for (final command in [
      'printf out; printf err',
      'printf out && printf err',
      'printf out || printf err',
      'printf out | cat',
      'printf out > output.txt',
      'cat < input.txt',
      'sleep 1 &',
      'printf out\nprintf err',
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

  test('CommandTools allows shell symbols inside quoted arguments', () async {
    final output = await CommandTools(
      workingDir: '.',
    ).runCommand({'command': 'printf "%s" "a|b;c&&d>e"', 'timeout': 5});

    expect(output, 'a|b;c&&d>e');
  });

  test(
    'CommandTools blocks outside-workspace file access at execution boundary',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-command-root-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final outside = File('${root.parent.path}/outside-command-file.txt');
      await outside.writeAsString('outside');
      addTearDown(() async {
        if (await outside.exists()) await outside.delete();
      });

      for (final command in [
        'cat ${outside.path}',
        'python3 -c "from pathlib import Path; print(Path(\'../outside-command-file.txt\').read_text())"',
      ]) {
        final events = <CommandRunEvent>[];
        final output = await CommandTools(
          workingDir: root.path,
        ).runCommand({'command': command, 'timeout': 5}, onEvent: events.add);

        expect(output, contains('Workspace boundary blocked'), reason: command);
        expect(events.single.type, CommandRunEventType.blocked);
      }
    },
  );

  test('CommandTools blocks dangerous commands', () async {
    final events = <CommandRunEvent>[];
    final output = await CommandTools(
      workingDir: '.',
    ).runCommand({'command': 'rm -rf /'}, onEvent: events.add);

    expect(output, contains('Potentially dangerous command blocked'));
    expect(events.single.type, CommandRunEventType.blocked);
  });

  test('CommandTools blocks nested shell command execution', () async {
    for (final command in [
      "bash -lc 'cat /etc/passwd'",
      "sh -c 'cat .env.local'",
      'zsh -c "printenv"',
      'pwsh -Command "Get-ChildItem Env:"',
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
      expect(events.single.text, contains('Nested shell command execution'));
    }
  });

  test('CommandTools blocks secret and environment file access', () async {
    for (final command in [
      'cat .env',
      'printenv',
      'python -c "print(open(\'.env\').read())"',
      'node -e "require(\'fs\').readFileSync(\'.npmrc\', \'utf8\')"',
      'tar czf secrets.tgz .aws/credentials',
      'cp ~/.netrc /tmp/netrc-copy',
      'ls .ssh',
      'find .aws -maxdepth 1',
      'stat .config/gh/hosts.yml',
      'gh auth token',
      'security find-generic-password -a user -s service -w',
      'gcloud auth print-access-token',
      'firebase functions:secrets:access OPENAI_API_KEY',
      'aws configure get aws_secret_access_key',
      'op read op://Private/api-key/credential',
      'pass show production/api-token',
      'vault kv get secret/app',
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
    'CommandTools blocks network commands unless explicitly allowed',
    () async {
      final events = <CommandRunEvent>[];
      final blocked = await CommandTools(workingDir: '.').runCommand({
        'command': 'printf "%s" "https://example.com/status"',
      }, onEvent: events.add);

      expect(blocked, contains('Network command blocked'));
      expect(events.single.type, CommandRunEventType.blocked);

      final allowed = await CommandTools(workingDir: '.').runCommand({
        'command': 'printf "%s" "https://example.com/status"',
      }, allowNetwork: true);

      expect(allowed, 'https://example.com/status');
    },
  );

  test(
    'CommandTools blocks private network targets even when network is approved',
    () async {
      for (final command in [
        'curl http://localhost:3000/status',
        'curl http://127.0.0.1:8000/health',
        'curl http://10.1.2.3/status',
        'curl http://192.168.1.10/status',
        'curl http://169.254.169.254/latest/meta-data',
        'printf "%s" "http://service.local/status"',
      ]) {
        final events = <CommandRunEvent>[];
        final output = await CommandTools(workingDir: '.').runCommand(
          {'command': command},
          allowNetwork: true,
          onEvent: events.add,
        );

        expect(output, contains('Network target blocked'), reason: command);
        expect(
          events.single.type,
          CommandRunEventType.blocked,
          reason: command,
        );
      }
    },
  );

  test(
    'CommandTools blocks obfuscated private network targets even when network is approved',
    () async {
      for (final command in [
        'printf "%s" "http://0x7f000001:8000/health"',
        'printf "%s" "http://0177.0.0.1:8000/health"',
        'printf "%s" "http://2130706433:8000/health"',
        'printf "%s" "http://[::1]:8000/health"',
        'printf "%s" "http://[fe80::1]:8000/health"',
        'printf "%s" "http://[fd00::1]:8000/health"',
      ]) {
        final events = <CommandRunEvent>[];
        final output = await CommandTools(workingDir: '.').runCommand(
          {'command': command},
          allowNetwork: true,
          onEvent: events.add,
        );

        expect(output, contains('Network target blocked'), reason: command);
        expect(
          events.single.type,
          CommandRunEventType.blocked,
          reason: command,
        );
      }
    },
  );

  test(
    'CommandTools blocks DNS and programmatic socket access unless explicitly allowed',
    () async {
      for (final command in [
        'ping example.com',
        'dig example.com',
        'nslookup example.com',
        'host example.com',
        'whois example.com',
        'python3 -c "import socket; socket.create_connection((\'example.com\', 443))"',
        'python3 -c "import socket; socket.socket().connect((\'example.com\', 443))"',
        'python3 -c "import socket; socket.gethostbyname(\'example.com\')"',
        'python3 -c "from socket import socket; socket().connect((\'example.com\', 443))"',
        'node -e "require(\'net\').connect(443, \'example.com\')"',
        'node -e "require(\'tls\').connect(443, \'example.com\')"',
        'ruby -rsocket -e "TCPSocket.open(\'example.com\', 443)"',
        'perl -MIO::Socket::INET -e "IO::Socket::INET->new(PeerHost=>\'example.com\', PeerPort=>443)"',
      ]) {
        final events = <CommandRunEvent>[];
        final blocked = await CommandTools(
          workingDir: '.',
        ).runCommand({'command': command}, onEvent: events.add);

        expect(blocked, contains('Network command blocked'), reason: command);
        expect(events.single.type, CommandRunEventType.blocked);
      }

      final allowed = await CommandTools(workingDir: '.').runCommand({
        'command': 'printf "%s" "programmatic-network-approved"',
      }, allowNetwork: true);

      expect(allowed, 'programmatic-network-approved');
    },
  );

  test(
    'CommandTools blocks dependency network commands unless explicitly allowed',
    () async {
      for (final command in [
        'npm install left-pad',
        'python -m pip install requests',
        'pipx install poetry',
        'npx create-vite@latest demo',
        'pnpm dlx create-next-app demo',
        'yarn dlx create-vite demo',
        'bunx create-vite demo',
        'uvx ruff check .',
        'go mod download',
        'cargo fetch',
        'brew install wget',
        'flutter pub get',
        'firebase deploy --only hosting',
        'vercel deploy --prod',
        'gcloud run deploy circuit-service',
        'kubectl apply -f deploy.yaml',
        'gh workflow run release.yml',
        'firebase login',
        'gh auth login',
        'gcloud auth login',
        'aws sso login',
      ]) {
        final events = <CommandRunEvent>[];
        final blocked = await CommandTools(
          workingDir: '.',
        ).runCommand({'command': command}, onEvent: events.add);

        expect(blocked, contains('Network command blocked'), reason: command);
        expect(events.single.type, CommandRunEventType.blocked);
      }

      final allowed = await CommandTools(workingDir: '.').runCommand({
        'command': 'printf "%s" "package-network-approved"',
      }, allowNetwork: true);

      expect(allowed, 'package-network-approved');
    },
  );

  test(
    'ToolExecutor passes network allowance only after command review',
    () async {
      var reviewCount = 0;
      final executor =
          ToolExecutor(
            workingDir: '.',
            onConfirmationNeeded: (_) async {
              reviewCount++;
              return true;
            },
          )..setPermissionRequest(
            const ToolPermissionRequest(
              intent: TurnIntent.verify,
              phase: ToolPermissionPhase.verify,
            ),
          );

      final results = await executor.executeToolCalls([
        const ToolCallInfo(
          id: 'approved-network-like-command',
          name: 'run_command',
          arguments: {
            'command': 'printf "%s" "https://example.com/status"',
            'timeout': 5,
          },
        ),
      ]);

      expect(reviewCount, 1);
      expect(results.single.success, isTrue);
      expect(results.single.result, 'https://example.com/status');
    },
  );

  test(
    'ToolExecutor never dispatches run_command through the generic path',
    () async {
      final source = await File(
        'lib/agent/tools/tool_executor.dart',
      ).readAsString();
      final dispatchStart = source.indexOf('Future<String> _dispatch');
      expect(dispatchStart, isNonNegative);
      final commandBranch = source.indexOf(
        "case 'run_command':",
        dispatchStart,
      );
      expect(commandBranch, isNonNegative);
      final nextBranch = source.indexOf("case 'web_fetch':", commandBranch);
      expect(nextBranch, isNonNegative);
      final branchSource = source.substring(commandBranch, nextBranch);

      expect(branchSource, isNot(contains('_commandTools.runCommand(args)')));
      expect(
        branchSource,
        contains('reviewed command execution path'),
        reason:
            'run_command must always pass through _executeCommandTool so network approval, event streaming, and command policy cannot be bypassed.',
      );
    },
  );

  test(
    'ToolExecutor never dispatches GitHub mutation through the generic path',
    () async {
      final source = await File(
        'lib/agent/tools/tool_executor.dart',
      ).readAsString();
      final dispatchStart = source.indexOf('Future<String> _dispatch');
      expect(dispatchStart, isNonNegative);
      final createIssueCase = source.indexOf(
        "case 'github_create_issue':",
        dispatchStart,
      );
      final closeIssueCase = source.indexOf(
        "case 'github_close_issue':",
        dispatchStart,
      );
      final createRepoCase = source.indexOf(
        "case 'github_create_repo':",
        dispatchStart,
      );
      expect(createIssueCase, isNonNegative);
      expect(closeIssueCase, isNonNegative);
      expect(createRepoCase, isNonNegative);
      final orchestrationMarker = source.indexOf(
        '// Orchestration tool',
        createIssueCase,
      );
      expect(orchestrationMarker, isNonNegative);
      final mutationBranch = source.substring(
        createIssueCase,
        orchestrationMarker,
      );

      expect(mutationBranch, isNot(contains('_githubTools.execute')));
      expect(
        mutationBranch,
        contains('GitHub mutation tools are unavailable'),
        reason:
            'GitHub mutation must stay feature-gated and unavailable from the generic dispatcher until it has Studio-scoped permissions and tests.',
      );
    },
  );

  test(
    'CommandTools scrubs ambient secrets from command environment',
    () async {
      final output =
          await CommandTools(
            workingDir: '.',
            environment: {
              'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
              'HOME': Platform.environment['HOME'] ?? '/tmp',
              'CIRCUIT_SECRET_TOKEN': 'should-not-leak',
              'OPENAI_API_KEY': 'should-not-leak',
              'LANG': 'en_US.UTF-8',
            },
          ).runCommand({
            'command': 'printf "%s|%s" "\$CIRCUIT_SECRET_TOKEN" "\$PATH"',
          });

      expect(output, isNot(contains('should-not-leak')));
      expect(output, startsWith('|'));
      expect(output.length, greaterThan(1));
    },
  );

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
    expect(run.requestId, isNull);
    expect(run.turnId, isNull);
    expect(run.taskId, isNull);
    expect(run.stdout, 'hello\n');
    expect(run.combinedOutput, 'hello');
    expect(run.exitCode, 0);
  });

  test(
    'CommandRunController listens to Studio runtime events, not legacy bus',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(commandRunProvider.notifier);
      final runtimeEvents = EventBus();
      addTearDown(runtimeEvents.dispose);

      controller.attachRuntimeEvents('request-command', runtimeEvents);
      runtimeEvents.emit(EventType.toolCallStarted, {
        'requestId': 'request-command',
        'toolCall': const ToolCallInfo(
          id: 'cmd-runtime',
          name: 'run_command',
          status: ToolStatus.running,
          arguments: {'command': 'pwd'},
        ),
      });
      runtimeEvents.emit(EventType.toolCallCompleted, {
        'requestId': 'request-command',
        'toolCall': const ToolCallInfo(
          id: 'cmd-runtime',
          name: 'run_command',
          status: ToolStatus.success,
          result: '/tmp/project',
          arguments: {'command': 'pwd'},
        ),
      });

      final run = container.read(commandRunProvider)['cmd-runtime']!;
      expect(run.requestId, 'request-command');
      expect(run.command, 'pwd');
      expect(run.stdout, '/tmp/project');
      expect(run.status, CommandRunStatus.succeeded);

      final unattachedEvents = EventBus();
      addTearDown(unattachedEvents.dispose);
      unattachedEvents.emit(EventType.toolCallStarted, {
        'requestId': 'legacy-request',
        'toolCall': const ToolCallInfo(
          id: 'cmd-legacy',
          name: 'run_command',
          status: ToolStatus.running,
          arguments: {'command': 'ls'},
        ),
      });
      expect(
        container.read(commandRunProvider).containsKey('cmd-legacy'),
        isFalse,
      );
    },
  );

  test('CommandRunController records command outcome on Studio turn', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .createBlankThread(title: 'Verify command');
    final turn = container
        .read(studioTurnProvider.notifier)
        .registerTurn(
          requestId: 'request-command-turn',
          threadId: thread.id,
          taskId: null,
          userMessageId: 'message-command-turn',
          prompt: 'Run verification',
          model: 'gpt-5-nano',
          contextSummary: const StudioContextSummary(
            rootPath: '/tmp/project',
            projectLabel: 'project',
          ),
          intent: TurnIntent.verify,
        );
    final controller = container.read(commandRunProvider.notifier);
    final runtimeEvents = EventBus();
    addTearDown(runtimeEvents.dispose);

    controller.attachRuntimeEvents('request-command-turn', runtimeEvents);
    runtimeEvents.emit(EventType.toolCallStarted, {
      'requestId': 'request-command-turn',
      'toolCall': const ToolCallInfo(
        id: 'cmd-turn',
        name: 'run_command',
        status: ToolStatus.running,
        arguments: {'command': 'flutter test'},
      ),
    });
    runtimeEvents.emit(EventType.toolCallCompleted, {
      'requestId': 'request-command-turn',
      'toolCall': const ToolCallInfo(
        id: 'cmd-turn',
        name: 'run_command',
        status: ToolStatus.success,
        result: 'All tests passed!',
        arguments: {'command': 'flutter test'},
      ),
    });

    final updatedTurn = container
        .read(studioThreadProvider)
        .threads
        .singleWhere((candidate) => candidate.id == thread.id)
        .turns
        .singleWhere((candidate) => candidate.id == turn.id);
    final event = updatedTurn.events.singleWhere(
      (candidate) =>
          candidate.type == StudioTurnEventType.completionSummary &&
          candidate.title == 'Ran command',
    );
    expect(event.id, 'command-run-${turn.id}-cmd-turn');
    expect(event.detail, contains('Command: flutter test'));
    expect(event.detail, contains('Exit code: 0'));
    expect(event.detail, contains('All tests passed!'));
    final commandStep = updatedTurn.steps.singleWhere(
      (candidate) => candidate.step == TurnStep.commandRun,
    );
    expect(commandStep.status, TurnStepStatus.completed);
    expect(commandStep.detail, contains('flutter test'));
    final verificationStep = updatedTurn.steps.singleWhere(
      (candidate) => candidate.step == TurnStep.verification,
    );
    expect(verificationStep.status, TurnStepStatus.completed);
    expect(verificationStep.detail, contains('flutter test'));
  });

  test('CommandRun serializes status, output, and event timeline', () {
    final run = CommandRun(
      id: 'cmd-json',
      requestId: 'request-json',
      turnId: 'turn-json',
      taskId: 'task-json',
      command: 'flutter test',
      status: CommandRunStatus.failed,
      startedAt: DateTime(2026),
      endedAt: DateTime(2026, 1, 1, 0, 0, 2),
      exitCode: 1,
      stdout: 'running\n',
      stderr: 'failed\n',
      events: [
        CommandRunEvent(
          type: CommandRunEventType.started,
          timestamp: DateTime(2026),
          text: 'flutter test',
        ),
        CommandRunEvent(
          type: CommandRunEventType.stderr,
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
          text: 'failed\n',
        ),
        CommandRunEvent(
          type: CommandRunEventType.exited,
          timestamp: DateTime(2026, 1, 1, 0, 0, 2),
          text: 'exit 1',
        ),
      ],
    );

    final restored = CommandRun.fromJson(run.toJson());

    expect(restored, isNotNull);
    expect(restored!.id, 'cmd-json');
    expect(restored.requestId, 'request-json');
    expect(restored.turnId, 'turn-json');
    expect(restored.taskId, 'task-json');
    expect(restored.command, 'flutter test');
    expect(restored.status, CommandRunStatus.failed);
    expect(restored.exitCode, 1);
    expect(restored.stdout, 'running\n');
    expect(restored.stderr, 'failed\n');
    expect(restored.events.map((event) => event.type), [
      CommandRunEventType.started,
      CommandRunEventType.stderr,
      CommandRunEventType.exited,
    ]);
    expect(restored.combinedOutput, contains('[stderr] failed'));
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
        .start(
          id: 'cmd-studio',
          command: 'flutter test',
          requestId: 'request-1',
          turnId: 'turn-1',
        );

    final updatedTask = container.read(agentWorkspaceProvider).tasks.single;
    final run = container.read(commandRunProvider)['cmd-studio']!;
    expect(run.requestId, 'request-1');
    expect(run.turnId, 'turn-1');
    expect(run.taskId, task.id);
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
          workspaceRoot: Directory.systemTemp.path,
          phase: AgentTurnPhase.toolExecution,
          startedAt: DateTime(2026),
        ),
      },
    );
  }
}
