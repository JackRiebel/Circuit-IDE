import '../core/utils/file_utils.dart';
import '../models/semantic_search_models.dart';

/// Regex-based heuristic code chunker that splits source files into
/// logical chunks (functions, classes, methods, etc.) without requiring
/// an AST parser dependency.
class CodeChunker {
  /// Main entry point: chunk a file into logical code segments.
  List<CodeChunk> chunkFile(
    String filePath,
    String content,
    String language,
  ) {
    if (content.trim().isEmpty) return [];

    final lang = language.isEmpty
        ? FileUtils.getLanguageFromPath(filePath)
        : language;

    final lines = content.split('\n');

    return switch (lang) {
      'dart' => _chunkDart(filePath, lines, lang),
      'python' => _chunkPython(filePath, lines, lang),
      'javascript' || 'typescript' => _chunkJsTs(filePath, lines, lang),
      _ => _chunkGeneric(filePath, lines, lang),
    };
  }

  /// Detect language from file extension.
  String detectLanguage(String filePath) {
    return FileUtils.getLanguageFromPath(filePath);
  }

  // ---------------------------------------------------------------------------
  // Dart chunking
  // ---------------------------------------------------------------------------

  static final _dartClassPattern =
      RegExp(r'^(abstract\s+)?(class|mixin|enum|extension)\s+(\w+)');
  static final _dartTopLevelFuncPattern =
      RegExp(r'^(\w[\w<>, ?]*)\s+(\w+)\s*[\(<]');
  static final _dartImportPattern = RegExp(r"^import\s+'");

  List<CodeChunk> _chunkDart(
    String filePath,
    List<String> lines,
    String language,
  ) {
    final chunks = <CodeChunk>[];
    int i = 0;

    // Collect imports block
    final importStart = i;
    while (i < lines.length &&
        (lines[i].trimLeft().startsWith('import ') ||
            lines[i].trimLeft().startsWith('export ') ||
            lines[i].trimLeft().startsWith('part ') ||
            lines[i].trimLeft().startsWith('library ') ||
            lines[i].trim().isEmpty ||
            lines[i].trimLeft().startsWith('//'))) {
      i++;
    }
    if (i > importStart && _hasImports(lines, importStart, i)) {
      chunks.add(_makeChunk(
        filePath, lines, importStart, i - 1,
        ChunkType.imports, 'imports', language,
      ));
    }

    // Parse declarations
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trimLeft();

      // Skip blank lines
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Class / mixin / enum / extension
      final classMatch = _dartClassPattern.firstMatch(trimmed);
      if (classMatch != null) {
        final name = classMatch.group(3) ?? 'unknown';
        final end = _findBraceBlockEnd(lines, i);
        chunks.add(_makeChunk(
          filePath, lines, i, end,
          ChunkType.classDecl, name, language,
        ));
        i = end + 1;
        continue;
      }

      // Top-level function (not indented)
      if (!line.startsWith(' ') &&
          !line.startsWith('\t') &&
          _dartTopLevelFuncPattern.hasMatch(trimmed) &&
          !trimmed.startsWith('//')) {
        final funcMatch = _dartTopLevelFuncPattern.firstMatch(trimmed);
        final name = funcMatch?.group(2) ?? 'function';
        final end = _findBraceBlockEnd(lines, i);
        chunks.add(_makeChunk(
          filePath, lines, i, end,
          ChunkType.function, name, language,
        ));
        i = end + 1;
        continue;
      }

      // Annotations or comments before a declaration — skip ahead
      if (trimmed.startsWith('@') || trimmed.startsWith('///')) {
        i++;
        continue;
      }

      i++;
    }

    // If nothing was chunked, fall back to generic
    if (chunks.isEmpty) {
      return _chunkGeneric(filePath, lines, language);
    }

