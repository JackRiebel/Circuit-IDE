import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/generated_artifact.dart';
import 'generated_artifact_writer.dart';

class GeneratedArtifactExporter {
  final GeneratedArtifactWriter writer;

  const GeneratedArtifactExporter({
    this.writer = const GeneratedArtifactWriter(),
  });

  List<GeneratedArtifactKind> supportedTargets(GeneratedArtifact artifact) {
    final targets = switch (artifact.kind) {
      GeneratedArtifactKind.markdown || GeneratedArtifactKind.report => [
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.pdf,
        GeneratedArtifactKind.powerPoint,
      ],
      GeneratedArtifactKind.csv => [
        GeneratedArtifactKind.excel,
        GeneratedArtifactKind.markdown,
      ],
      GeneratedArtifactKind.json => [
        GeneratedArtifactKind.markdown,
        GeneratedArtifactKind.docx,
        GeneratedArtifactKind.pdf,
      ],
      GeneratedArtifactKind.diagram || GeneratedArtifactKind.chart => [
        GeneratedArtifactKind.powerPoint,
        GeneratedArtifactKind.markdown,
        GeneratedArtifactKind.pdf,
      ],
      GeneratedArtifactKind.excel ||
      GeneratedArtifactKind.docx ||
      GeneratedArtifactKind.pdf ||
      GeneratedArtifactKind.powerPoint => <GeneratedArtifactKind>[],
    };
    return targets
        .where((target) => target != artifact.kind)
        .toList(growable: false);
  }

  Future<GeneratedArtifact?> export({
    required GeneratedArtifact artifact,
    required GeneratedArtifactKind targetKind,
  }) async {
    if (!supportedTargets(artifact).contains(targetKind)) return null;
    final source = File(artifact.filePath);
    if (!await source.exists()) return null;
    final rootPath = _workspaceRootFor(artifact.filePath);
    final content = await _sourceContent(artifact);
    if (content.trim().isEmpty) return null;
    final prompt =
        'export ${artifact.fileName} as ${_kindPromptLabel(targetKind)}';
    return writer.writeStructuredArtifact(
      rootPath: rootPath,
      prompt: prompt,
      content: content,
      targetKind: targetKind,
      turnId: '${artifact.id}-export-${targetKind.name}',
      threadId: artifact.threadId,
      requestId: artifact.requestId,
    );
  }

  Future<String> _sourceContent(GeneratedArtifact artifact) async {
    final file = File(artifact.filePath);
    final text = await file.readAsString();
    return switch (artifact.kind) {
      GeneratedArtifactKind.csv => _csvToMarkdown(artifact.fileName, text),
      GeneratedArtifactKind.json => _jsonToMarkdown(artifact.fileName, text),
      GeneratedArtifactKind.diagram || GeneratedArtifactKind.chart =>
        '# ${artifact.fileName}\n\n${artifact.summary}\n\n```svg\n$text\n```',
      _ => text,
    };
  }

  String _workspaceRootFor(String filePath) {
    final normalized = p.normalize(filePath);
    final parts = p.split(normalized);
    final outputIndex = parts.lastIndexOf('outputs');
    if (outputIndex > 0) {
      return p.joinAll(parts.take(outputIndex));
    }
    return p.dirname(normalized);
  }

  String _csvToMarkdown(String fileName, String csv) {
    final rows = const LineSplitter()
        .convert(csv)
        .map(_parseCsvRow)
        .where((row) => row.isNotEmpty)
        .toList(growable: false);
    if (rows.isEmpty) return '# $fileName\n\n$csv';
    final width = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    final normalizedRows = [
      for (final row in rows)
        [for (var i = 0; i < width; i++) i < row.length ? row[i] : ''],
    ];
    final buffer = StringBuffer('# $fileName\n\n');
    buffer.writeln(
      '| ${normalizedRows.first.map(_markdownCell).join(' | ')} |',
    );
    buffer.writeln('| ${List.filled(width, '---').join(' | ')} |');
    for (final row in normalizedRows.skip(1)) {
      buffer.writeln('| ${row.map(_markdownCell).join(' | ')} |');
    }
    return buffer.toString();
  }

  List<String> _parseCsvRow(String line) {
    final cells = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
        continue;
      }
      if (char == ',' && !quoted) {
        cells.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    cells.add(buffer.toString().trim());
    if (!cells.any((cell) => cell.isNotEmpty)) return const [];
    return cells;
  }

  String _jsonToMarkdown(String fileName, String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      return '# $fileName\n\n```json\n$pretty\n```';
    } catch (_) {
      return '# $fileName\n\n```json\n$jsonText\n```';
    }
  }

  String _markdownCell(String value) {
    return value.replaceAll('|', '\\|').replaceAll('\n', ' ').trim();
  }

  String _kindPromptLabel(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel => 'Excel workbook',
      GeneratedArtifactKind.csv => 'CSV',
      GeneratedArtifactKind.markdown => 'Markdown report',
      GeneratedArtifactKind.json => 'JSON',
      GeneratedArtifactKind.pdf => 'PDF report',
      GeneratedArtifactKind.powerPoint => 'PowerPoint deck',
      GeneratedArtifactKind.docx => 'Word report',
      GeneratedArtifactKind.diagram => 'diagram',
      GeneratedArtifactKind.chart => 'chart',
      GeneratedArtifactKind.report => 'report',
    };
  }
}
