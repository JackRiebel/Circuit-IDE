import 'package:uuid/uuid.dart';

enum CellType { code, markdown }

enum CellStatus { idle, running, complete, error }

class CellOutput {
  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration executionTime;
  final String? errorMessage;

  const CellOutput({
    this.stdout = '',
    this.stderr = '',
    this.exitCode = 0,
    this.executionTime = Duration.zero,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
        'stdout': stdout,
        'stderr': stderr,
        'exitCode': exitCode,
        'executionTimeMs': executionTime.inMilliseconds,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  factory CellOutput.fromJson(Map<String, dynamic> json) => CellOutput(
        stdout: json['stdout'] ?? '',
        stderr: json['stderr'] ?? '',
        exitCode: json['exitCode'] ?? 0,
        executionTime: Duration(milliseconds: json['executionTimeMs'] ?? 0),
        errorMessage: json['errorMessage'],
      );
}

class NotebookCell {
  final String id;
  final CellType type;
  final String source;
  final String language;
  final CellStatus status;
  final CellOutput? output;
  final int? executionOrder;
  final DateTime? lastExecuted;
  final bool isEditing;

  NotebookCell({
    String? id,
    this.type = CellType.code,
    this.source = '',
    this.language = 'python',
    this.status = CellStatus.idle,
    this.output,
    this.executionOrder,
    this.lastExecuted,
    this.isEditing = true,
  }) : id = id ?? const Uuid().v4();

  NotebookCell copyWith({
    CellType? type,
    String? source,
    String? language,
    CellStatus? status,
    CellOutput? output,
    bool clearOutput = false,
    int? executionOrder,
    bool clearExecutionOrder = false,
    DateTime? lastExecuted,
    bool? isEditing,
  }) {
    return NotebookCell(
      id: id,
      type: type ?? this.type,
      source: source ?? this.source,
      language: language ?? this.language,
      status: status ?? this.status,
      output: clearOutput ? null : (output ?? this.output),
      executionOrder: clearExecutionOrder
          ? null
          : (executionOrder ?? this.executionOrder),
      lastExecuted: lastExecuted ?? this.lastExecuted,
      isEditing: isEditing ?? this.isEditing,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'source': source,
        'language': language,
        if (output != null) 'output': output!.toJson(),
        if (executionOrder != null) 'executionOrder': executionOrder,
        if (lastExecuted != null)
          'lastExecuted': lastExecuted!.toIso8601String(),
      };

  factory NotebookCell.fromJson(Map<String, dynamic> json) => NotebookCell(
        id: json['id'],
        type: CellType.values.byName(json['type'] ?? 'code'),
        source: json['source'] ?? '',
        language: json['language'] ?? 'python',
        output: json['output'] != null
            ? CellOutput.fromJson(json['output'])
            : null,
        executionOrder: json['executionOrder'],
        lastExecuted: json['lastExecuted'] != null
            ? DateTime.parse(json['lastExecuted'])
            : null,
      );
}

class Notebook {
  final String id;
  final String name;
  final String description;
  final List<NotebookCell> cells;
  final String defaultLanguage;
  final DateTime createdAt;
  final DateTime modifiedAt;

  Notebook({
    String? id,
    this.name = 'Untitled Notebook',
    this.description = '',
    List<NotebookCell>? cells,
    this.defaultLanguage = 'python',
    DateTime? createdAt,
    DateTime? modifiedAt,
  })  : id = id ?? const Uuid().v4(),
        cells = cells ?? [NotebookCell()],
        createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  Notebook copyWith({
    String? name,
    String? description,
    List<NotebookCell>? cells,
    String? defaultLanguage,
    DateTime? modifiedAt,
  }) {
    return Notebook(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      cells: cells ?? this.cells,
      defaultLanguage: defaultLanguage ?? this.defaultLanguage,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'cells': cells.map((c) => c.toJson()).toList(),
        'defaultLanguage': defaultLanguage,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
        id: json['id'],
        name: json['name'] ?? 'Untitled',
        description: json['description'] ?? '',
        cells: (json['cells'] as List?)
            ?.map((c) => NotebookCell.fromJson(c))
            .toList(),
        defaultLanguage: json['defaultLanguage'] ?? 'python',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : null,
        modifiedAt: json['modifiedAt'] != null
            ? DateTime.parse(json['modifiedAt'])
            : null,
      );
}

class NotebookState {
  final List<Notebook> notebooks;
  final String? activeNotebookId;
  final bool isLoading;
  final int executionCounter;

  const NotebookState({
    this.notebooks = const [],
    this.activeNotebookId,
    this.isLoading = false,
    this.executionCounter = 0,
  });

  NotebookState copyWith({
    List<Notebook>? notebooks,
    String? activeNotebookId,
    bool? isLoading,
    int? executionCounter,
  }) {
    return NotebookState(
      notebooks: notebooks ?? this.notebooks,
      activeNotebookId: activeNotebookId ?? this.activeNotebookId,
      isLoading: isLoading ?? this.isLoading,
      executionCounter: executionCounter ?? this.executionCounter,
    );
  }

  Notebook? get activeNotebook {
    if (activeNotebookId == null) return null;
    try {
      return notebooks.firstWhere((n) => n.id == activeNotebookId);
    } catch (_) {
      return null;
    }
  }
}
