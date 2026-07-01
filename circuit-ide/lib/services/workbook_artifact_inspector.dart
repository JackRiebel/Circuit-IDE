import 'dart:convert';
import 'dart:typed_data';

class WorkbookArtifactInspection {
  final bool hasZipSignature;
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

  WorkbookArtifactInspection inspect(List<int> bytes) {
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
      hasZipSignature:
          bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4b &&
          bytes[2] == 0x03 &&
          bytes[3] == 0x04,
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
