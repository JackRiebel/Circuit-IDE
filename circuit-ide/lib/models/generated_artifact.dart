import 'dart:convert';

import 'studio_source_artifact.dart';

enum GeneratedArtifactKind {
  excel,
  csv,
  markdown,
  json,
  pdf,
  powerPoint,
  docx,
  diagram,
  chart,
  report,
}

enum GeneratedArtifactStatus { ready, fallback, failed }

class GeneratedArtifact {
  final String id;
  final GeneratedArtifactKind kind;
  final GeneratedArtifactStatus status;
  final String fileName;
  final String filePath;
  final String summary;
  final int byteSize;
  final List<List<String>> previewRows;
  final int sheetCount;
  final String? threadId;
  final String? requestId;
  final DateTime createdAt;

  const GeneratedArtifact({
    required this.id,
    required this.kind,
    required this.status,
    required this.fileName,
    required this.filePath,
    required this.summary,
    required this.byteSize,
    this.previewRows = const [],
    this.sheetCount = 0,
    this.threadId,
    this.requestId,
    required this.createdAt,
  });

  String get typeLabel {
    return switch (kind) {
      GeneratedArtifactKind.excel => 'Excel',
      GeneratedArtifactKind.csv => 'CSV',
      GeneratedArtifactKind.markdown => 'Markdown',
      GeneratedArtifactKind.json => 'JSON',
      GeneratedArtifactKind.pdf => 'PDF',
      GeneratedArtifactKind.powerPoint => 'PowerPoint',
      GeneratedArtifactKind.docx => 'Word',
      GeneratedArtifactKind.diagram => 'Diagram',
      GeneratedArtifactKind.chart => 'Chart',
      GeneratedArtifactKind.report => 'Report',
    };
  }

  String get statusLabel {
    return switch (status) {
      GeneratedArtifactStatus.ready => 'Ready',
      GeneratedArtifactStatus.fallback => 'Fallback',
      GeneratedArtifactStatus.failed => 'Failed',
    };
  }

  StudioSourceArtifact toSourceArtifact() {
    return StudioSourceArtifact(
      id: 'generated-$id',
      kind: StudioSourceArtifactKind.generatedArtifact,
      title: fileName,
      subtitle: '$typeLabel artifact • $statusLabel',
      value: jsonEncode(toJson()),
      threadId: threadId,
      requestId: requestId,
      filePath: filePath,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'status': status.name,
      'fileName': fileName,
      'filePath': filePath,
      'summary': summary,
      'byteSize': byteSize,
      'previewRows': previewRows,
      'sheetCount': sheetCount,
      'threadId': threadId,
      'requestId': requestId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static GeneratedArtifact? fromJson(Map<String, dynamic> json) {
    try {
      return GeneratedArtifact(
        id: json['id'] as String? ?? '',
        kind: GeneratedArtifactKind.values.firstWhere(
          (kind) => kind.name == json['kind'],
          orElse: () => GeneratedArtifactKind.report,
        ),
        status: GeneratedArtifactStatus.values.firstWhere(
          (status) => status.name == json['status'],
          orElse: () => GeneratedArtifactStatus.ready,
        ),
        fileName: json['fileName'] as String? ?? 'Generated artifact',
        filePath: json['filePath'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        byteSize: json['byteSize'] as int? ?? 0,
        previewRows: _previewRowsFromJson(json['previewRows']),
        sheetCount: json['sheetCount'] as int? ?? 0,
        threadId: json['threadId'] as String?,
        requestId: json['requestId'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static GeneratedArtifact? fromSourceArtifact(StudioSourceArtifact artifact) {
    if (artifact.kind != StudioSourceArtifactKind.generatedArtifact) {
      return null;
    }
    try {
      final decoded = jsonDecode(artifact.value);
      if (decoded is! Map<String, dynamic>) return null;
      return fromJson(decoded);
    } catch (_) {
      return GeneratedArtifact(
        id: artifact.id,
        kind: GeneratedArtifactKind.report,
        status: GeneratedArtifactStatus.ready,
        fileName: artifact.title,
        filePath: artifact.filePath ?? '',
        summary: artifact.subtitle,
        byteSize: artifact.value.length,
        previewRows: const [],
        sheetCount: 0,
        threadId: artifact.threadId,
        requestId: artifact.requestId,
        createdAt: artifact.createdAt,
      );
    }
  }

  static List<List<String>> _previewRowsFromJson(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<List>()
        .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
        .where((row) => row.isNotEmpty)
        .toList(growable: false);
  }
}

GeneratedArtifactKind? detectGeneratedArtifactKind(String text) {
  final normalized = text.toLowerCase();
  if (RegExp(
    r'\b(excel|xlsx|spreadsheet|workbook|sizing matrix|sizing model|solution sizing|product comparison matrix|comparison matrix|eox|eol|eos|ldos|last date of support|lifecycle (?:report|matrix|review|status)|replacement pid|migration pid)\b',
  ).hasMatch(normalized)) {
    return GeneratedArtifactKind.excel;
  }
  if (RegExp(r'\b(csv|comma[- ]separated)\b').hasMatch(normalized)) {
    return GeneratedArtifactKind.csv;
  }
  if (RegExp(r'\b(json)\b').hasMatch(normalized)) {
    return GeneratedArtifactKind.json;
  }
  if (RegExp(r'\b(pdf)\b').hasMatch(normalized)) {
    return GeneratedArtifactKind.pdf;
  }
  if (RegExp(
    r'\b(powerpoint|pptx|presentation|slide deck|deck|slides?)\b',
  ).hasMatch(normalized)) {
    return GeneratedArtifactKind.powerPoint;
  }
  if (RegExp(r'\b(docx|word document)\b').hasMatch(normalized)) {
    return GeneratedArtifactKind.docx;
  }
  if (RegExp(
    r'\b(evidence pack|citation pack|source pack|sources report|source report|evidence review|fact check|fact-check|source validation|claim validation|unsupported claims?|checked dates?|confidence notes?)\b',
  ).hasMatch(normalized)) {
    return GeneratedArtifactKind.docx;
  }
  if (RegExp(r'\b(diagram|mermaid|topology)\b').hasMatch(normalized)) {
    return GeneratedArtifactKind.diagram;
  }
  if (RegExp(
    r'\b(chart|charts|graph|graphs|visualization)\b',
  ).hasMatch(normalized)) {
    return GeneratedArtifactKind.chart;
  }
  if (RegExp(
    r'\b(business case|business use cases?|use case brief|company research brief|market research brief|industry research brief|executive brief|customer brief|account plan|sales play|value proposition|roi analysis|case study)\b',
  ).hasMatch(normalized)) {
    return GeneratedArtifactKind.docx;
  }
  if (RegExp(
    r'\b(markdown|md|readme|report|brief|document)\b',
  ).hasMatch(normalized)) {
    return GeneratedArtifactKind.markdown;
  }
  return null;
}

bool isGeneratedArtifactRequest(String text) {
  final normalized = text.toLowerCase();
  if (RegExp(
    r'\b(inline|in chat|chat only|without (?:writing|creating|saving) (?:a )?files?|without writing files|no files?|do not (?:write|create|save)|don.t write|don’t write)\b',
  ).hasMatch(normalized)) {
    return false;
  }
  if (detectGeneratedArtifactKind(normalized) == null) return false;
  return RegExp(
    r'\b(create|make|generate|build|export|save|write|turn|convert|put)\b',
  ).hasMatch(normalized);
}
