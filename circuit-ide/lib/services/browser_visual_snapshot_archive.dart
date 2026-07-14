import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/studio_browser.dart';

typedef BrowserVisualSnapshotRootResolver = Future<Directory> Function();

/// A durable, local-only archive for a browser visual snapshot the user has
/// explicitly chosen to keep with a task.
///
/// This service never captures a page, performs OCR, or creates model context.
/// Its only input is the already-bounded, visible PNG held in the browser's
/// session state after a user-confirmed save action.
class BrowserVisualSnapshotArchive {
  static const _directoryName = 'browser-visual-snapshots';

  final BrowserVisualSnapshotRootResolver _rootResolver;

  BrowserVisualSnapshotArchive({
    required BrowserVisualSnapshotRootResolver rootResolver,
  }) : _rootResolver = rootResolver;

  factory BrowserVisualSnapshotArchive.platform() {
    return BrowserVisualSnapshotArchive(
      rootResolver: getApplicationSupportDirectory,
    );
  }

  Future<BrowserVisualSnapshotArchiveRecord> save({
    required String taskId,
    required String url,
    required DateTime capturedAt,
    required Uint8List pngBytes,
  }) async {
    _validatePng(pngBytes);
    final provenanceUrl = browserProvenanceUrl(url);
    if (provenanceUrl == null) {
      throw ArgumentError.value(url, 'url', 'Expected a safe browser URL.');
    }
    final directory = await _archiveDirectory();
    final digest = sha256.convert(pngBytes).toString();
    // Avoid exposing the task identifier in a Finder-visible path.
    final taskKey = sha256
        .convert(utf8.encode(taskId))
        .toString()
        .substring(0, 16);
    final timestamp = capturedAt.toUtc().microsecondsSinceEpoch;
    final target = File(
      p.join(
        directory.path,
        'browser-$taskKey-$timestamp-${digest.substring(0, 16)}.png',
      ),
    );

    final existingType = await FileSystemEntity.type(
      target.path,
      followLinks: false,
    );
    if (existingType == FileSystemEntityType.link ||
        existingType == FileSystemEntityType.directory) {
      throw StateError(
        'Browser snapshot archive target is not a regular file.',
      );
    }
    if (existingType == FileSystemEntityType.notFound) {
      final staging = File('${target.path}.${_randomSuffix()}.staging');
      try {
        await staging.writeAsBytes(pngBytes, flush: true);
        // The staging file lives beside the target, so this is an atomic
        // replacement on the local filesystem. A collision represents the
        // same task/capture/content and can safely reuse the existing copy.
        try {
          await staging.rename(target.path);
        } on FileSystemException {
          if (await FileSystemEntity.type(target.path, followLinks: false) ==
              FileSystemEntityType.notFound) {
            rethrow;
          }
          if (await staging.exists()) await staging.delete();
        }
      } catch (_) {
        if (await staging.exists()) await staging.delete();
        rethrow;
      }
    }
    await _verifyExistingSnapshot(
      target,
      expectedDigest: digest,
      expectedByteSize: pngBytes.lengthInBytes,
    );

    return BrowserVisualSnapshotArchiveRecord(
      filePath: target.path,
      sha256: digest,
      byteSize: pngBytes.lengthInBytes,
      url: provenanceUrl,
      capturedAt: capturedAt,
    );
  }

  Future<bool> delete(String filePath) async {
    final directory = await _archiveDirectory();
    final rootPath = p.normalize(p.absolute(directory.path));
    final candidatePath = p.normalize(p.absolute(filePath));
    if (!p.isWithin(rootPath, candidatePath)) return false;

    final file = File(candidatePath);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    // A prior task cleanup may already have removed this file. Treat that as
    // successful deletion so its stale task provenance can still be cleared.
    if (type == FileSystemEntityType.notFound) return true;
    if (type != FileSystemEntityType.file) {
      return false;
    }
    await file.delete();
    return true;
  }

  Future<Directory> _archiveDirectory() async {
    final root = await _rootResolver();
    await root.create(recursive: true);
    final canonicalRoot = Directory(await root.resolveSymbolicLinks());
    final requestedDirectory = Directory(
      p.join(canonicalRoot.path, _directoryName),
    );
    final type = await FileSystemEntity.type(
      requestedDirectory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      await requestedDirectory.create();
    } else if (type != FileSystemEntityType.directory) {
      throw StateError('Browser snapshot archive directory is not safe.');
    }
    final canonicalDirectory = Directory(
      await requestedDirectory.resolveSymbolicLinks(),
    );
    if (!p.isWithin(canonicalRoot.path, canonicalDirectory.path)) {
      throw StateError('Browser snapshot archive escapes private app storage.');
    }
    return canonicalDirectory;
  }

  Future<void> _verifyExistingSnapshot(
    File file, {
    required String expectedDigest,
    required int expectedByteSize,
  }) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw StateError(
        'Browser snapshot archive target is not a regular file.',
      );
    }
    if (await file.length() != expectedByteSize) {
      throw StateError(
        'Browser snapshot archive target does not match its record.',
      );
    }
    final digest = sha256.convert(await file.readAsBytes()).toString();
    if (digest != expectedDigest) {
      throw StateError(
        'Browser snapshot archive target does not match its record.',
      );
    }
  }

  void _validatePng(Uint8List bytes) {
    if (!BrowserPageSnapshot.isValidVisualPng(bytes)) {
      throw ArgumentError.value(bytes, 'pngBytes', 'Expected a bounded PNG.');
    }
  }

  String _randomSuffix() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(1 << 32).toRadixString(36)}';
}

class BrowserVisualSnapshotArchiveRecord {
  final String filePath;
  final String sha256;
  final int byteSize;
  final String url;
  final DateTime capturedAt;

  const BrowserVisualSnapshotArchiveRecord({
    required this.filePath,
    required this.sha256,
    required this.byteSize,
    required this.url,
    required this.capturedAt,
  });
}
