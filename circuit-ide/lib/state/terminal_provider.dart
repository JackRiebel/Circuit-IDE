import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

import '../core/constants/design_tokens.dart';
import '../core/utils/platform_utils.dart';

/// Strips ANSI escape codes from terminal output.
String _stripAnsi(String input) {
  return input
      .replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '')
      .replaceAll(RegExp(r'\x1B\][^\x07]*\x07'), '') // OSC sequences
      .replaceAll(RegExp(r'\r'), '');
}

class TerminalInstance {
  final String id;
  final Terminal terminal;
  Pty? pty;

  /// Ring buffer of recent terminal output lines (ANSI-stripped).
  final List<String> outputBuffer = [];
  final List<String> commandHistory = [];
  static const int maxBufferLines = 200;
  static const int maxCommandHistory = 50;
  String _lineAccumulator = '';
  String _inputAccumulator = '';
  String? lastCommand;
  String? lastErrorLine;
  bool hasRecentError = false;

  TerminalInstance({required this.id, required this.terminal, this.pty});

  /// Feed raw output into the buffer for AI analysis.
  void bufferOutput(String raw) {
    final stripped = _stripAnsi(raw);
    _lineAccumulator += stripped;

    // Split on newlines and buffer complete lines
    final parts = _lineAccumulator.split('\n');
    if (parts.length > 1) {
      // All but last are complete lines
      for (int i = 0; i < parts.length - 1; i++) {
        final line = parts[i].trimRight();
        if (line.isNotEmpty) {
          outputBuffer.add(line);
          if (_looksLikeError(line)) {
            hasRecentError = true;
            lastErrorLine = line;
          }
        }
      }
      _lineAccumulator = parts.last;

      // Trim buffer
      while (outputBuffer.length > maxBufferLines) {
        outputBuffer.removeAt(0);
      }
    }
  }

  /// Get the last N lines of output for AI analysis.
  String getRecentOutput({int lines = 50}) {
    final start = outputBuffer.length > lines ? outputBuffer.length - lines : 0;
    return outputBuffer.sublist(start).join('\n');
  }

  void bufferInput(String data) {
    for (final codeUnit in data.codeUnits) {
      if (codeUnit == 13 || codeUnit == 10) {
        final command = _inputAccumulator.trim();
        _inputAccumulator = '';
        if (command.isNotEmpty) {
          lastCommand = command;
          commandHistory.add(command);
          hasRecentError = false;
          lastErrorLine = null;
          while (commandHistory.length > maxCommandHistory) {
            commandHistory.removeAt(0);
          }
        }
      } else if (codeUnit == 8 || codeUnit == 127) {
        if (_inputAccumulator.isNotEmpty) {
          _inputAccumulator = _inputAccumulator.substring(
            0,
            _inputAccumulator.length - 1,
          );
        }
      } else if (codeUnit >= 32) {
        _inputAccumulator += String.fromCharCode(codeUnit);
      }
    }
  }

  static bool _looksLikeError(String line) {
    final lower = line.toLowerCase();
    return lower.contains('error') ||
        lower.contains('exception') ||
        lower.contains('failed') ||
        lower.contains('fatal') ||
        lower.contains('traceback') ||
        lower.contains('command not found') ||
        lower.contains('permission denied') ||
        lower.contains('no such file') ||
        lower.contains('segmentation fault');
  }
}

class _TerminalStorage {
  static String get _filePath =>
      p.join(PlatformUtils.configDir, 'terminal_session.json');

