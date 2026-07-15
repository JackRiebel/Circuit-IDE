import 'dart:convert';
import 'dart:typed_data';

/// Validates the ZIP container boundary for generated Office artifacts.
///
/// The artifact writers emit uncompressed ZIP entries, so this validator also
/// verifies each stored entry's CRC-32 before an Office package is published.
/// Deflated third-party packages retain central-directory and local-entry
/// validation; their CRC is validated by the native Office consumer.
class ZipPackageInspection {
  final bool hasZipHeader;
  final bool hasEndOfCentralDirectory;
  final bool hasConsistentCentralDirectory;
  final bool hasValidatedEntries;
  final int entryCount;
  final List<String> entryNames;
  final Map<String, Uint8List> storedEntries;
  final List<String> failures;

  const ZipPackageInspection({
    required this.hasZipHeader,
    required this.hasEndOfCentralDirectory,
    required this.hasConsistentCentralDirectory,
    required this.hasValidatedEntries,
    required this.entryCount,
    required this.entryNames,
    required this.storedEntries,
    required this.failures,
  });

  bool get isStructurallyValid =>
      hasZipHeader &&
      hasEndOfCentralDirectory &&
      hasConsistentCentralDirectory &&
      hasValidatedEntries &&
      entryCount > 0 &&
      failures.isEmpty;
}

/// A deliberately bounded ZIP validator for untrusted or interrupted Office
/// package output. It does not decompress entries; it validates all package
/// offsets and names, then verifies CRC-32 for stored entries which Circuit
/// emits itself.
class ZipPackageInspector {
  const ZipPackageInspector();

  static const _localHeaderSignature = 0x04034b50;
  static const _centralDirectorySignature = 0x02014b50;
  static const _endOfCentralDirectorySignature = 0x06054b50;
  static const _endOfCentralDirectoryLength = 22;
  static const _maxZipCommentLength = 0xffff;

  ZipPackageInspection inspect(List<int> source) {
    final bytes = Uint8List.fromList(source);
    final failures = <String>[];
    final entryNames = <String>[];
    final storedEntries = <String, Uint8List>{};
    final hasZipHeader =
        _hasRange(bytes, 0, 4) && _uint32(bytes, 0) == _localHeaderSignature;
    if (!hasZipHeader) failures.add('ZIP package header is missing.');

    final endOffset = _findEndOfCentralDirectory(bytes);
    if (endOffset == null) {
      failures.add('ZIP end-of-central-directory record is missing.');
      return ZipPackageInspection(
        hasZipHeader: hasZipHeader,
        hasEndOfCentralDirectory: false,
        hasConsistentCentralDirectory: false,
        hasValidatedEntries: false,
        entryCount: 0,
        entryNames: entryNames,
        storedEntries: storedEntries,
        failures: failures,
      );
    }

    final commentLength = _uint16(bytes, endOffset + 20);
    if (endOffset + _endOfCentralDirectoryLength + commentLength !=
        bytes.length) {
      failures.add('ZIP end-of-central-directory comment is malformed.');
    }
    final diskNumber = _uint16(bytes, endOffset + 4);
    final centralDirectoryDisk = _uint16(bytes, endOffset + 6);
    final entriesOnDisk = _uint16(bytes, endOffset + 8);
    final entryCount = _uint16(bytes, endOffset + 10);
    final centralDirectorySize = _uint32(bytes, endOffset + 12);
    final centralDirectoryOffset = _uint32(bytes, endOffset + 16);
    if (diskNumber != 0 || centralDirectoryDisk != 0) {
      failures.add('Multi-disk ZIP packages are not supported.');
    }
    if (entriesOnDisk != entryCount || entryCount == 0) {
      failures.add('ZIP central-directory entry count is invalid.');
    }
    if (centralDirectoryOffset > endOffset ||
        centralDirectorySize > endOffset - centralDirectoryOffset) {
      failures.add('ZIP central-directory bounds are invalid.');
    }

    final centralDirectoryEnd = centralDirectoryOffset + centralDirectorySize;
    var centralOffset = centralDirectoryOffset;
    var entriesValid = failures.isEmpty;
    final seenNames = <String>{};
    if (entriesValid) {
      for (var index = 0; index < entryCount; index++) {
        if (!_hasRange(bytes, centralOffset, 46) ||
            centralOffset + 46 > centralDirectoryEnd ||
            _uint32(bytes, centralOffset) != _centralDirectorySignature) {
          failures.add('ZIP central-directory entry $index is malformed.');
          entriesValid = false;
          break;
        }
        final flags = _uint16(bytes, centralOffset + 8);
        final method = _uint16(bytes, centralOffset + 10);
        final crc = _uint32(bytes, centralOffset + 16);
        final compressedSize = _uint32(bytes, centralOffset + 20);
        final uncompressedSize = _uint32(bytes, centralOffset + 24);
        final nameLength = _uint16(bytes, centralOffset + 28);
        final extraLength = _uint16(bytes, centralOffset + 30);
        final entryCommentLength = _uint16(bytes, centralOffset + 32);
        final startDisk = _uint16(bytes, centralOffset + 34);
        final localOffset = _uint32(bytes, centralOffset + 42);
        final centralEntryEnd =
            centralOffset + 46 + nameLength + extraLength + entryCommentLength;
        if (startDisk != 0 ||
            centralEntryEnd > centralDirectoryEnd ||
            !_hasRange(bytes, centralOffset + 46, nameLength)) {
          failures.add(
            'ZIP central-directory entry $index has invalid bounds.',
          );
          entriesValid = false;
          break;
        }
        final name = _entryName(bytes, centralOffset + 46, nameLength);
        if (name == null ||
            name.isEmpty ||
            name.startsWith('/') ||
            name.contains('\\') ||
            name.split('/').contains('..') ||
            !seenNames.add(name)) {
          failures.add('ZIP entry $index has an unsafe or duplicate path.');
          entriesValid = false;
          break;
        }
        entryNames.add(name);
        if (!_validateLocalEntry(
          bytes: bytes,
          index: index,
          name: name,
          flags: flags,
          method: method,
          crc: crc,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          localOffset: localOffset,
          centralDirectoryOffset: centralDirectoryOffset,
          storedEntries: storedEntries,
          failures: failures,
        )) {
          entriesValid = false;
          break;
        }
        centralOffset = centralEntryEnd;
      }
      if (entriesValid && centralOffset != centralDirectoryEnd) {
        failures.add('ZIP central-directory size does not match its entries.');
        entriesValid = false;
      }
    }

    final centralDirectoryValid =
        failures.isEmpty && centralOffset == centralDirectoryEnd;
    return ZipPackageInspection(
      hasZipHeader: hasZipHeader,
      hasEndOfCentralDirectory: true,
      hasConsistentCentralDirectory: centralDirectoryValid,
      hasValidatedEntries: entriesValid && failures.isEmpty,
      entryCount: entryNames.length,
      entryNames: List.unmodifiable(entryNames),
      storedEntries: Map.unmodifiable(storedEntries),
      failures: List.unmodifiable(failures),
    );
  }

