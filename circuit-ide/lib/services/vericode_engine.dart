import 'dart:io';

import '../core/utils/platform_utils.dart';
import '../models/vericoding_models.dart';

class VericodeEngine {
  final String workingDir;

  VericodeEngine({required this.workingDir});

  Future<VericodeResult> runCheck(VericodeCheck check) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = await Process.run(
        PlatformUtils.shell,
        [...PlatformUtils.shellArgs, check.command],
        workingDirectory: workingDir,
        environment: {...Platform.environment, 'TERM': 'dumb'},
      ).timeout(Duration(seconds: check.timeoutSeconds));

      stopwatch.stop();

      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();

      final output = StringBuffer();
      if (stdout.isNotEmpty) output.writeln(stdout);
      if (stderr.isNotEmpty) {
        if (output.isNotEmpty) output.writeln();
        output.writeln(stderr);
      }

      return VericodeResult(
        checkId: check.id,
        checkName: check.name,
        passed: result.exitCode == 0,
        output: output.toString().trim(),
        exitCode: result.exitCode,
        duration: stopwatch.elapsed,
      );
    } on ProcessException catch (e) {
      stopwatch.stop();
      return VericodeResult(
        checkId: check.id,
        checkName: check.name,
        passed: false,
        output: 'Process error: ${e.message}',
        exitCode: -1,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      final isTimeout = e.toString().contains('TimeoutException');
      return VericodeResult(
        checkId: check.id,
        checkName: check.name,
        passed: false,
        output: isTimeout
            ? 'Timed out after ${check.timeoutSeconds}s'
            : 'Error: $e',
        exitCode: -1,
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<List<VericodeResult>> runAllChecks(List<VericodeCheck> checks) async {
    final enabled = checks.where((c) => c.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final results = <VericodeResult>[];
    for (final check in enabled) {
      results.add(await runCheck(check));
    }
    return results;
  }

  String generateFixPrompt(
    List<VericodeResult> failures, {
    int attemptNumber = 1,
    int maxAttempts = 3,
  }) {
    final buffer = StringBuffer();
    if (attemptNumber > 1) {
      buffer.writeln(
        '[Vericoding] Fix attempt $attemptNumber of $maxAttempts — '
        'previous fix did not resolve all issues.\n',
      );
    }
    buffer.writeln(
      'The following verification checks failed. Please fix the issues:\n',
    );

    for (final failure in failures) {
      buffer.writeln(
        '--- ${failure.checkName} (exit code ${failure.exitCode}) ---',
      );
      // Truncate very long output
      final output = failure.output.length > 3000
          ? '${failure.output.substring(0, 3000)}\n... (truncated)'
          : failure.output;
      buffer.writeln(output);
      buffer.writeln();
    }

    buffer.writeln(
      'Fix all the issues above. Only modify the files that have errors.',
    );
    if (attemptNumber > 1) {
      buffer.writeln(
        'Be more careful this time — the previous fix attempt did not work.',
      );
    }
    return buffer.toString();
  }

  static List<VericodeCheck> defaultChecks() => [
    const VericodeCheck(
      id: '1',
      name: 'Dart Analyze',
      command: 'dart analyze',
      type: VericodeCheckType.dartAnalyze,
      enabled: true,
      order: 0,
      timeoutSeconds: 60,
    ),
    const VericodeCheck(
      id: '2',
      name: 'Flutter Test',
      command: 'flutter test',
      type: VericodeCheckType.flutterTest,
      enabled: false,
      order: 1,
      timeoutSeconds: 120,
    ),
    const VericodeCheck(
      id: '3',
      name: 'Format Check',
      command: 'dart format --set-exit-if-changed .',
      type: VericodeCheckType.flutterFormat,
      enabled: false,
      order: 2,
      timeoutSeconds: 30,
    ),
  ];
}
