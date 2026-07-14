import 'dart:io';

/// Launch description for a policy-controlled child process.
class ExecutionBoundaryLaunch {
  final String executable;
  final List<String> arguments;
  final bool brokered;
  final String? denialMessage;

  const ExecutionBoundaryLaunch({
    required this.executable,
    required this.arguments,
    this.brokered = false,
    this.denialMessage,
  });

  /// A packaged release must not silently fall back to an unrestricted shell
  /// when its separately signed execution broker is missing or damaged.
  const ExecutionBoundaryLaunch.denied(String message)
    : executable = '',
      arguments = const [],
      brokered = false,
      denialMessage = message;

  bool get isDenied => denialMessage != null;
}

/// Applies OS-enforced restrictions that complement the Studio permission
/// policy. Release builds bundle a separately executable broker that owns the
/// workspace mount, private temporary directory, resource limits, and network
/// capability. Development/test environments that do not have that helper
/// retain macOS's no-network fallback for unapproved network access.
abstract final class MacOsExecutionBoundary {
  static const _sandboxExecutable = '/usr/bin/sandbox-exec';
  static const _noInternetProfile = 'no-internet';
  static const _brokerName = 'CircuitExecutionBroker';
  static const packagedBrokerUnavailableMessage =
      'Command execution is unavailable because the packaged execution boundary is missing.';
  // Keep this allowlist aligned with CircuitExecutionBroker.swift. PATH is
  // inherited discovery metadata, not a capability grant: an unrelated
  // runtime directory (for example a developer tool cache) must not make an
  // otherwise safe brokered command fail before the broker can run it.
  static const _trustedToolRootPrefixes = [
    '/bin',
    '/sbin',
    '/usr/bin',
    '/usr/sbin',
    '/usr/local',
    '/opt/homebrew',
    '/Library/Developer',
  ];

  /// Test-only override for a temporary bundled broker path.
  static String? debugBrokerExecutableOverride;

  /// Test-only override for the `Contents` directory of a packaged app.
  ///
  /// This is deliberately a directory, not an executable path, so tests can
  /// exercise the release-only missing-helper condition without ever allowing
  /// an absent helper to fall back to the developer shell.
  static String? debugPackagedContentsDirectoryOverride;

  static ExecutionBoundaryLaunch forShellCommand({
    required String shell,
    required List<String> shellArgs,
    required String command,
    required String workingDirectory,
    required int cpuLimitSeconds,
    required bool allowNetwork,
    List<String> toolRoots = const [],
  }) {
    final direct = ExecutionBoundaryLaunch(
      executable: shell,
      arguments: [...shellArgs, command],
    );
    if (!Platform.isMacOS) return direct;

    final contentsDirectory = _packagedContentsDirectory();
    final broker = _bundledBrokerExecutable(contentsDirectory);
    if (broker != null) {
      return ExecutionBoundaryLaunch(
        executable: broker,
        arguments: [
          '--workspace',
          workingDirectory,
          '--network',
          allowNetwork ? 'allow' : 'deny',
          '--cpu-limit',
          '$cpuLimitSeconds',
          for (final root in _reviewedToolRoots(toolRoots)) ...[
            '--tool-root',
            root,
          ],
          '--',
          shell,
          ...shellArgs,
          command,
        ],
        brokered: true,
      );
    }
    if (contentsDirectory != null) {
      return const ExecutionBoundaryLaunch.denied(
        packagedBrokerUnavailableMessage,
      );
    }
    if (allowNetwork || !File(_sandboxExecutable).existsSync()) {
      return direct;
    }
    return ExecutionBoundaryLaunch(
      executable: _sandboxExecutable,
      arguments: ['-n', _noInternetProfile, shell, ...shellArgs, command],
    );
  }

  static String? _bundledBrokerExecutable(Directory? contentsDirectory) {
    final override = debugBrokerExecutableOverride;
    if (override != null) {
      final overrideFile = File(override);
      if (overrideFile.existsSync()) return overrideFile.absolute.path;
    }
    if (contentsDirectory == null) return null;
    final candidate = File('${contentsDirectory.path}/Helpers/$_brokerName');
    return candidate.existsSync() ? candidate.path : null;
  }

  /// Returns a packaged app's `Contents` directory, never merely the parent
  /// of an arbitrary executable. Development, test, and command-line hosts
  /// retain their documented fallback behavior; a `.app` bundle does not.
  static Directory? _packagedContentsDirectory() {
    final override = debugPackagedContentsDirectoryOverride;
    if (override != null) return Directory(override).absolute;

    final executable = File(Platform.resolvedExecutable).absolute;
    final macOsDirectory = executable.parent;
    final contentsDirectory = macOsDirectory.parent;
    final appDirectory = contentsDirectory.parent;
    if (!macOsDirectory.path.endsWith('/Contents/MacOS') ||
        !contentsDirectory.path.endsWith('/Contents') ||
        !appDirectory.path.endsWith('.app')) {
      return null;
    }
    return contentsDirectory;
  }

  static Iterable<String> _reviewedToolRoots(Iterable<String> roots) sync* {
    final seen = <String>{};
    for (final candidate in roots) {
      final root = candidate.trim();
      final trusted = _trustedToolRootPrefixes.any(
        (prefix) => root == prefix || root.startsWith('$prefix/'),
      );
      if (trusted && seen.add(root)) yield root;
    }
  }
}
