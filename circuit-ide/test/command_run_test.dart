import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/agent/tools/command_tools.dart';
import 'package:circuit_ide/agent/security/child_process_environment.dart';
import 'package:circuit_ide/core/utils/platform_utils.dart';
import 'package:circuit_ide/agent/security/macos_execution_boundary.dart';
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
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:circuit_ide/state/studio_turn_provider.dart';
import 'package:circuit_ide/services/event_bus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS development command turns retain a no-network fallback', () {
    final launch = MacOsExecutionBoundary.forShellCommand(
      shell: '/bin/sh',
      shellArgs: const ['-c'],
      command: 'printf safe',
      workingDirectory: Directory.current.path,
      cpuLimitSeconds: 5,
      allowNetwork: false,
    );

    if (Platform.isMacOS && File('/usr/bin/sandbox-exec').existsSync()) {
      expect(launch.executable, '/usr/bin/sandbox-exec');
      expect(launch.arguments, [
        '-n',
        'no-internet',
        '/bin/sh',
        '-c',
        'printf safe',
      ]);
    } else {
      expect(launch.executable, '/bin/sh');
      expect(launch.arguments, ['-c', 'printf safe']);
    }
  });

  test(
    'explicit network approval is the only path that bypasses no-network',
    () {
      final launch = MacOsExecutionBoundary.forShellCommand(
        shell: '/bin/sh',
        shellArgs: const ['-c'],
        command: 'printf approved',
        workingDirectory: Directory.current.path,
        cpuLimitSeconds: 5,
        allowNetwork: true,
      );

      expect(launch.executable, '/bin/sh');
      expect(launch.arguments, ['-c', 'printf approved']);
    },
  );

  test(
    'a packaged macOS app fails closed when its broker is missing',
    () async {
      if (!Platform.isMacOS) return;
      final contents = await Directory.systemTemp.createTemp(
        'missing-packaged-broker-',
      );
      addTearDown(() => contents.delete(recursive: true));
      MacOsExecutionBoundary.debugPackagedContentsDirectoryOverride =
          contents.path;
      addTearDown(() {
        MacOsExecutionBoundary.debugPackagedContentsDirectoryOverride = null;
        MacOsExecutionBoundary.debugBrokerExecutableOverride = null;
      });

      final launch = MacOsExecutionBoundary.forShellCommand(
        shell: '/bin/sh',
        shellArgs: const ['-c'],
        command: 'touch must-not-run',
        workingDirectory: contents.path,
        cpuLimitSeconds: 5,
        allowNetwork: true,
      );

      expect(launch.isDenied, isTrue);
      expect(launch.executable, isEmpty);
      expect(
        launch.denialMessage,
        MacOsExecutionBoundary.packagedBrokerUnavailableMessage,
      );

      final events = <CommandRunEvent>[];
      final output = await CommandTools(workingDir: contents.path).runCommand(
        const {'command': 'touch must-not-run', 'timeout': 5},
        onEvent: events.add,
      );
      expect(
        output,
        'Error: ${MacOsExecutionBoundary.packagedBrokerUnavailableMessage}',
      );
      expect(events, hasLength(1));
      expect(events.single.type, CommandRunEventType.stderr);
      expect(
        events.single.text,
        MacOsExecutionBoundary.packagedBrokerUnavailableMessage,
      );
      expect(File('${contents.path}/must-not-run').existsSync(), isFalse);
    },
  );

  test('brokered commands forward only reviewed executable roots', () async {
    if (!Platform.isMacOS) return;
    final directory = await Directory.systemTemp.createTemp('broker-roots-');
    addTearDown(() => directory.delete(recursive: true));
    final broker = File('${directory.path}/CircuitExecutionBroker')
      ..createSync();
    MacOsExecutionBoundary.debugBrokerExecutableOverride = broker.path;
    addTearDown(() {
      MacOsExecutionBoundary.debugBrokerExecutableOverride = null;
    });

    final launch = MacOsExecutionBoundary.forShellCommand(
      shell: '/bin/sh',
      shellArgs: const ['-c'],
      command: 'printf brokered',
      workingDirectory: directory.path,
      cpuLimitSeconds: 10,
      allowNetwork: false,
      toolRoots: const [
        '/usr/bin',
        '/opt/homebrew/bin',
        '/Users/example/.cache/runtime/bin',
        '/',
      ],
    );

    expect(launch.brokered, isTrue);
    expect(launch.arguments, containsAllInOrder(['--tool-root', '/usr/bin']));
    expect(
      launch.arguments,
      containsAllInOrder(['--tool-root', '/opt/homebrew/bin']),
    );
    expect(
      launch.arguments,
      isNot(contains('/Users/example/.cache/runtime/bin')),
    );
    expect(launch.arguments, isNot(contains('/')));
  });

  test('a configured packaged broker completes a sanitized command', () async {
    final brokerPath = Platform.environment['CIRCUIT_SOAK_BROKER_PATH']?.trim();
    if (!Platform.isMacOS ||
        brokerPath == null ||
        brokerPath.isEmpty ||
        !File(brokerPath).existsSync()) {
      return;
    }

    final root = await Directory.systemTemp.createTemp('broker-command-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/marker.dart').create(recursive: true);
    MacOsExecutionBoundary.debugBrokerExecutableOverride = brokerPath;
    addTearDown(() {
      MacOsExecutionBoundary.debugBrokerExecutableOverride = null;
    });

    final launch = MacOsExecutionBoundary.forShellCommand(
      shell: PlatformUtils.shell,
      shellArgs: PlatformUtils.shellArgs,
      command: 'test -f lib/marker.dart',
      workingDirectory: root.path,
      cpuLimitSeconds: 10,
      allowNetwork: false,
      toolRoots: Platform.environment['PATH']!
          .split(Platform.pathSeparator)
          .where((entry) => entry.startsWith('/'))
          .toList(growable: false),
    );
    try {
      final process = await Process.start(
        launch.executable,
        launch.arguments,
        workingDirectory: root.path,
        environment: ChildProcessEnvironment.build(
          baseEnvironment: Platform.environment,
        ),
      );
      expect(await process.exitCode, 0);
    } on ProcessException catch (error) {
      fail('packaged_broker_process_start_${error.errorCode}');
    }

    final events = <CommandRunEvent>[];
    final output = await CommandTools(workingDir: root.path).runCommand({
      'command': 'test -f lib/marker.dart',
      'timeout': 10,
    }, onEvent: events.add);

    expect(output, '(no output)');
    expect(events.last.type, CommandRunEventType.exited);
    expect(events.last.text, 'exit 0');
  });

  test('a bundled macOS broker receives the reviewed execution policy', () {
    if (!Platform.isMacOS) return;

    final directory = Directory.systemTemp.createTempSync(
      'circuit-broker-test-',
    );
    final broker = File('${directory.path}/CircuitExecutionBroker')
      ..createSync();
    MacOsExecutionBoundary.debugBrokerExecutableOverride = broker.path;
    addTearDown(() {
      MacOsExecutionBoundary.debugBrokerExecutableOverride = null;
      directory.deleteSync(recursive: true);
    });

    final launch = MacOsExecutionBoundary.forShellCommand(
      shell: '/bin/sh',
      shellArgs: const ['-c'],
      command: 'printf brokered',
      workingDirectory: Directory.current.path,
      cpuLimitSeconds: 7,
      allowNetwork: true,
      toolRoots: const ['/usr/local/bin'],
    );

    expect(launch.executable, broker.path);
    expect(launch.brokered, isTrue);
    expect(launch.arguments, [
      '--workspace',
      Directory.current.path,
      '--network',
      'allow',
      '--cpu-limit',
      '7',
      '--tool-root',
      '/usr/local/bin',
      '--',
      '/bin/sh',
      '-c',
      'printf brokered',
    ]);
  });

  test('macOS release keeps the broker build and escape harness wired', () {
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final harness = File(
      'scripts/verify_execution_broker.sh',
    ).readAsStringSync();
    final broker = File(
      'macos/Runner/CircuitExecutionBroker.swift',
    ).readAsStringSync();
    final workflow = File('../.github/workflows/ci.yml').readAsStringSync();

    expect(project, contains('Build Circuit execution broker'));
    expect(project, contains('CircuitExecutionBroker.swift'));
    expect(project, contains('swiftc -parse-as-library'));
    expect(harness, contains('symlink escape read'));
    expect(harness, contains('system-selected shell was denied'));
    expect(harness, contains('path-sentinel'));
    expect(harness, contains('broker-harness-term-sentinel'));
    expect(harness, contains('untrusted tool root'));
    expect(harness, contains('broker launch denial'));
    expect(harness, contains('temporary-directory symlink'));
    expect(harness, contains('network egress'));
    expect(harness, contains('unrelated process inspection'));
    expect(harness, contains('system Keychain metadata'));
    expect(
      broker,
      contains(
        'Circuit execution broker denied launch. Check the execution boundary and try again.',
      ),
    );
    expect(broker, isNot(contains('error.localizedDescription')));
    expect(
      broker,
      contains(
        '/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin',
      ),
    );
    expect(
      broker,
      isNot(contains('ProcessInfo.processInfo.environment["PATH"]')),
    );
    expect(broker, contains('destinationOfSymbolicLink'));
    expect(broker, contains('isStrictDescendant'));
    expect(broker, contains('keychainDenyRules'));
    expect(broker, contains('Library/Keychains'));
    expect(workflow, contains('verify_execution_broker.sh'));
  });

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

  test('CommandTools redacts and records a process launch failure', () async {
    final root = await Directory.systemTemp.createTemp(
      'circuit-command-launch-failure-',
    );
    addTearDown(() => root.delete(recursive: true));
    final missingDirectory = '${root.path}/missing-workspace';
    final events = <CommandRunEvent>[];

    final output = await CommandTools(workingDir: missingDirectory).runCommand({
      'command': 'printf launch-sentinel',
      'timeout': 5,
    }, onEvent: events.add);

    expect(
      output,
      'Error: Command process could not start. Check the execution boundary and try again.',
    );
    expect(events, hasLength(1));
    expect(events.single.type, CommandRunEventType.stderr);
    expect(
      events.single.text,
      'Command process could not start. Check the execution boundary and try again.',
    );
    expect(events.single.text, isNot(contains(root.path)));
    expect(events.single.text, isNot(contains('launch-sentinel')));
  });

  test(
    'CommandTools redacts an unexpected callback error and terminates its child',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-command-callback-failure-',
      );
      addTearDown(() => root.delete(recursive: true));
      int? launchedPid;

      final output = await CommandTools(workingDir: root.path).runCommand(
        {'command': 'sleep 30', 'timeout': 5},
        onEvent: (event) {
          if (event.type != CommandRunEventType.started) return;
          launchedPid = event.processId;
          throw StateError('callback diagnostic contained callback-secret');
        },
      );

      expect(
        output,
        'Error: Command process failed before completion. Check the execution boundary and try again.',
      );
      expect(output, isNot(contains('callback-secret')));
      expect(launchedPid, isNotNull);
      final processLookup = await Process.run('/bin/ps', [
        '-p',
        '$launchedPid',
        '-o',
        'pid=',
      ]);
      expect(processLookup.stdout.toString().trim(), isEmpty);
    },
  );

  test(
    'CommandTools stops a command that exceeds its output resource limit',
    () async {
      final events = <CommandRunEvent>[];
      final output = await CommandTools(workingDir: '.', maxOutputBytes: 32)
          .runCommand({
            'command':
                'python3 -c "import sys,time; sys.stdout.write(\'x\'*64); sys.stdout.flush(); time.sleep(1)"',
            'timeout': 5,
          }, onEvent: events.add);

      expect(
        output,
        contains('Command output exceeded the 32 byte resource limit'),
      );
      expect(
        events.map((event) => event.text).join('\n'),
        contains('process was stopped'),
      );
    },
  );

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
        'open ${outside.path}',
        'qlmanage -p ${outside.path}',
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
      'python -c "import os; print(os.environ)"',
      'python -c "from os import getenv; print(getenv(\'HOME\'))"',
      'python -c "from dotenv import load_dotenv; load_dotenv()"',
      'node -e "console.log(process.env)"',
      'ruby -e "puts ENV.to_h"',
      'php -r "echo getenv(\'HOME\');"',
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
        'python3 -c "import http.client; http.client.HTTPSConnection(\'example.com\')"',
        'python3 -c "import urllib3; urllib3.PoolManager()"',
        'python3 -c "import httpx; httpx.Client()"',
        'python3 -c "import aiohttp; aiohttp.ClientSession()"',
        'node -e "require(\'net\').connect(443, \'example.com\')"',
        'node -e "require(\'tls\').connect(443, \'example.com\')"',
        'ruby -rsocket -e "TCPSocket.open(\'example.com\', 443)"',
        'ruby -rnet/http -e "Net::HTTP.start(\'example.com\', 443)"',
        'perl -MIO::Socket::INET -e "IO::Socket::INET->new(PeerHost=>\'example.com\', PeerPort=>443)"',
        'perl -MLWP::UserAgent -e "LWP::UserAgent->new"',
        'php -r "curl_init(\'example.com\');"',
        'php -r "fsockopen(\'example.com\', 443);"',
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
      final defaultCase = source.indexOf('default:', createIssueCase);
      expect(defaultCase, isNonNegative);
      final mutationBranch = source.substring(createIssueCase, defaultCase);

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

  test('CommandTools cancellation terminates spawned descendants', () async {
    final root = await Directory.systemTemp.createTemp('command-tree-cancel-');
    addTearDown(() => root.delete(recursive: true));
    final marker = File('${root.path}/orphan.txt');
    final child =
        "import time; time.sleep(2); open(r'${marker.path}', 'w').write('orphan')";
    final parent =
        "import subprocess,sys,time; subprocess.Popen([sys.executable, '-c', ${jsonEncode(child)}]); time.sleep(10)";
    final tools = CommandTools(workingDir: root.path);

    final running = tools.runCommand({
      'command': 'python3 -c ${jsonEncode(parent)}',
      'timeout': 20,
    }, runId: 'tree-cancel');
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(tools.cancel('tree-cancel'), isTrue);
    await running;
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(await marker.exists(), isFalse);
  });

  test('CommandTools timeout terminates spawned descendants', () async {
    final root = await Directory.systemTemp.createTemp('command-tree-timeout-');
    addTearDown(() => root.delete(recursive: true));
    final marker = File('${root.path}/orphan.txt');
    // The command tool enforces a five-second minimum timeout. Keep the child
    // alive longer than that threshold so a marker proves a timeout orphan.
    final child =
        "import time; time.sleep(8); open(r'${marker.path}', 'w').write('orphan')";
    final parent =
        "import subprocess,sys,time; subprocess.Popen([sys.executable, '-c', ${jsonEncode(child)}]); time.sleep(10)";
    final output = await CommandTools(
      workingDir: root.path,
    ).runCommand({'command': 'python3 -c ${jsonEncode(parent)}', 'timeout': 1});

    expect(output, contains('Command timed out'));
    await Future<void>.delayed(const Duration(milliseconds: 3300));
    expect(await marker.exists(), isFalse);
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
    expect(run.exitReason, CommandExitReason.completed);
    expect(run.environmentPolicy, 'sanitized-allowlist');
  });

  test(
    'Command runs persist logs and recover active runs as interrupted',
    () async {
      final root = await Directory.systemTemp.createTemp('command-run-root-');
      final storeRoot = await Directory.systemTemp.createTemp(
        'command-run-store-',
      );
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => storeRoot.delete(recursive: true));
      final store = CommandRunStore(baseDir: storeRoot.path);
      final logPath = store.logPath(root.path, 'interrupted-command');
      await store.appendLog(
        logPath,
        '[started] flutter test\nstdout: running\n',
      );
      await store.save(root.path, [
        CommandRun(
          id: 'interrupted-command',
          command: 'flutter test',
          workingDirectory: root.path,
          timeoutSeconds: 120,
          logPath: logPath,
          processId: 4242,
          status: CommandRunStatus.running,
          startedAt: DateTime(2026),
        ),
      ]);

      final container = ProviderContainer(
        overrides: [commandRunStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);
      container.read(commandRunProvider);
      for (var index = 0; index < 30; index++) {
        final run = container.read(commandRunProvider)['interrupted-command'];
        if (run?.exitReason == CommandExitReason.interrupted) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final recovered = container.read(
        commandRunProvider,
      )['interrupted-command']!;
      expect(recovered.status, CommandRunStatus.failed);
      expect(recovered.exitReason, CommandExitReason.interrupted);
      expect(recovered.processId, 4242);
      expect(recovered.logPath, logPath);
      expect(await File(logPath).readAsString(), contains('flutter test'));
      final persisted = (await store.load(root.path)).single;
      expect(persisted.exitReason, CommandExitReason.interrupted);
    },
  );

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

  test(
    'CommandRunController runs direct verification command on Studio turn',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'direct_verify_command_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .createBlankThread(title: 'Direct verify command');
      final turn = container
          .read(studioTurnProvider.notifier)
          .registerTurn(
            requestId: 'request-direct-command-turn',
            threadId: thread.id,
            taskId: null,
            userMessageId: 'message-direct-command-turn',
            prompt: 'Run verification',
            model: 'gpt-5-nano',
            contextSummary: StudioContextSummary(
              rootPath: root.path,
              projectLabel: 'project',
            ),
            intent: TurnIntent.verify,
          );

      final run = await container
          .read(commandRunProvider.notifier)
          .runVerificationCommand(
            id: 'cmd-direct-turn',
            command: 'python3 -c "print(\'direct-ok\')"',
            workingDir: root.path,
            requestId: 'request-direct-command-turn',
            turnId: turn.id,
            userApproved: true,
          );

      expect(run.status, CommandRunStatus.succeeded);
      expect(run.exitCode, 0);
      expect(run.stdout, contains('direct-ok'));
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
      expect(event.id, 'command-run-${turn.id}-cmd-direct-turn');
      expect(event.detail, contains('Command: python3 -c'));
      expect(event.detail, contains('direct-ok'));
      final verificationStep = updatedTurn.steps.singleWhere(
        (candidate) => candidate.step == TurnStep.verification,
      );
      expect(verificationStep.status, TurnStepStatus.completed);
      expect(verificationStep.detail, contains('direct-ok'));
    },
  );

  test(
    'CommandRunController blocks unapproved direct verification commands',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'unapproved_verify_command_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final run = await container
          .read(commandRunProvider.notifier)
          .runVerificationCommand(
            id: 'cmd-unapproved',
            command: 'printf "%s" "must-not-run"',
            workingDir: root.path,
          );

      expect(run.status, CommandRunStatus.blocked);
      expect(run.combinedOutput, contains('requires review'));
    },
  );

  test(
    'CommandRunController persists a safe diagnostic when launch fails',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-command-run-launch-failure-',
      );
      addTearDown(() => root.delete(recursive: true));
      final missingDirectory = '${root.path}/missing-workspace';
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final run = await container
          .read(commandRunProvider.notifier)
          .runVerificationCommand(
            id: 'cmd-launch-failure',
            command: 'printf launch-sentinel',
            workingDir: missingDirectory,
            userApproved: true,
          );

      expect(run.status, CommandRunStatus.failed);
      expect(run.exitCode, isNull);
      expect(run.endedAt, isNotNull);
      expect(
        run.stderr,
        'Command process could not start. Check the execution boundary and try again.',
      );
      expect(run.combinedOutput, contains('Command process could not start'));
      expect(run.combinedOutput, isNot(contains(root.path)));
      expect(run.combinedOutput, isNot(contains('launch-sentinel')));
      expect(
        run.events.map((event) => event.type),
        contains(CommandRunEventType.stderr),
      );
    },
  );

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
