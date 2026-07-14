import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'worker_cancellation.dart';
import 'office_package_relationship_inspector.dart';
import 'zip_package_integrity.dart';

class WorkbookArtifactInspection {
  final bool hasZipSignature;
  final bool hasValidZipContainer;
  final bool hasResolvablePackageRelationships;
  final bool hasWorkbookXml;
  final bool hasStylesXml;
  final bool hasCoreProperties;
  final bool generatedByCircuitCode;
  final bool hasFrozenHeaderPanes;
  final bool hasAutoFilters;
  final bool hasStyledHeaders;
  final bool hasColumnWidths;
  final List<String> sheetNames;
  final Map<String, int> rowCounts;
  final Map<String, List<String>> sheetText;

  const WorkbookArtifactInspection({
    required this.hasZipSignature,
    required this.hasValidZipContainer,
    required this.hasResolvablePackageRelationships,
    required this.hasWorkbookXml,
    required this.hasStylesXml,
    required this.hasCoreProperties,
    required this.generatedByCircuitCode,
    required this.hasFrozenHeaderPanes,
    required this.hasAutoFilters,
    required this.hasStyledHeaders,
    required this.hasColumnWidths,
    required this.sheetNames,
    required this.rowCounts,
    required this.sheetText,
  });

  bool get isStructurallyValid {
    return hasZipSignature &&
        hasValidZipContainer &&
        hasResolvablePackageRelationships &&
        hasWorkbookXml &&
        hasStylesXml &&
        hasCoreProperties &&
        generatedByCircuitCode &&
        sheetNames.isNotEmpty;
  }

  bool get hasEnterpriseWorkbookStructure {
    return isStructurallyValid &&
        hasFrozenHeaderPanes &&
        hasAutoFilters &&
        hasStyledHeaders &&
        hasColumnWidths;
  }

  Map<String, Object?> toMetadata() {
    final checks = <String, bool>{
      'ZIP package header': hasZipSignature,
      'ZIP central-directory integrity': hasValidZipContainer,
      'OOXML relationship targets': hasResolvablePackageRelationships,
      'xl/workbook.xml': hasWorkbookXml,
      'xl/styles.xml': hasStylesXml,
      'core properties': hasCoreProperties,
      'CircuitCode creator': generatedByCircuitCode,
      'frozen header panes': hasFrozenHeaderPanes,
      'auto filters': hasAutoFilters,
      'styled headers': hasStyledHeaders,
      'column widths': hasColumnWidths,
      'at least one worksheet': sheetNames.isNotEmpty,
    };
    final failedChecks = checks.entries
        .where((entry) => !entry.value)
        .map((entry) => entry.key)
        .toList(growable: false);
    return {
      'workbookInspectionVersion': '1.0',
      'workbookInspectionStatus': failedChecks.isEmpty
          ? 'Verified'
          : 'Needs review',
      'workbookStructuralValid': isStructurallyValid,
      'workbookEnterpriseStructure': hasEnterpriseWorkbookStructure,
      'workbookInspectionFailedChecks': failedChecks,
      'workbookInspectionFailedCheckCount': failedChecks.length,
      'workbookParsedSheetCount': sheetNames.length,
      'workbookZipContainerValid': hasValidZipContainer,
      'workbookRelationshipTargetsValid': hasResolvablePackageRelationships,
      'workbookParsedSheetNames': sheetNames,
      'workbookParsedRowCounts': rowCounts,
      'workbookHasFrozenHeaderPanes': hasFrozenHeaderPanes,
      'workbookHasAutoFilters': hasAutoFilters,
      'workbookHasStyledHeaders': hasStyledHeaders,
      'workbookHasColumnWidths': hasColumnWidths,
    };
  }

  bool hasSheets(Iterable<String> requiredSheets) {
    final normalized = sheetNames.map(_normalize).toSet();
    return requiredSheets.every(
      (sheet) => normalized.contains(_normalize(sheet)),
    );
  }

