import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notebook.dart';
import '../services/notebook_executor.dart';
import '../services/notebook_storage.dart';
import 'connection_provider.dart';
import 'file_tree_provider.dart';

class NotebookNotifier extends Notifier<NotebookState> {
  final NotebookExecutor _executor = NotebookExecutor();
  final NotebookStorage _storage = NotebookStorage();
  Timer? _saveDebounce;

  @override
  NotebookState build() => const NotebookState();

  String? get _projectRoot => ref.read(fileTreeProvider).rootPath;

  /// Load all notebooks from the project's storage directory.
  Future<void> loadNotebooks() async {
    final root = _projectRoot;
    if (root == null) return;

    state = state.copyWith(isLoading: true);
    final notebooks = await _storage.loadAll(root);
    state = state.copyWith(notebooks: notebooks, isLoading: false);
  }

  /// Create a new notebook with an optional name.
  Future<Notebook> createNotebook({String? name}) async {
    final notebook = Notebook(
      name: name ?? 'Untitled Notebook',
    );

    final newList = [notebook, ...state.notebooks];
    state = state.copyWith(
      notebooks: newList,
      activeNotebookId: notebook.id,
    );

    _saveNotebook(notebook);
    return notebook;
  }

  /// Delete a notebook by ID.
  Future<void> deleteNotebook(String id) async {
    final root = _projectRoot;
    if (root == null) return;

    final newList = state.notebooks.where((n) => n.id != id).toList();
    String? newActiveId = state.activeNotebookId;
    if (newActiveId == id) {
      newActiveId = newList.isNotEmpty ? newList.first.id : null;
    }

    state = state.copyWith(
      notebooks: newList,
      activeNotebookId: newActiveId,
    );

    await _storage.deleteNotebook(id, root);
  }

  /// Set the active notebook by ID.
  void setActiveNotebook(String id) {
    state = state.copyWith(activeNotebookId: id);
  }

  /// Add a new cell to the specified notebook.
  void addCell(String notebookId, {CellType type = CellType.code}) {
    _updateNotebook(notebookId, (notebook) {
      final newCell = NotebookCell(
        type: type,
        language: notebook.defaultLanguage,
      );
      return notebook.copyWith(
        cells: [...notebook.cells, newCell],
      );
    });
  }

  /// Update the source code of a cell (debounced auto-save).
  void updateCellSource(String notebookId, String cellId, String source) {
    _updateNotebook(notebookId, (notebook) {
      final cells = notebook.cells.map((c) {
        if (c.id == cellId) return c.copyWith(source: source);
        return c;
      }).toList();
      return notebook.copyWith(cells: cells);
    }, debounce: true);
  }

  /// Execute a single cell via the executor.
  Future<void> executeCell(String notebookId, String cellId) async {
    // Mark cell as running
    _updateNotebook(notebookId, (notebook) {
      final cells = notebook.cells.map((c) {
        if (c.id == cellId) return c.copyWith(status: CellStatus.running);
        return c;
      }).toList();
      return notebook.copyWith(cells: cells);
    }, save: false);

    // Find the cell
    final notebook = state.notebooks.firstWhere((n) => n.id == notebookId);
    final cell = notebook.cells.firstWhere((c) => c.id == cellId);

    // Execute
    final output = await _executor.execute(
      cell.source,
      cell.language,
      workingDir: _projectRoot,
    );

    // Update execution counter
    final newCounter = state.executionCounter + 1;

    // Update cell with results
    _updateNotebook(notebookId, (nb) {
      final cells = nb.cells.map((c) {
        if (c.id == cellId) {
          return c.copyWith(
            status: output.exitCode == 0 ? CellStatus.complete : CellStatus.error,
            output: output,
            executionOrder: newCounter,
            lastExecuted: DateTime.now(),
          );
        }
        return c;
      }).toList();
      return nb.copyWith(cells: cells);
    });

    state = state.copyWith(executionCounter: newCounter);
  }

  /// Use AI to generate code for a new cell from a natural language prompt.
  Future<void> generateCell(String notebookId, String prompt) async {
    final service = ref.read(agentServiceProvider);
    final notebook = state.notebooks.firstWhere((n) => n.id == notebookId);

    // Gather existing cell sources for context
    final existingCode = notebook.cells
        .where((c) => c.type == CellType.code && c.source.isNotEmpty)
        .map((c) => '```${c.language}\n${c.source}\n```')
        .join('\n\n');

    final systemPrompt =
        'You are a code assistant inside a notebook IDE. '
        'Generate ONLY executable code — no markdown fences, no explanations. '
        'Language: ${notebook.defaultLanguage}. '
        '${existingCode.isNotEmpty ? 'Existing notebook code for context:\n$existingCode' : ''}';

    final result = await service.sendOneShot(
      prompt,
      systemPrompt: systemPrompt,
    );

    if (result != null && result.isNotEmpty) {
      // Strip any markdown code fences the AI might have included
      final cleanedCode = _stripCodeFences(result);

      final newCell = NotebookCell(
        type: CellType.code,
        source: cleanedCode,
        language: notebook.defaultLanguage,
      );

      _updateNotebook(notebookId, (nb) {
        return nb.copyWith(cells: [...nb.cells, newCell]);
      });
    }
  }

