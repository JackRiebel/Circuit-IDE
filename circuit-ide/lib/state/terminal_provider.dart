import 'dart:convert';
import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../core/utils/platform_utils.dart';

/// Strips ANSI escape codes from terminal output.
String _stripAnsi(String input) {
  return input.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '')
      .replaceAll(RegExp(r'\x1B\][^\x07]*\x07'), '') // OSC sequences
      .replaceAll(RegExp(r'\r'), '');
}

class TerminalInstance {
  final String id;
  final Terminal terminal;
  Pty? pty;

  /// Ring buffer of recent terminal output lines (ANSI-stripped).
  final List<String> outputBuffer = [];
  static const int maxBufferLines = 200;
  String _lineAccumulator = '';

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
    final start = outputBuffer.length > lines
        ? outputBuffer.length - lines
        : 0;
    return outputBuffer.sublist(start).join('\n');
  }
}

class TerminalState {
  final bool isVisible;
  final double height;
  final int activeTerminalIndex;
  final List<TerminalInstance> terminals;

  TerminalState({
    this.isVisible = false,
    this.height = 200,
    this.activeTerminalIndex = 0,
    List<TerminalInstance>? terminals,
  }) : terminals = terminals ??
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
  }) {
    return TerminalState(
      isVisible: isVisible ?? this.isVisible,
      height: height ?? this.height,
      activeTerminalIndex: activeTerminalIndex ?? this.activeTerminalIndex,
      terminals: terminals ?? this.terminals,
    );
  }
}

class TerminalNotifier extends Notifier<TerminalState> {
  int _nextId = 1;

  @override
  TerminalState build() => TerminalState();

  void toggle() {
    state = state.copyWith(isVisible: !state.isVisible);
  }

  void show() {
    state = state.copyWith(isVisible: true);
  }

  void hide() {
    state = state.copyWith(isVisible: false);
  }

  void setHeight(double height) {
    state = state.copyWith(height: height.clamp(100, 600));
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
        environment: {
          ...Platform.environment,
          'TERM': 'xterm-256color',
        },
      );

      instance.pty = pty;

      pty.output.listen((data) {
        final text = String.fromCharCodes(data);
        instance.terminal.write(text);
        instance.bufferOutput(text);
      });

      instance.terminal.onOutput = (data) {
        instance.pty?.write(const Utf8Encoder().convert(data));
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
    for (final instance in state.terminals) {
      instance.pty?.kill();
    }
  }
}

final terminalProvider =
    NotifierProvider<TerminalNotifier, TerminalState>(TerminalNotifier.new);
