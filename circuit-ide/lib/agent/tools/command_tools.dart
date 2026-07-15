import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/utils/platform_utils.dart';
import '../../models/command_run.dart';
import '../security/child_process_environment.dart';
import '../security/command_sanitizer.dart';
import '../security/macos_execution_boundary.dart';

typedef CommandRunEventCallback = void Function(CommandRunEvent event);

/// A bounded-output refusal is safe to show to the user because its message
/// is constructed entirely by this process. It must stay distinct from an
/// arbitrary [StateError], which may originate in a connector, codec, or
/// callback and can contain unsafe diagnostic text.
class _CommandOutputLimitException implements Exception {
  final String message;

  const _CommandOutputLimitException(this.message);
}

class CommandTools {
  final String workingDir;
  final int maxOutputBytes;
  final Map<String, String> _baseEnvironment;
  final Map<String, Process> _activeProcesses = {};

  CommandTools({
    required this.workingDir,
    Map<String, String>? environment,
    this.maxOutputBytes = AppConstants.commandOutputMaxBytes,
  }) : assert(maxOutputBytes > 0),
       _baseEnvironment = environment ?? Platform.environment;

  Future<String> runCommand(
    Map<String, dynamic> args, {
    String? runId,
    bool allowNetwork = false,
    CommandRunEventCallback? onEvent,
  }) async {
    final command = args['command'] as String;
    final timeout =
        (args['timeout'] as int?)?.clamp(
          AppConstants.commandTimeoutMin,
          AppConstants.commandTimeoutMax,
        ) ??
        AppConstants.commandTimeoutDefault;

    // Check for dangerous commands
    final danger = CommandSanitizer.checkDangerous(command);
    if (danger != null) {
      onEvent?.call(
        CommandRunEvent(
          type: CommandRunEventType.blocked,
          timestamp: DateTime.now(),
          text: danger,
        ),
      );
      return 'Error: Potentially dangerous command blocked: $danger';
    }
    final networkAccess = CommandSanitizer.checkNetworkAccess(command);
    final blockedNetworkTarget = CommandSanitizer.checkBlockedNetworkTarget(
      command,
    );
    if (blockedNetworkTarget != null) {
      onEvent?.call(
        CommandRunEvent(
          type: CommandRunEventType.blocked,
          timestamp: DateTime.now(),
          text: blockedNetworkTarget,
        ),
      );
      return 'Error: Network target blocked: $blockedNetworkTarget';
    }
    if (!allowNetwork && networkAccess != null) {
      onEvent?.call(
        CommandRunEvent(
          type: CommandRunEventType.blocked,
          timestamp: DateTime.now(),
          text: networkAccess,
        ),
      );
      return 'Error: Network command blocked: $networkAccess';
    }
    final workspaceBoundary = CommandSanitizer.checkWorkspaceBoundary(
      command,
      workingDir,
    );
    if (workspaceBoundary != null) {
      onEvent?.call(
        CommandRunEvent(
          type: CommandRunEventType.blocked,
          timestamp: DateTime.now(),
          text: workspaceBoundary,
        ),
      );
      return 'Error: Workspace boundary blocked: $workspaceBoundary';
    }

    Process? process;
    Timer? timer;
    try {
      final launch = MacOsExecutionBoundary.forShellCommand(
        shell: PlatformUtils.shell,
        shellArgs: PlatformUtils.shellArgs,
        command: command,
        workingDirectory: workingDir,
        cpuLimitSeconds: timeout,
        allowNetwork: allowNetwork,
        toolRoots: _toolRoots(),
      );
      if (launch.isDenied) {
        final message = launch.denialMessage!;
        onEvent?.call(
          CommandRunEvent(
            type: CommandRunEventType.stderr,
            timestamp: DateTime.now(),
            text: message,
          ),
        );
        return 'Error: $message';
      }
      process = await Process.start(
        launch.executable,
        launch.arguments,
        workingDirectory: workingDir,
        environment: _sanitizedEnvironment(),
      );
      if (runId != null) _activeProcesses[runId] = process;
      final processGroupId = await _processGroupId(process.pid);
      onEvent?.call(
        CommandRunEvent(
          type: CommandRunEventType.started,
          timestamp: DateTime.now(),
          text: command,
          processId: process.pid,
          processGroupId: processGroupId,
        ),
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final completer = Completer<int>();
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      var capturedOutputBytes = 0;
      var outputLimitReached = false;

      void captureOutput(
        String chunk,
        StringBuffer buffer,
        CommandRunEventType type,
      ) {
        if (outputLimitReached) return;
        final chunkBytes = utf8.encode(chunk).length;
        if (capturedOutputBytes + chunkBytes > maxOutputBytes) {
          outputLimitReached = true;
          final detail =
              'Command output exceeded the $maxOutputBytes byte resource limit; the process was stopped.';
          onEvent?.call(
            CommandRunEvent(
              type: CommandRunEventType.stderr,
              timestamp: DateTime.now(),
              text: detail,
            ),
          );
          if (process != null) unawaited(_terminateProcessTree(process));
          if (!completer.isCompleted) {
            completer.completeError(_CommandOutputLimitException(detail));
          }
          return;
        }
        capturedOutputBytes += chunkBytes;
        buffer.write(chunk);
        onEvent?.call(
          CommandRunEvent(type: type, timestamp: DateTime.now(), text: chunk),
        );
      }

      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              captureOutput(chunk, stdoutBuffer, CommandRunEventType.stdout);
            },
            onDone: () {
              if (!stdoutDone.isCompleted) stdoutDone.complete();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!stdoutDone.isCompleted) {
                stdoutDone.completeError(error, stackTrace);
              }
            },
          );
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              captureOutput(chunk, stderrBuffer, CommandRunEventType.stderr);
            },
            onDone: () {
              if (!stderrDone.isCompleted) stderrDone.complete();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!stderrDone.isCompleted) {
                stderrDone.completeError(error, stackTrace);
              }
            },
          );

      timer = Timer(Duration(seconds: timeout), () {
        if (completer.isCompleted) return;
        if (process != null) unawaited(_terminateProcessTree(process));
        onEvent?.call(
          CommandRunEvent(
            type: CommandRunEventType.timedOut,
            timestamp: DateTime.now(),
            text: 'Command timed out after ${timeout}s',
          ),
        );
        completer.completeError(TimeoutException('Command timed out'));
      });

      unawaited(
        process.exitCode.then((code) {
          if (!completer.isCompleted) completer.complete(code);
        }),
      );

      final exitCode = await completer.future;
      if (runId != null) _activeProcesses.remove(runId);
      timer.cancel();
      await Future.wait([stdoutDone.future, stderrDone.future]);
      await stdoutSub.cancel();
      await stderrSub.cancel();
      onEvent?.call(
        CommandRunEvent(
          type: CommandRunEventType.exited,
          timestamp: DateTime.now(),
          text: 'exit $exitCode',
        ),
      );

      final stdout = stdoutBuffer.toString().trim();
      final stderr = stderrBuffer.toString().trim();

      final output = StringBuffer();
      if (stdout.isNotEmpty) output.writeln(stdout);
      if (stderr.isNotEmpty) {
        if (output.isNotEmpty) output.writeln();
        output.writeln('[stderr] $stderr');
      }

      if (exitCode != 0) {
        output.writeln('\n[exit code: $exitCode]');
      }

      final text = output.toString().trim();
      // Truncate very long output
      if (text.length > 50000) {
        return '${text.substring(0, 25000)}\n\n... (output truncated, ${text.length} chars total) ...\n\n${text.substring(text.length - 5000)}';
      }
      return text.isEmpty ? '(no output)' : text;
    } on _CommandOutputLimitException catch (error) {
      if (runId != null) _activeProcesses.remove(runId);
      return 'Error: ${error.message}';
    } on ProcessException {
      if (runId != null) _activeProcesses.remove(runId);
      // OS launch errors may include an executable path, working-directory
      // spelling, or platform diagnostic. Preserve a durable actionable event
      // without allowing those host details into the Studio transcript.
      const message =
          'Command process could not start. Check the execution boundary and try again.';
      onEvent?.call(
        CommandRunEvent(
          type: CommandRunEventType.stderr,
          timestamp: DateTime.now(),
          text: message,
        ),
      );
      return 'Error: $message';
    } on TimeoutException {
      if (runId != null) _activeProcesses.remove(runId);
      return 'Error: Command timed out after ${timeout}s';
    } catch (_) {
      if (runId != null) _activeProcesses.remove(runId);
      // An unexpected failure after Process.start can arise from a caller
      // callback or a stream/codec boundary. It must neither reflect raw
      // diagnostic data into Studio nor leave an already-started child alive.
      if (process != null) await _terminateProcessTree(process);
      return 'Error: Command process failed before completion. Check the execution boundary and try again.';
    } finally {
      timer?.cancel();
    }
  }

  bool cancel(String runId) {
    final process = _activeProcesses.remove(runId);
    if (process == null) return false;
    unawaited(_terminateProcessTree(process));
    return true;
  }

  int cancelAll() {
    var count = 0;
    for (final id in _activeProcesses.keys.toList()) {
      if (cancel(id)) count++;
    }
    return count;
  }

  Map<String, String> _sanitizedEnvironment() {
    return ChildProcessEnvironment.build(baseEnvironment: _baseEnvironment);
  }

  List<String> _toolRoots() {
    final path = _sanitizedEnvironment()['PATH'];
    if (path == null || path.trim().isEmpty) return const [];
    return path
        .split(Platform.pathSeparator)
        .map((entry) => entry.trim())
        .where((entry) => entry.startsWith('/'))
        .toSet()
        .toList(growable: false);
  }

  /// Shell commands can create descendants that outlive the shell itself.
  /// Dart exposes a handle only for that root process, so cancellation first
  /// snapshots the descendant tree and signals leaves before the root. A
  /// second SIGKILL pass bounds stubborn children without ever invoking the
  /// user command parser or inheriting its environment.
  Future<void> _terminateProcessTree(Process process) async {
    final pids = await _processTree(process.pid);
    await _signalPids(pids, 'TERM');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final survivors = await _runningPids(pids);
    if (survivors.isNotEmpty) await _signalPids(survivors, 'KILL');
  }

  Future<List<int>> _processTree(int rootPid) async {
    try {
      final result = await Process.run('/bin/ps', const ['-axo', 'pid=,ppid=']);
      if (result.exitCode != 0) return [rootPid];
      final childrenByParent = <int, List<int>>{};
      for (final line in result.stdout.toString().split('\n')) {
        final values = line.trim().split(RegExp(r'\s+'));
        if (values.length != 2) continue;
        final pid = int.tryParse(values[0]);
        final parent = int.tryParse(values[1]);
        if (pid == null || parent == null) continue;
        childrenByParent.putIfAbsent(parent, () => []).add(pid);
      }
      final descendants = <int>[];
      void collect(int pid) {
        for (final child in childrenByParent[pid] ?? const <int>[]) {
          collect(child);
          descendants.add(child);
        }
      }

      collect(rootPid);
      return [...descendants, rootPid];
    } catch (_) {
      return [rootPid];
    }
  }

  Future<int?> _processGroupId(int pid) async {
    try {
      final result = await Process.run('/bin/ps', [
        '-o',
        'pgid=',
        '-p',
        '$pid',
      ]);
      return int.tryParse(result.stdout.toString().trim());
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _runningPids(List<int> pids) async {
    if (pids.isEmpty) return const [];
    try {
      final result = await Process.run('/bin/ps', [
        '-p',
        pids.join(','),
        '-o',
        'pid=',
      ]);
      if (result.exitCode != 0) return const [];
      return result.stdout
          .toString()
          .split('\n')
          .map((line) => int.tryParse(line.trim()))
          .whereType<int>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _signalPids(List<int> pids, String signal) async {
    if (pids.isEmpty) return;
    try {
      await Process.run('/bin/kill', [
        '-$signal',
        ...pids.map((pid) => '$pid'),
      ]);
    } catch (_) {
      // The process may have exited between discovery and signalling. That is
      // the desired outcome and should not turn a user cancellation into an
      // executor failure.
    }
  }
}