  bool _validateLocalEntry({
    required Uint8List bytes,
    required int index,
    required String name,
    required int flags,
    required int method,
    required int crc,
    required int compressedSize,
    required int uncompressedSize,
    required int localOffset,
    required int centralDirectoryOffset,
    required Map<String, Uint8List> storedEntries,
    required List<String> failures,
  }) {
    if (!_hasRange(bytes, localOffset, 30) ||
        localOffset >= centralDirectoryOffset ||
        _uint32(bytes, localOffset) != _localHeaderSignature) {
      failures.add('ZIP local entry $index is missing.');
      return false;
    }
    final localFlags = _uint16(bytes, localOffset + 6);
    final localMethod = _uint16(bytes, localOffset + 8);
    final localCrc = _uint32(bytes, localOffset + 14);
    final localCompressedSize = _uint32(bytes, localOffset + 18);
    final localUncompressedSize = _uint32(bytes, localOffset + 22);
    final localNameLength = _uint16(bytes, localOffset + 26);
    final localExtraLength = _uint16(bytes, localOffset + 28);
    final dataOffset = localOffset + 30 + localNameLength + localExtraLength;
    if (!_hasRange(bytes, localOffset + 30, localNameLength) ||
        dataOffset > centralDirectoryOffset ||
        dataOffset + compressedSize > centralDirectoryOffset ||
        localFlags != flags ||
        localMethod != method ||
        _entryName(bytes, localOffset + 30, localNameLength) != name) {
      failures.add(
        'ZIP local entry $index does not match the central directory.',
      );
      return false;
    }
    final usesDataDescriptor = flags & 0x0008 != 0;
    if (!usesDataDescriptor &&
        (localCrc != crc ||
            localCompressedSize != compressedSize ||
            localUncompressedSize != uncompressedSize)) {
      failures.add(
        'ZIP local entry $index size or CRC metadata is inconsistent.',
      );
      return false;
    }
    if (method == 0) {
      if (compressedSize != uncompressedSize ||
          _crc32(bytes.sublist(dataOffset, dataOffset + compressedSize)) !=
              crc) {
        failures.add('ZIP stored entry $index failed CRC validation.');
        return false;
      }
      storedEntries[name] = Uint8List.sublistView(
        bytes,
        dataOffset,
        dataOffset + compressedSize,
      );
    }
    return true;
  }

  int? _findEndOfCentralDirectory(Uint8List bytes) {
    final firstOffset =
        bytes.length > _maxZipCommentLength + _endOfCentralDirectoryLength
        ? bytes.length - _maxZipCommentLength - _endOfCentralDirectoryLength
        : 0;
    for (
      var offset = bytes.length - _endOfCentralDirectoryLength;
      offset >= firstOffset;
      offset--
    ) {
      if (_uint32(bytes, offset) == _endOfCentralDirectorySignature) {
        return offset;
      }
    }
    return null;
  }

  bool _hasRange(Uint8List bytes, int offset, int length) =>
      offset >= 0 && length >= 0 && offset <= bytes.length - length;

  String? _entryName(Uint8List bytes, int offset, int length) {
    try {
      return utf8.decode(bytes.sublist(offset, offset + length));
    } on FormatException {
      return null;
    }
  }

  int _uint16(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  int _uint32(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  int _crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}
