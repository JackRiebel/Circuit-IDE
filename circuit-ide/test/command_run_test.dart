import 'package:circuit_ide/agent/tools/command_tools.dart';
import 'package:circuit_ide/models/command_run.dart';
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
}
