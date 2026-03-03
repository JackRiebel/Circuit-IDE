import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class RuntimeVariable {
  final String name;
  final String type;
  final String value;
  final bool isModified;

  const RuntimeVariable({
    required this.name,
    required this.type,
    required this.value,
    this.isModified = false,
  });
}

class RuntimeFrame {
  final String id;
  final int frameNumber;
  final String functionName;
  final String filePath;
  final int lineNumber;
  final List<RuntimeVariable> variables;
  final bool isCurrent;
  final String? annotation;

  const RuntimeFrame({
    required this.id,
    required this.frameNumber,
    required this.functionName,
    required this.filePath,
    required this.lineNumber,
    this.variables = const [],
    this.isCurrent = false,
    this.annotation,
  });

  RuntimeFrame copyWith({bool? isCurrent}) => RuntimeFrame(
        id: id,
        frameNumber: frameNumber,
        functionName: functionName,
        filePath: filePath,
        lineNumber: lineNumber,
        variables: variables,
        isCurrent: isCurrent ?? this.isCurrent,
        annotation: annotation,
      );
}

class ExecutionTrace {
  final String id;
  final String entryPoint;
  final List<RuntimeFrame> frames;
  final int currentFrameIndex;
  final String? summary;

  ExecutionTrace({
    String? id,
    required this.entryPoint,
    required this.frames,
    this.currentFrameIndex = 0,
    this.summary,
  }) : id = id ?? _uuid.v4().substring(0, 8);

  ExecutionTrace copyWith({
    List<RuntimeFrame>? frames,
    int? currentFrameIndex,
  }) {
    return ExecutionTrace(
      id: id,
      entryPoint: entryPoint,
      frames: frames ?? this.frames,
      currentFrameIndex: currentFrameIndex ?? this.currentFrameIndex,
      summary: summary,
    );
  }

  RuntimeFrame? get currentFrame =>
      currentFrameIndex >= 0 && currentFrameIndex < frames.length
          ? frames[currentFrameIndex]
          : null;
}
