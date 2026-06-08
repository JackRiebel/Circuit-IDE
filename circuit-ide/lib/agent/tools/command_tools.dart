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

  CommandTools({required this.workingDir});

  Future<String> runCommand(
    Map<String, dynamic> args, {
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
        environment: {...Platform.environment, 'TERM': 'dumb'},
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final completer = Completer<int>();

      final stdoutSub = process.stdout.transform(utf8.decoder).listen((chunk) {
        stdoutBuffer.write(chunk);
        onEvent?.call(
          CommandRunEvent(
            type: CommandRunEventType.stdout,
            timestamp: DateTime.now(),
            text: chunk,
          ),
        );
      });
      final stderrSub = process.stderr.transform(utf8.decoder).listen((chunk) {
        stderrBuffer.write(chunk);
        onEvent?.call(
          CommandRunEvent(
            type: CommandRunEventType.stderr,
            timestamp: DateTime.now(),
            text: chunk,
          ),
        );
      });

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
      timer.cancel();
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
      return 'Error executing command: ${e.message}';
    } on TimeoutException {
      return 'Error: Command timed out after ${timeout}s';
    } catch (e) {
      return 'Error: $e';
    } finally {
      timer?.cancel();
    }
  }
}
