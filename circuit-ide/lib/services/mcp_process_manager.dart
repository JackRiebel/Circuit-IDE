import 'dart:async';
import 'dart:io';

import '../agent/mcp/mcp_config.dart';
import '../agent/mcp/mcp_token_storage.dart';
import '../agent/security/child_process_environment.dart';
import '../core/utils/logger.dart';

enum McpProcessState { stopped, starting, running, error }

/// Manages the lifecycle of Python MCP server processes.
class McpProcessManager {
  final _processes = <String, Process>{};
  final _states = <String, McpProcessState>{};
  final _errors = <String, String>{};
  final _pids = <String, int>{};
  final _tokenStorage = McpTokenStorage();
  final Map<String, String> _baseEnvironment;

  final _stateController =
      StreamController<(String, McpProcessState)>.broadcast();

  McpProcessManager({Map<String, String>? baseEnvironment})
    : _baseEnvironment = baseEnvironment ?? Platform.environment;

  /// Stream of (serverName, newState) events for UI reactivity.
  Stream<(String, McpProcessState)> get stateChanges => _stateController.stream;

  McpProcessState stateOf(String name) =>
      _states[name] ?? McpProcessState.stopped;

  String? errorOf(String name) => _errors[name];

  int? pidOf(String name) => _pids[name];

  bool isRunning(String name) => _states[name] == McpProcessState.running;

  /// Start a Python MCP server process.
  Future<void> startServer(McpServerConfig config) async {
    if (config.scriptPath == null || config.scriptPath!.isEmpty) return;

    final name = config.name;
    if (_processes.containsKey(name)) {
      await stopServer(name);
    }
    _setState(name, McpProcessState.starting);

    try {
      // Load tokens from secure storage
      final tokens = await _tokenStorage.loadTokens(
        name,
        config.requiredEnvVars,
      );

      final env = ChildProcessEnvironment.build(
        baseEnvironment: _baseEnvironment,
        injected: tokens,
        fixed: {if (config.port != null) 'PORT': config.port.toString()},
      );

      final process = await Process.start('python3', [
        config.scriptPath!,
      ], environment: env);

      _processes[name] = process;
      _pids[name] = process.pid;
      _setState(name, McpProcessState.running);

      Logger.info(
        'Started MCP server $name (PID ${process.pid})',
        'McpProcessManager',
      );

      // Capture stdout
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        Logger.info(
          '[$name stdout] ${ChildProcessEnvironment.redactOutput(data, tokens.values)}',
          'McpProcessManager',
        );
      });

      // Capture stderr
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        Logger.warning(
          '[$name stderr] ${ChildProcessEnvironment.redactOutput(data, tokens.values)}',
          'McpProcessManager',
        );
      });

      // Listen for exit
      process.exitCode.then((code) {
        _processes.remove(name);
        _pids.remove(name);
        if (code != 0) {
          _errors[name] = 'Process exited with code $code';
          _setState(name, McpProcessState.error);
        } else {
          _errors.remove(name);
          _setState(name, McpProcessState.stopped);
        }
        Logger.info(
          'MCP server $name exited with code $code',
          'McpProcessManager',
        );
      });
    } catch (e) {
      _errors[name] = e.toString();
      _setState(name, McpProcessState.error);
      Logger.error('Failed to start MCP server $name', e);
    }
  }

  /// Stop a running server process. SIGTERM first, then SIGKILL after timeout.
  Future<void> stopServer(String name) async {
    final process = _processes[name];
    if (process == null) return;

    process.kill(ProcessSignal.sigterm);

    // Wait up to 3 seconds for graceful shutdown
    final exited = await process.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () => -1,
    );

    if (exited == -1) {
      process.kill(ProcessSignal.sigkill);
      Logger.warning('Force-killed MCP server $name', 'McpProcessManager');
    }

    _processes.remove(name);
    _pids.remove(name);
    _errors.remove(name);
    _setState(name, McpProcessState.stopped);
  }

  /// Stop all running server processes (for app shutdown).
  Future<void> stopAll() async {
    final names = _processes.keys.toList();
    await Future.wait(names.map(stopServer));
  }

  void _setState(String name, McpProcessState newState) {
    _states[name] = newState;
    if (_stateController.isClosed) return;
    _stateController.add((name, newState));
  }

  Future<void> dispose() async {
    await stopAll();
    if (!_stateController.isClosed) {
      await _stateController.close();
    }
  }
}