  static Future<Map<String, dynamic>> read() async {
    try {
      final file = File(_filePath);
      if (!await file.exists()) return {};
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> write(Map<String, dynamic> patch) async {
    try {
      final dir = Directory(PlatformUtils.configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final existing = await read();
      existing.addAll(patch);
      await File(
        _filePath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(existing));
    } catch (_) {}
  }
}

class TerminalState {
  final bool isVisible;
  final double height;
  final int activeTerminalIndex;
  final List<TerminalInstance> terminals;
  final int outputRevision;

  TerminalState({
    this.isVisible = false,
    this.height = 200,
    this.activeTerminalIndex = 0,
    this.outputRevision = 0,
    List<TerminalInstance>? terminals,
  }) : terminals =
           terminals ??
           [
             TerminalInstance(
               id: 'term-0',
               terminal: Terminal(maxLines: 10000),
             ),
           ];

  TerminalState copyWith({
    bool? isVisible,
    double? height,
    int? activeTerminalIndex,
    List<TerminalInstance>? terminals,
    int? outputRevision,
  }) {
    return TerminalState(
      isVisible: isVisible ?? this.isVisible,
      height: height ?? this.height,
      activeTerminalIndex: activeTerminalIndex ?? this.activeTerminalIndex,
      terminals: terminals ?? this.terminals,
      outputRevision: outputRevision ?? this.outputRevision,
    );
  }
}

class TerminalNotifier extends Notifier<TerminalState> {
  int _nextId = 1;
  Timer? _outputNotifyTimer;

  @override
  TerminalState build() {
    ref.onDispose(() => _outputNotifyTimer?.cancel());
    unawaited(_loadSession());
    return TerminalState();
  }

  Future<void> _loadSession() async {
    final data = await _TerminalStorage.read();
    if (!ref.mounted) return;
    final visible = data['terminal_visible'];
    final height = (data['terminal_height'] as num?)?.toDouble();
    state = state.copyWith(
      isVisible: visible is bool ? visible : null,
      height: height?.clamp(
        LayoutDimensions.terminalMinHeight,
        LayoutDimensions.terminalMaxHeight,
      ),
    );
  }

  void toggle() {
    state = state.copyWith(isVisible: !state.isVisible);
    unawaited(_TerminalStorage.write({'terminal_visible': state.isVisible}));
  }

  void show() {
    state = state.copyWith(isVisible: true);
    unawaited(_TerminalStorage.write({'terminal_visible': true}));
  }

  void hide() {
    state = state.copyWith(isVisible: false);
    unawaited(_TerminalStorage.write({'terminal_visible': false}));
  }

  void setHeight(double height) {
    final clamped = height.clamp(
      LayoutDimensions.terminalMinHeight,
      LayoutDimensions.terminalMaxHeight,
    );
    state = state.copyWith(height: clamped);
    unawaited(_TerminalStorage.write({'terminal_height': clamped}));
  }

  void addTerminal() {
    final instance = TerminalInstance(
      id: 'term-${_nextId++}',
      terminal: Terminal(maxLines: 10000),
    );
    final newTerminals = [...state.terminals, instance];
    state = state.copyWith(
      terminals: newTerminals,
      activeTerminalIndex: newTerminals.length - 1,
    );
  }

  void setActiveTerminal(int index) {
    if (index >= 0 && index < state.terminals.length) {
      state = state.copyWith(activeTerminalIndex: index);
    }
  }

  void removeTerminal(int index) {
    if (state.terminals.length <= 1) return;
    final instance = state.terminals[index];
    instance.pty?.kill();

    final newTerminals = List<TerminalInstance>.from(state.terminals)
      ..removeAt(index);
    int newActive = state.activeTerminalIndex;
    if (newActive >= newTerminals.length) {
      newActive = newTerminals.length - 1;
    }
    state = state.copyWith(
      terminals: newTerminals,
      activeTerminalIndex: newActive,
    );
  }

  void initializePty(int index, String workingDir) {
    if (index < 0 || index >= state.terminals.length) return;
    final instance = state.terminals[index];
    if (instance.pty != null) return; // already initialized

    try {
      final pty = Pty.start(
        PlatformUtils.shell,
        columns: 80,
        rows: 24,
        workingDirectory: workingDir,
        environment: {...Platform.environment, 'TERM': 'xterm-256color'},
      );

      instance.pty = pty;

      pty.output.listen((data) {
        final text = String.fromCharCodes(data);
        instance.terminal.write(text);
        instance.bufferOutput(text);
        _scheduleOutputNotification();
      });

      instance.terminal.onOutput = (data) {
        instance.bufferInput(data);
        instance.pty?.write(const Utf8Encoder().convert(data));
        _scheduleOutputNotification();
      };

      instance.terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        instance.pty?.resize(height, width);
      };

      pty.exitCode.then((_) {
        instance.terminal.write('\r\n[Process exited]\r\n');
      });
    } catch (e) {
      instance.terminal.write('Failed to start shell: $e\r\n');
    }
  }

  /// Get recent output from the active terminal for AI fix.
  String getActiveTerminalOutput({int lines = 50}) {
    if (state.terminals.isEmpty) return '';
    final instance = state.terminals[state.activeTerminalIndex];
    return instance.getRecentOutput(lines: lines);
  }

  void disposeAll() {
    _outputNotifyTimer?.cancel();
    for (final instance in state.terminals) {
      instance.pty?.kill();
    }
  }

  void _scheduleOutputNotification() {
    if (_outputNotifyTimer?.isActive ?? false) return;
    _outputNotifyTimer = Timer(const Duration(milliseconds: 250), () {
      state = state.copyWith(outputRevision: state.outputRevision + 1);
    });
  }
}

final terminalProvider = NotifierProvider<TerminalNotifier, TerminalState>(
  TerminalNotifier.new,
);
