import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/utils/platform_utils.dart';
import '../security/command_sanitizer.dart';

class CommandTools {
  final String workingDir;

  CommandTools({required this.workingDir});

  Future<String> runCommand(Map<String, dynamic> args) async {
    final command = args['command'] as String;
    final timeout = (args['timeout'] as int?)
            ?.clamp(AppConstants.commandTimeoutMin, AppConstants.commandTimeoutMax) ??
        AppConstants.commandTimeoutDefault;

    // Check for dangerous commands
    final danger = CommandSanitizer.checkDangerous(command);
    if (danger != null) {
      return 'Error: Potentially dangerous command blocked: $danger';
    }

    try {
      final result = await Process.run(
        PlatformUtils.shell,
        [...PlatformUtils.shellArgs, command],
        workingDirectory: workingDir,
        environment: {
          ...Platform.environment,
          'TERM': 'dumb',
        },
      ).timeout(Duration(seconds: timeout));

      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();

      final output = StringBuffer();
      if (stdout.isNotEmpty) output.writeln(stdout);
      if (stderr.isNotEmpty) {
        if (output.isNotEmpty) output.writeln();
        output.writeln('[stderr] $stderr');
      }

      if (result.exitCode != 0) {
        output.writeln('\n[exit code: ${result.exitCode}]');
      }

      final text = output.toString().trim();
      // Truncate very long output
      if (text.length > 50000) {
        return '${text.substring(0, 25000)}\n\n... (output truncated, ${text.length} chars total) ...\n\n${text.substring(text.length - 5000)}';
      }
      return text.isEmpty ? '(no output)' : text;
    } on ProcessException catch (e) {
      return 'Error executing command: ${e.message}';
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        return 'Error: Command timed out after ${timeout}s';
      }
      return 'Error: $e';
    }
  }
}