    return chunks;
  }

  bool _hasImports(List<String> lines, int start, int end) {
    for (int i = start; i < end; i++) {
      if (_dartImportPattern.hasMatch(lines[i].trimLeft())) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Python chunking
  // ---------------------------------------------------------------------------

  static final _pyClassPattern = RegExp(r'^class\s+(\w+)');
  static final _pyFuncPattern = RegExp(r'^(async\s+)?def\s+(\w+)');
  static final _pyImportPattern = RegExp(r'^(import |from )');

  List<CodeChunk> _chunkPython(
    String filePath,
    List<String> lines,
    String language,
  ) {
    final chunks = <CodeChunk>[];
    int i = 0;

    // Collect imports block
    final importStart = i;
    while (i < lines.length &&
        (_pyImportPattern.hasMatch(lines[i].trimLeft()) ||
            lines[i].trim().isEmpty ||
            lines[i].trimLeft().startsWith('#'))) {
      i++;
    }
    if (i > importStart && i > 1) {
      chunks.add(_makeChunk(
        filePath, lines, importStart, i - 1,
        ChunkType.imports, 'imports', language,
      ));
    }

    // Parse declarations
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      final indent = line.length - trimmed.length;

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Top-level class
      if (indent == 0 && _pyClassPattern.hasMatch(trimmed)) {
        final name =
            _pyClassPattern.firstMatch(trimmed)?.group(1) ?? 'class';
        final end = _findIndentBlockEnd(lines, i);
        chunks.add(_makeChunk(
          filePath, lines, i, end,
          ChunkType.classDecl, name, language,
        ));
        i = end + 1;
        continue;
      }

      // Top-level function / async def
      if (indent == 0 && _pyFuncPattern.hasMatch(trimmed)) {
        final name =
            _pyFuncPattern.firstMatch(trimmed)?.group(2) ?? 'function';
        final end = _findIndentBlockEnd(lines, i);
        chunks.add(_makeChunk(
          filePath, lines, i, end,
          ChunkType.function, name, language,
        ));
        i = end + 1;
        continue;
      }

      i++;
    }

    if (chunks.isEmpty) {
      return _chunkGeneric(filePath, lines, language);
    }

    return chunks;
  }

  // ---------------------------------------------------------------------------
  // JavaScript / TypeScript chunking
  // ---------------------------------------------------------------------------

  static final _jsClassPattern = RegExp(r'^\s*(export\s+)?(default\s+)?class\s+(\w+)');
  static final _jsFuncPattern =
      RegExp(r'^\s*(export\s+)?(default\s+)?(async\s+)?function\s+(\w+)');
  static final _jsArrowPattern =
      RegExp(r'^\s*(export\s+)?(const|let|var)\s+(\w+)\s*=\s*(async\s+)?\(');
  static final _jsImportPattern = RegExp(r'^\s*(import |export |require\()');

  List<CodeChunk> _chunkJsTs(
    String filePath,
    List<String> lines,
    String language,
  ) {
    final chunks = <CodeChunk>[];
    int i = 0;

    // Collect imports block
    final importStart = i;
    while (i < lines.length &&
        (_jsImportPattern.hasMatch(lines[i]) ||
            lines[i].trim().isEmpty ||
            lines[i].trimLeft().startsWith('//'))) {
      i++;
    }
    if (i > importStart && i > 1) {
      chunks.add(_makeChunk(
        filePath, lines, importStart, i - 1,
        ChunkType.imports, 'imports', language,
      ));
    }

    // Parse declarations
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trimLeft();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Class
      final classMatch = _jsClassPattern.firstMatch(line);
      if (classMatch != null) {
        final name = classMatch.group(3) ?? 'class';
        final end = _findBraceBlockEnd(lines, i);
        chunks.add(_makeChunk(
          filePath, lines, i, end,
          ChunkType.classDecl, name, language,
        ));
        i = end + 1;
        continue;
      }

      // Named function
      final funcMatch = _jsFuncPattern.firstMatch(line);
      if (funcMatch != null) {
        final name = funcMatch.group(4) ?? 'function';
        final end = _findBraceBlockEnd(lines, i);
        chunks.add(_makeChunk(
          filePath, lines, i, end,
          ChunkType.function, name, language,
        ));
        i = end + 1;
        continue;
      }

      // Arrow function assigned to const/let/var
      final arrowMatch = _jsArrowPattern.firstMatch(line);
      if (arrowMatch != null) {
        final name = arrowMatch.group(3) ?? 'arrow';
        final end = _findBraceBlockEnd(lines, i);
        chunks.add(_makeChunk(
          filePath, lines, i, end,
          ChunkType.function, name, language,
        ));
        i = end + 1;
        continue;
      }

      i++;
    }

    if (chunks.isEmpty) {
      return _chunkGeneric(filePath, lines, language);
    }

    return chunks;
  }

  // ---------------------------------------------------------------------------
  // Generic chunking — blank-line-delimited blocks, max ~50 lines
  // ---------------------------------------------------------------------------

  List<CodeChunk> _chunkGeneric(
    String filePath,
    List<String> lines,
    String language,
  ) {
    final chunks = <CodeChunk>[];
    int blockStart = 0;
    int consecutiveBlanks = 0;
    const maxChunkLines = 50;

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) {
        consecutiveBlanks++;
      } else {
        consecutiveBlanks = 0;
      }

      final blockLen = i - blockStart + 1;

      // Split on double blank line or max chunk size
      if (consecutiveBlanks >= 2 || blockLen >= maxChunkLines) {
        if (i > blockStart) {
          // Trim trailing blank lines from this chunk
          int end = i;
          while (end > blockStart && lines[end].trim().isEmpty) {
            end--;
          }
          if (end >= blockStart) {
            chunks.add(_makeChunk(
              filePath, lines, blockStart, end,
              ChunkType.block, 'block_${blockStart + 1}', language,
            ));
          }
        }
        blockStart = i + 1;
        consecutiveBlanks = 0;
      }
    }

    // Final block
    if (blockStart < lines.length) {
      int end = lines.length - 1;
      while (end > blockStart && lines[end].trim().isEmpty) {
        end--;
      }
      if (end >= blockStart) {
        chunks.add(_makeChunk(
          filePath, lines, blockStart, end,
          ChunkType.block, 'block_${blockStart + 1}', language,
        ));
      }
    }

    return chunks;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Find the end of a brace-delimited block starting at [startLine].
  int _findBraceBlockEnd(List<String> lines, int startLine) {
    int braceCount = 0;
    bool foundOpen = false;

    for (int i = startLine; i < lines.length; i++) {
      for (final ch in lines[i].runes) {
        if (ch == 0x7B /* { */) {
          braceCount++;
          foundOpen = true;
        } else if (ch == 0x7D /* } */) {
          braceCount--;
        }
      }
      if (foundOpen && braceCount <= 0) return i;
    }

    // If no matching brace, return up to 50 lines or end
    return (startLine + 50).clamp(startLine, lines.length - 1);
  }

  /// Find the end of an indentation-based block (Python).
  int _findIndentBlockEnd(List<String> lines, int startLine) {
    if (startLine >= lines.length - 1) return startLine;

    // The block body must be more indented than the definition line
    final defIndent = _getIndent(lines[startLine]);
    int end = startLine;

    for (int i = startLine + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        end = i;
        continue;
      }
      final indent = _getIndent(line);
      if (indent <= defIndent) break;
      end = i;
    }

    return end;
  }

  int _getIndent(String line) {
    int indent = 0;
    for (final ch in line.runes) {
      if (ch == 0x20) {
        indent++;
      } else if (ch == 0x09) {
        indent += 4;
      } else {
        break;
      }
    }
    return indent;
  }

  CodeChunk _makeChunk(
    String filePath,
    List<String> lines,
    int startLine,
    int endLine,
    ChunkType type,
    String name,
    String language,
  ) {
    final clampedEnd = endLine.clamp(startLine, lines.length - 1);
    final content = lines
        .sublist(startLine, clampedEnd + 1)
        .join('\n');

    return CodeChunk(
      id: '$filePath:${startLine + 1}',
      filePath: filePath,
      startLine: startLine + 1, // 1-indexed
      endLine: clampedEnd + 1,
      type: type,
      name: name,
      content: content,
      language: language,
    );
  }
}
