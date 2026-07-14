import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A typed durable JSON envelope. Records written before envelopes existed are
/// treated as version 1 and can be migrated by their owning store.
class VersionedJsonDocument {
  static const schemaVersionKey = 'schemaVersion';
  static const kindKey = 'kind';
  static const payloadKey = 'payload';
  static const checksumKey = 'checksum';

  final String kind;
  final int schemaVersion;
  final Object? payload;
  final String? checksum;
  final bool isLegacy;

  const VersionedJsonDocument({
    required this.kind,
    required this.schemaVersion,
    required this.payload,
    this.checksum,
    this.isLegacy = false,
  });

  /// New records include a digest of their payload. Older envelopes without a
  /// digest remain readable, so this does not require a destructive migration.
  Map<String, dynamic> toJson() {
    final payloadChecksum = checksum ?? checksumFor(payload);
    return {
      schemaVersionKey: schemaVersion,
      kindKey: kind,
      payloadKey: payload,
      checksumKey: payloadChecksum,
    };
  }

  String encode({bool pretty = false}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  static VersionedJsonDocument decode(
    Object? decoded, {
    required String expectedKind,
    required int currentSchemaVersion,
    int legacySchemaVersion = 1,
  }) {
    if (decoded is Map<String, dynamic> &&
        decoded.containsKey(schemaVersionKey)) {
      final schemaVersion = decoded[schemaVersionKey];
      if (schemaVersion is! int || schemaVersion < 1) {
        throw const FormatException(
          'The saved record has an invalid schema version.',
        );
      }
      if (schemaVersion > currentSchemaVersion) {
        throw UnsupportedRuntimeSchemaVersion(
          kind: expectedKind,
          foundVersion: schemaVersion,
          supportedVersion: currentSchemaVersion,
        );
      }
      if (decoded[kindKey] != expectedKind) {
        throw FormatException(
          'Expected a $expectedKind record but found ${decoded[kindKey] ?? 'an unknown'} record.',
        );
      }
      if (!decoded.containsKey(payloadKey)) {
        throw const FormatException('The saved record is missing its payload.');
      }
      final checksum = decoded[checksumKey];
      if (checksum != null) {
        if (checksum is! String ||
            checksum != checksumFor(decoded[payloadKey])) {
          throw const FormatException(
            'The saved record failed its integrity check and may be corrupt.',
          );
        }
      }
      return VersionedJsonDocument(
        kind: expectedKind,
        schemaVersion: schemaVersion,
        payload: decoded[payloadKey],
        checksum: checksum as String?,
      );
    }

    return VersionedJsonDocument(
      kind: expectedKind,
      schemaVersion: legacySchemaVersion,
      payload: decoded,
      isLegacy: true,
    );
  }

  static String checksumFor(Object? payload) =>
      sha256.convert(utf8.encode(jsonEncode(payload))).toString();
}

class UnsupportedRuntimeSchemaVersion implements Exception {
  final String kind;
  final int foundVersion;
  final int supportedVersion;

  const UnsupportedRuntimeSchemaVersion({
    required this.kind,
    required this.foundVersion,
    required this.supportedVersion,
  });

  @override
  String toString() =>
      'This $kind record uses schema $foundVersion, but this version of CircuitCode supports schema $supportedVersion. Your data was left unchanged; update CircuitCode or restore a compatible backup.';
}

/// Creates a one-time backup of the exact source bytes, then atomically writes
/// the migrated document. A failed migration always leaves the original file
/// and its backup available for recovery.
Future<void> migrateVersionedJsonFile({
  required File file,
  required String originalContents,
  required String migratedContents,
  required int previousSchemaVersion,
}) async {
  if (!await file.parent.exists()) await file.parent.create(recursive: true);
  final backup = File('${file.path}.schema-v$previousSchemaVersion.backup');
  if (!await backup.exists()) {
    await backup.writeAsString(originalContents, flush: true);
  }
  await writeVersionedJsonAtomically(file, migratedContents);
}

Future<void> writeVersionedJsonAtomically(File file, String contents) async {
  if (!await file.parent.exists()) await file.parent.create(recursive: true);
  final staged = File(
    '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-$pid',
  );
  try {
    await staged.writeAsString(contents, flush: true);
    await staged.rename(file.path);
  } finally {
    if (await staged.exists()) await staged.delete();
  }
}
