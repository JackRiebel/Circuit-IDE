import 'dart:io';

import '../core/utils/platform_utils.dart';

class TerminalService {
  Process? _process;
  final String workingDir;

  TerminalService({required this.workingDir});

  Future<Process> startShell() async {
    _process = await Process.start(
      PlatformUtils.shell,
      [],
      workingDirectory: workingDir,
      environment: {...Platform.environment, 'TERM': 'xterm-256color'},
    );
    return _process!;
  }

  void write(String data) {
    _process?.stdin.write(data);
  }

  void kill() {
    _process?.kill();
    _process = null;
  }

  bool get isRunning => _process != null;
}