  /// Use AI to explain a cell's code.
  Future<String?> explainCell(String notebookId, String cellId) async {
    final service = ref.read(agentServiceProvider);
    final notebook = state.notebooks.firstWhere((n) => n.id == notebookId);
    final cell = notebook.cells.firstWhere((c) => c.id == cellId);

    const systemPrompt =
        'You are a code assistant. Explain the following code clearly and '
        'concisely. Include what it does, key concepts, and any potential issues.';

    return await service.sendOneShot(
      'Explain this ${cell.language} code:\n\n${cell.source}',
      systemPrompt: systemPrompt,
    );
  }

  /// Run all code cells in order.
  Future<void> runAll(String notebookId) async {
    final notebook = state.notebooks.firstWhere((n) => n.id == notebookId);
    final codeCells =
        notebook.cells.where((c) => c.type == CellType.code).toList();

    for (final cell in codeCells) {
      await executeCell(notebookId, cell.id);
    }
  }

  /// Clear all cell outputs.
  void clearOutputs(String notebookId) {
    _updateNotebook(notebookId, (notebook) {
      final cells = notebook.cells.map((c) {
        return c.copyWith(
          status: CellStatus.idle,
          clearOutput: true,
          clearExecutionOrder: true,
        );
      }).toList();
      return notebook.copyWith(cells: cells);
    });
  }

  /// Delete a cell from a notebook.
  void deleteCell(String notebookId, String cellId) {
    _updateNotebook(notebookId, (notebook) {
      final cells = notebook.cells.where((c) => c.id != cellId).toList();
      // Keep at least one cell
      if (cells.isEmpty) {
        cells.add(NotebookCell(language: notebook.defaultLanguage));
      }
      return notebook.copyWith(cells: cells);
    });
  }

  /// Reorder cells via drag-and-drop.
  void reorderCells(String notebookId, int oldIndex, int newIndex) {
    _updateNotebook(notebookId, (notebook) {
      final cells = List<NotebookCell>.from(notebook.cells);
      if (newIndex > oldIndex) newIndex--;
      final cell = cells.removeAt(oldIndex);
      cells.insert(newIndex, cell);
      return notebook.copyWith(cells: cells);
    });
  }

  /// Toggle a cell's editing mode.
  void toggleCellEditing(String notebookId, String cellId) {
    _updateNotebook(notebookId, (notebook) {
      final cells = notebook.cells.map((c) {
        if (c.id == cellId) return c.copyWith(isEditing: !c.isEditing);
        return c;
      }).toList();
      return notebook.copyWith(cells: cells);
    }, save: false);
  }

  /// Update the default language for a notebook.
  void setDefaultLanguage(String notebookId, String language) {
    _updateNotebook(notebookId, (notebook) {
      return notebook.copyWith(defaultLanguage: language);
    });
  }

  /// Rename a notebook.
  void renameNotebook(String notebookId, String name) {
    _updateNotebook(notebookId, (notebook) {
      return notebook.copyWith(name: name);
    });
  }

  /// Change the language of a specific cell.
  void setCellLanguage(String notebookId, String cellId, String language) {
    _updateNotebook(notebookId, (notebook) {
      final cells = notebook.cells.map((c) {
        if (c.id == cellId) return c.copyWith(language: language);
        return c;
      }).toList();
      return notebook.copyWith(cells: cells);
    });
  }

  /// Toggle a cell between code and markdown.
  void toggleCellType(String notebookId, String cellId) {
    _updateNotebook(notebookId, (notebook) {
      final cells = notebook.cells.map((c) {
        if (c.id == cellId) {
          final newType =
              c.type == CellType.code ? CellType.markdown : CellType.code;
          return c.copyWith(type: newType);
        }
        return c;
      }).toList();
      return notebook.copyWith(cells: cells);
    });
  }

  // ── Private Helpers ──────────────────────────────────────────────────

  /// Update a notebook by ID using a transform function.
  void _updateNotebook(
    String notebookId,
    Notebook Function(Notebook) transform, {
    bool save = true,
    bool debounce = false,
  }) {
    final newNotebooks = state.notebooks.map((n) {
      if (n.id == notebookId) return transform(n);
      return n;
    }).toList();

    state = state.copyWith(notebooks: newNotebooks);

    if (save) {
      final updated = newNotebooks.firstWhere((n) => n.id == notebookId);
      if (debounce) {
        _debouncedSave(updated);
      } else {
        _saveNotebook(updated);
      }
    }
  }

  void _saveNotebook(Notebook notebook) {
    final root = _projectRoot;
    if (root == null) return;
    _storage.saveNotebook(notebook, root);
  }

  void _debouncedSave(Notebook notebook) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      _saveNotebook(notebook);
    });
  }

  /// Strip markdown code fences from AI-generated code.
  String _stripCodeFences(String text) {
    var result = text.trim();
    // Remove opening fence: ```language\n
    if (result.startsWith('```')) {
      final firstNewline = result.indexOf('\n');
      if (firstNewline != -1) {
        result = result.substring(firstNewline + 1);
      }
    }
    // Remove closing fence
    if (result.endsWith('```')) {
      result = result.substring(0, result.length - 3).trimRight();
    }
    return result;
  }
}

final notebookProvider =
    NotifierProvider<NotebookNotifier, NotebookState>(NotebookNotifier.new);
