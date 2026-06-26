import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/utils/platform_utils.dart';
import '../../models/command_run.dart';
import '../security/command_sanitizer.dart';

typedef CommandRunEventCallback = void Function(CommandRunEvent event);

class CommandTools {
  final String workingDir;
  final Map<String, String> _baseEnvironment;
  final Map<String, Process> _activeProcesses = {};

  CommandTools({required this.workingDir, Map<String, String>? environment})
    : _baseEnvironment = environment ?? Platform.environment;

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
      onEvent?.call(
        CommandRunEvent(
          type: CommandRunEventType.started,
          timestamp: DateTime.now(),
          text: command,
        ),
      );
      process = await Process.start(
        PlatformUtils.shell,
        [...PlatformUtils.shellArgs, command],
        workingDirectory: workingDir,
        environment: _sanitizedEnvironment(),
      );
      if (runId != null) _activeProcesses[runId] = process;

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final completer = Completer<int>();
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              stdoutBuffer.write(chunk);
              onEvent?.call(
                CommandRunEvent(
                  type: CommandRunEventType.stdout,
                  timestamp: DateTime.now(),
                  text: chunk,
                ),
              );
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
              stderrBuffer.write(chunk);
              onEvent?.call(
                CommandRunEvent(
                  type: CommandRunEventType.stderr,
                  timestamp: DateTime.now(),
                  text: chunk,
                ),
              );
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
        process?.kill(ProcessSignal.sigterm);
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
    } on ProcessException catch (e) {
      if (runId != null) _activeProcesses.remove(runId);
      return 'Error executing command: ${e.message}';
    } on TimeoutException {
      if (runId != null) _activeProcesses.remove(runId);
      return 'Error: Command timed out after ${timeout}s';
    } catch (e) {
      if (runId != null) _activeProcesses.remove(runId);
      return 'Error: $e';
    } finally {
      timer?.cancel();
    }
  }

  bool cancel(String runId) {
    final process = _activeProcesses.remove(runId);
    return process?.kill(ProcessSignal.sigterm) ?? false;
  }

  int cancelAll() {
    var count = 0;
    for (final id in _activeProcesses.keys.toList()) {
      if (cancel(id)) count++;
    }
    return count;
  }

  Map<String, String> _sanitizedEnvironment() {
    final env = <String, String>{};
    for (final entry in _baseEnvironment.entries) {
      final key = entry.key;
      if (_isBlockedEnvironmentKey(key)) continue;
      if (_isAllowedEnvironmentKey(key)) {
        env[key] = entry.value;
      }
    }
    env['TERM'] = 'dumb';
    return env;
  }

  bool _isAllowedEnvironmentKey(String key) {
    final upper = key.toUpperCase();
    if (upper.startsWith('LC_')) return true;
    return const {
      'ANDROID_HOME',
      'ANDROID_SDK_ROOT',
      'CI',
      'DART_SDK',
      'DEVELOPER_DIR',
      'FLUTTER_ROOT',
      'GEM_HOME',
      'GEM_PATH',
      'GRADLE_USER_HOME',
      'HOME',
      'JAVA_HOME',
      'LANG',
      'LOGNAME',
      'NPM_CONFIG_CACHE',
      'PATH',
      'PUB_CACHE',
      'PWD',
      'SDKROOT',
      'SHELL',
      'TERM',
      'TMP',
      'TMPDIR',
      'TEMP',
      'USER',
      'XCODE_DEVELOPER_DIR_PATH',
    }.contains(upper);
  }

  bool _isBlockedEnvironmentKey(String key) {
    final upper = key.toUpperCase();
    return RegExp(
      r'(TOKEN|SECRET|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|COOKIE|SESSION|AUTH|API[_-]?KEY|ACCESS[_-]?KEY|CLIENT[_-]?SECRET|SSH_AUTH_SOCK)',
    ).hasMatch(upper);
  }
}