  bool sheetContains(String sheetName, String value) {
    final target = _normalize(sheetName);
    final expected = value.toLowerCase();
    for (final entry in sheetText.entries) {
      if (_normalize(entry.key) != target) continue;
      return entry.value.any((cell) => cell.toLowerCase().contains(expected));
    }
    return false;
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class WorkbookArtifactInspector {
  const WorkbookArtifactInspector();

  /// Parses a generated workbook away from the UI isolate before it is
  /// published. The result is metadata-only so it remains safe to transfer
  /// back to the caller and to persist with the artifact record.
  Future<Map<String, Object?>> inspectMetadataInWorker(
    List<int> bytes, {
    WorkerCancellationToken? cancellationToken,
  }) {
    return CancellableWorker.run<Map<String, Object?>>(
      entryPoint: _workbookInspectionWorkerEntry,
      arguments: {'bytes': bytes},
      cancellationToken: cancellationToken,
      decodeResult: _metadataFromWorkerResult,
    );
  }

  WorkbookArtifactInspection inspect(List<int> bytes) {
    final zipInspection = const ZipPackageInspector().inspect(bytes);
    final relationshipInspection = const OfficePackageRelationshipInspector()
        .inspect(zipInspection);
    final files = _readZipEntries(Uint8List.fromList(bytes));
    final workbookXml = _utf8(files['xl/workbook.xml']);
    final stylesXml = _utf8(files['xl/styles.xml']);
    final coreXml = _utf8(files['docProps/core.xml']);
    final appXml = _utf8(files['docProps/app.xml']);
    final sheetNames = _sheetNames(workbookXml);
    final sheetText = <String, List<String>>{};
    final rowCounts = <String, int>{};

    for (var i = 0; i < sheetNames.length; i++) {
      final sheetXml = _utf8(files['xl/worksheets/sheet${i + 1}.xml']);
      if (sheetXml == null) continue;
      final name = sheetNames[i];
      sheetText[name] = _cellText(sheetXml);
      rowCounts[name] = RegExp(r'<row\b').allMatches(sheetXml).length;
    }

    final worksheetXml = files.entries
        .where((entry) => entry.key.startsWith('xl/worksheets/sheet'))
        .map((entry) => _utf8(entry.value) ?? '')
        .join('\n');

    return WorkbookArtifactInspection(
      hasZipSignature: zipInspection.hasZipHeader,
      hasValidZipContainer: zipInspection.isStructurallyValid,
      hasResolvablePackageRelationships:
          relationshipInspection.hasResolvableInternalTargets,
      hasWorkbookXml: workbookXml != null && workbookXml.contains('<workbook'),
      hasStylesXml: stylesXml != null && stylesXml.contains('<styleSheet'),
      hasCoreProperties:
          coreXml != null && coreXml.contains('<cp:coreProperties'),
      generatedByCircuitCode:
          (coreXml?.contains('<dc:creator>CircuitCode</dc:creator>') ??
              false) ||
          (appXml?.contains('<Application>CircuitCode</Application>') ?? false),
      hasFrozenHeaderPanes:
          worksheetXml.contains('state="frozen"') &&
          worksheetXml.contains('topLeftCell="A2"'),
      hasAutoFilters: worksheetXml.contains('<autoFilter '),
      hasStyledHeaders:
          worksheetXml.contains('<c r="A1" t="inlineStr" s="1"') ||
          worksheetXml.contains('<c r="A1" s="1" t="inlineStr"'),
      hasColumnWidths:
          worksheetXml.contains('<cols>') &&
          worksheetXml.contains('customWidth="1"'),
      sheetNames: sheetNames,
      rowCounts: rowCounts,
      sheetText: sheetText,
    );
  }

  Map<String, Uint8List> _readZipEntries(Uint8List bytes) {
    final files = <String, Uint8List>{};
    var offset = 0;
    while (offset + 30 <= bytes.length) {
      final signature = _uint32(bytes, offset);
      if (signature == 0x02014b50 || signature == 0x06054b50) break;
      if (signature != 0x04034b50) break;
      final method = _uint16(bytes, offset + 8);
      final compressedSize = _uint32(bytes, offset + 18);
      final fileNameLength = _uint16(bytes, offset + 26);
      final extraLength = _uint16(bytes, offset + 28);
      final nameStart = offset + 30;
      final nameEnd = nameStart + fileNameLength;
      final dataStart = nameEnd + extraLength;
      final dataEnd = dataStart + compressedSize;
      if (nameEnd > bytes.length || dataEnd > bytes.length) break;
      final name = utf8.decode(bytes.sublist(nameStart, nameEnd));
      if (method == 0) {
        files[name] = Uint8List.fromList(bytes.sublist(dataStart, dataEnd));
      }
      offset = dataEnd;
    }
    return files;
  }

  int _uint16(Uint8List bytes, int offset) {
    return ByteData.sublistView(
      bytes,
      offset,
      offset + 2,
    ).getUint16(0, Endian.little);
  }

  int _uint32(Uint8List bytes, int offset) {
    return ByteData.sublistView(
      bytes,
      offset,
      offset + 4,
    ).getUint32(0, Endian.little);
  }

  String? _utf8(Uint8List? bytes) {
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  List<String> _sheetNames(String? workbookXml) {
    if (workbookXml == null) return const [];
    return RegExp(r'<sheet\b[^>]*\bname="([^"]+)"')
        .allMatches(workbookXml)
        .map((match) => _xmlDecode(match.group(1) ?? ''))
        .where((name) => name.trim().isNotEmpty)
        .toList(growable: false);
  }

  List<String> _cellText(String sheetXml) {
    final values = <String>[];
    for (final match in RegExp(r'<t>([\s\S]*?)</t>').allMatches(sheetXml)) {
      final value = _xmlDecode(match.group(1) ?? '').trim();
      if (value.isNotEmpty) values.add(value);
    }
    for (final match in RegExp(r'<v>([\s\S]*?)</v>').allMatches(sheetXml)) {
      final value = _xmlDecode(match.group(1) ?? '').trim();
      if (value.isNotEmpty) values.add(value);
    }
    return values;
  }

  String _xmlDecode(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
}

void _workbookInspectionWorkerEntry(Map<String, Object?> arguments) {
  final replyPort = arguments['replyPort'];
  if (replyPort is! SendPort) return;
  try {
    final bytes = arguments['bytes'];
    if (bytes is! List<int>) {
      throw StateError('Missing workbook bytes for inspection.');
    }
    replyPort.send({
      'result': const WorkbookArtifactInspector().inspect(bytes).toMetadata(),
    });
  } catch (error) {
    replyPort.send({'error': error.toString()});
  }
}

Map<String, Object?> _metadataFromWorkerResult(Object? result) {
  if (result is! Map) {
    throw StateError('Workbook inspector returned malformed metadata.');
  }
  return Map<String, Object?>.from(result);
}
