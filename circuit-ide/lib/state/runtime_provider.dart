import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/logger.dart';
import '../models/runtime_models.dart';
import 'connection_provider.dart';
import 'editor_provider.dart';

const _uuid = Uuid();

class RuntimeNotifier extends Notifier<ExecutionTrace?> {
  bool _analyzing = false;

  @override
  ExecutionTrace? build() => null;

  bool get isAnalyzing => _analyzing;

  Future<void> analyze(String filePath, {String? functionName}) async {
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) return;

    _analyzing = true;
    state = null; // Reset

    try {
      final file = File(filePath);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final funcSpec = functionName != null
          ? 'Focus on the function "$functionName".'
          : 'Analyze the main entry point or primary function.';

      final prompt =
          '''Analyze the following code and produce a simulated execution trace.
For each step in the execution, provide:
- The function name being executed
- The line number (approximate)
- Variables and their values at that point
- A brief annotation explaining what's happening

Format your response as a structured trace with this EXACT format for each frame:
FRAME:<number>|<function_name>|<line_number>|<annotation>
VAR:<name>|<type>|<value>|<modified: true/false>

$funcSpec

File: $filePath
```
$content
```

Produce 5-15 frames showing the execution flow. End with:
SUMMARY:<one line summary>''';

      final response = await service.sendOneShot(
        prompt,
        systemPrompt: _systemPrompt,
      );

      if (response == null || response.isEmpty) {
        _analyzing = false;
        return;
      }

      final trace = _parseTrace(response, filePath, functionName);
      state = trace;
      _analyzing = false;

      // Open runtime tab
      ref.read(editorProvider.notifier).openRuntimeTab(trace.id, filePath);

      Logger.info(
        'Runtime trace generated: ${trace.frames.length} frames',
        'Runtime',
      );
    } catch (e) {
      Logger.error('Runtime analysis failed', e);
      _analyzing = false;
    }
  }

  void stepForward() {
    if (state == null) return;
    final nextIndex = state!.currentFrameIndex + 1;
    if (nextIndex >= state!.frames.length) return;
    _setCurrentFrame(nextIndex);
  }

  void stepBackward() {
    if (state == null) return;
    final prevIndex = state!.currentFrameIndex - 1;
    if (prevIndex < 0) return;
    _setCurrentFrame(prevIndex);
  }

  void jumpToFrame(int index) {
    if (state == null) return;
    if (index < 0 || index >= state!.frames.length) return;
    _setCurrentFrame(index);
  }

  void _setCurrentFrame(int index) {
    final frames = state!.frames.asMap().entries.map((e) {
      return e.value.copyWith(isCurrent: e.key == index);
    }).toList();
    state = state!.copyWith(frames: frames, currentFrameIndex: index);
  }

  ExecutionTrace _parseTrace(
    String response,
    String filePath,
    String? functionName,
  ) {
    final frames = <RuntimeFrame>[];
    String? summary;
    List<RuntimeVariable> currentVars = [];
    int frameCount = 0;

    for (final line in response.split('\n')) {
      final trimmed = line.trim();

      if (trimmed.startsWith('FRAME:')) {
        // Save previous vars to previous frame
        if (frames.isNotEmpty && currentVars.isNotEmpty) {
          final last = frames.removeLast();
          frames.add(
            RuntimeFrame(
              id: last.id,
              frameNumber: last.frameNumber,
              functionName: last.functionName,
              filePath: last.filePath,
              lineNumber: last.lineNumber,
              variables: currentVars,
              isCurrent: last.isCurrent,
              annotation: last.annotation,
            ),
          );
        }
        currentVars = [];

        final parts = trimmed.substring(6).split('|');
        if (parts.length >= 4) {
          frames.add(
            RuntimeFrame(
              id: _uuid.v4().substring(0, 8),
              frameNumber: frameCount,
              functionName: parts[1].trim(),
              filePath: filePath,
              lineNumber: int.tryParse(parts[2].trim()) ?? 0,
              isCurrent: frameCount == 0,
              annotation: parts[3].trim(),
            ),
          );
          frameCount++;
        }
      } else if (trimmed.startsWith('VAR:')) {
        final parts = trimmed.substring(4).split('|');
        if (parts.length >= 3) {
          currentVars.add(
            RuntimeVariable(
              name: parts[0].trim(),
              type: parts[1].trim(),
              value: parts[2].trim(),
              isModified:
                  parts.length > 3 && parts[3].trim().toLowerCase() == 'true',
            ),
          );
        }
      } else if (trimmed.startsWith('SUMMARY:')) {
        summary = trimmed.substring(8).trim();
      }
    }

    // Attach last set of vars
    if (frames.isNotEmpty && currentVars.isNotEmpty) {
      final last = frames.removeLast();
      frames.add(
        RuntimeFrame(
          id: last.id,
          frameNumber: last.frameNumber,
          functionName: last.functionName,
          filePath: last.filePath,
          lineNumber: last.lineNumber,
          variables: currentVars,
          isCurrent: last.isCurrent,
          annotation: last.annotation,
        ),
      );
    }

    // If parsing failed, create a single informational frame
    if (frames.isEmpty) {
      frames.add(
        RuntimeFrame(
          id: _uuid.v4().substring(0, 8),
          frameNumber: 0,
          functionName: functionName ?? 'main',
          filePath: filePath,
          lineNumber: 1,
          isCurrent: true,
          annotation: response.length > 200
              ? response.substring(0, 200)
              : response,
        ),
      );
    }

    return ExecutionTrace(
      entryPoint: functionName ?? filePath.split('/').last,
      frames: frames,
      currentFrameIndex: 0,
      summary: summary,
    );
  }

  static const _systemPrompt = '''
You are a runtime execution analyzer. Given source code, simulate its execution and produce a structured trace showing the call flow, variable states, and annotations.

Output ONLY structured frames in the specified format. No extra commentary.
Be precise about line numbers and variable values.''';
}

final runtimeProvider = NotifierProvider<RuntimeNotifier, ExecutionTrace?>(
  RuntimeNotifier.new,
);
