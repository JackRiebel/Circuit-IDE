import 'dart:io';

class PlatformUtils {
  static bool get isMacOS => Platform.isMacOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isLinux => Platform.isLinux;

  static String get homeDir {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
    }
    return Platform.environment['HOME'] ?? '/tmp';
  }

  static String get configDir {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      return '$appData\\CircuitIDE';
    }
    return '$homeDir/.config/circuit-ide';
  }

  static String get shell {
    if (Platform.isWindows) {
      return Platform.environment['COMSPEC'] ?? 'cmd.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/bash';
  }

  static List<String> get shellArgs {
    if (Platform.isWindows) return ['/c'];
    return ['-c'];
  }

  static String get pathSeparator => Platform.pathSeparator;

  static String get modifierKey => isMacOS ? 'Cmd' : 'Ctrl';

  /// A safe scratch workspace for when no project folder is open.
  /// Lives inside the app's config dir so it never triggers macOS TCC prompts.
  static String get scratchDir => '$configDir/workspace';

  static Future<String> ensureScratchDir() async {
    final dir = Directory(scratchDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return scratchDir;
  }
}
