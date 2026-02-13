import 'dart:async';
import 'dart:io';

import '../core/utils/logger.dart';
import '../models/notebook.dart';

/// Executes notebook cell code in a subprocess and captures output.
class NotebookExecutor {
  Process? _activeProcess;

  /// Map of language to file extension
  static const _extensions = {
    'python': '.py',
    'dart': '.dart',
    'javascript': '.js',
    'typescript': '.ts',
    'bash': '.sh',
    'shell': '.sh',
    'ruby': '.rb',
    'go': '.go',
    'rust': '.rs',
  };

  /// Map of language to interpreter command
  static const _interpreters = {
    'python': ['python3'],
    'dart': ['dart', 'run'],
    'javascript': ['node'],
    'typescript': ['npx', 'ts-node'],
    'bash': ['bash'],
    'shell': ['bash'],
    'ruby': ['ruby'],
    'go': ['go', 'run'],
    'rust': ['rustc', '--edition', '2021', '-o'],
  };

  /// Execute a cell's source code and return the output.
  Future<CellOutput> execute(
    String source,
    String language, {
    String? workingDir,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final stopwatch = Stopwatch()..start();
    File? tempFile;

    try {
      // Determine file extension
      final ext = _extensions[language] ?? '.txt';
      final dir = Directory.systemTemp;
      tempFile = File(
        '${dir.path}/circuit_notebook_${DateTime.now().millisecondsSinceEpoch}$ext',
      );

      // Write source to temp file
      await tempFile.writeAsString(source);

      // Build command
      final command = _buildCommand(language, tempFile.path);
      if (command == null) {
        stopwatch.stop();
        return CellOutput(
          stderr: 'Unsupported language: $language',
          exitCode: 1,
          executionTime: stopwatch.elapsed,
          errorMessage: 'No interpreter configured for "$language"',
        );
      }

      // Start process
      _activeProcess = await Process.start(
        command.first,
        command.sublist(1),
        workingDirectory: workingDir,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      // Collect stdout and stderr
      final stdoutDone = _activeProcess!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((data) => stdoutBuffer.write(data))
          .asFuture<void>();

      final stderrDone = _activeProcess!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((data) => stderrBuffer.write(data))
          .asFuture<void>();

      // Wait for exit with timeout
      final exitCode = await _activeProcess!.exitCode.timeout(
        timeout,
        onTimeout: () {
          _activeProcess?.kill(ProcessSignal.sigterm);
          // Give it a moment to terminate gracefully
          Future.delayed(const Duration(seconds: 2), () {
            _activeProcess?.kill(ProcessSignal.sigkill);
          });
          return -1;
        },
      );

      // Wait for streams to flush
      await Future.wait([
        stdoutDone.catchError((_) {}),
        stderrDone.catchError((_) {}),
      ]);

      stopwatch.stop();
      _activeProcess = null;

      final isTimeout = exitCode == -1;
      return CellOutput(
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        exitCode: exitCode,
        executionTime: stopwatch.elapsed,
        errorMessage: isTimeout
            ? 'Execution timed out after ${timeout.inSeconds}s'
            : (exitCode != 0 ? 'Process exited with code $exitCode' : null),
      );
    } catch (e) {
      stopwatch.stop();
      Logger.error('NotebookExecutor.execute failed', e.toString());
      return CellOutput(
        stderr: e.toString(),
        exitCode: 1,
        executionTime: stopwatch.elapsed,
        errorMessage: 'Execution error: $e',
      );
    } finally {
      // Cleanup temp file
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Build the command list for executing the given language.
  List<String>? _buildCommand(String language, String filePath) {
    // Special handling for Rust: compile then run
    if (language == 'rust') {
      final outPath = filePath.replaceAll('.rs', '');
      return ['rustc', '--edition', '2021', '-o', outPath, filePath];
    }

    final interpreter = _interpreters[language];
    if (interpreter == null) return null;

    return [...interpreter, filePath];
  }

  /// Cancel the currently running process.
  void cancel() {
    _activeProcess?.kill(ProcessSignal.sigterm);
    _activeProcess = null;
  }

  /// Check if a process is currently running.
  bool get isRunning => _activeProcess != null;
}
