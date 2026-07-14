import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Opaque, Keychain-backed storage for macOS security-scoped workspace
/// bookmarks. Bookmark bytes are capabilities, not normal application
/// preferences, so the workspace path is never used as a Keychain item name.
abstract interface class MacosWorkspaceBookmarkStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterMacosWorkspaceBookmarkStore
    implements MacosWorkspaceBookmarkStore {
  final FlutterSecureStorage _storage;

  const FlutterMacosWorkspaceBookmarkStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

class MacosWorkspaceAccessResult {
  final bool granted;
  final String path;
  final String? message;

  const MacosWorkspaceAccessResult({
    required this.granted,
    required this.path,
    this.message,
  });

  factory MacosWorkspaceAccessResult.allowed(String path) =>
      MacosWorkspaceAccessResult(granted: true, path: path);

  factory MacosWorkspaceAccessResult.denied(String path, String message) =>
      MacosWorkspaceAccessResult(granted: false, path: path, message: message);
}

/// The only Dart boundary allowed to request persistent macOS workspace
/// access. It is deliberately separate from the agent, command, browser, and
/// file-tree paths: a model cannot mint or resume a user filesystem grant.
abstract interface class MacosWorkspaceAccess {
  /// Captures a bookmark immediately after a native user selection (or a
  /// Finder/Dock open event) and starts its scope for this app process.
  Future<MacosWorkspaceAccessResult> grantUserSelectedWorkspace(String path);

  /// Resumes exactly the Keychain-backed scope previously granted for [path].
  /// Missing, stale-unrecoverable, or malformed grants fail closed.
  Future<MacosWorkspaceAccessResult> resumeWorkspace(String path);

  /// Releases the active scope and removes the persisted capability.
  Future<void> revokeWorkspace(String path);
}

class NativeMacosWorkspaceAccess implements MacosWorkspaceAccess {
  static const _channelName = 'circuitcode/workspace_access';
  static const _bookmarkPrefix = 'circuit.workspace.bookmark.v1.';

  final MethodChannel _channel;
  final MacosWorkspaceBookmarkStore _store;
  final bool Function() _isSupported;
  final bool _allowUnhostedDebugAccess;

  NativeMacosWorkspaceAccess({
    MethodChannel channel = const MethodChannel(_channelName),
    MacosWorkspaceBookmarkStore store =
        const FlutterMacosWorkspaceBookmarkStore(),
    bool Function()? isSupported,
    bool? allowUnhostedDebugAccess,
  }) : _channel = channel,
       _store = store,
       _isSupported = isSupported ?? _supportsMacos,
       _allowUnhostedDebugAccess = allowUnhostedDebugAccess ?? kDebugMode;

  @override
  Future<MacosWorkspaceAccessResult> grantUserSelectedWorkspace(
    String path,
  ) async {
    final normalized = _normalize(path);
    if (normalized.isEmpty) {
      return MacosWorkspaceAccessResult.denied(
        normalized,
        'Choose a project folder before continuing.',
      );
    }
    if (!_isSupported()) return MacosWorkspaceAccessResult.allowed(normalized);
    return _invokeAndPersist(
      method: 'createAndStartWorkspaceAccess',
      path: normalized,
    );
  }

  @override
  Future<MacosWorkspaceAccessResult> resumeWorkspace(String path) async {
    final normalized = _normalize(path);
    if (normalized.isEmpty) {
      return MacosWorkspaceAccessResult.denied(
        normalized,
        'Choose a project folder before continuing.',
      );
    }
    if (!_isSupported()) return MacosWorkspaceAccessResult.allowed(normalized);

    final bookmark = await _store.read(key: _bookmarkKey(normalized));
    if (bookmark == null || !_isBase64(bookmark)) {
      if (_allowUnhostedDebugAccess) {
        return MacosWorkspaceAccessResult.allowed(normalized);
      }
      return MacosWorkspaceAccessResult.denied(
        normalized,
        'Workspace access expired. Reopen the project folder to grant access again.',
      );
    }
    return _invokeAndPersist(
      method: 'resumeWorkspaceAccess',
      path: normalized,
      bookmark: bookmark,
    );
  }

  @override
  Future<void> revokeWorkspace(String path) async {
    final normalized = _normalize(path);
    if (normalized.isEmpty) return;
    if (_isSupported()) {
      try {
        await _channel.invokeMethod<void>('stopWorkspaceAccess', {
          'path': normalized,
        });
      } on PlatformException {
        // Revocation still removes the retained capability below. The native
        // scope disappears with the process if an isolated host is exiting.
      } on MissingPluginException {
        // Widget/unit hosts do not have AppDelegate channels.
      }
    }
    await _store.delete(key: _bookmarkKey(normalized));
  }

  Future<MacosWorkspaceAccessResult> _invokeAndPersist({
    required String method,
    required String path,
    String? bookmark,
  }) async {
    Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMapMethod<Object?, Object?>(method, {
        'path': path,
        'bookmark': ?bookmark,
      });
    } on MissingPluginException {
      // Test/debug Flutter hosts do not install the AppDelegate channel. A
      // shipping sandboxed app always has it; never apply this compatibility
      // path in a release build.
      if (_allowUnhostedDebugAccess) {
        return MacosWorkspaceAccessResult.allowed(path);
      }
      return _platformDenied(path);
    } on PlatformException {
      return _platformDenied(path);
    }
    if (raw == null) return _platformDenied(path);

    final sandboxed = raw['sandboxed'] == true;
    final resolved = _normalize(raw['path']?.toString() ?? path);
    if (resolved.isEmpty) return _platformDenied(path);
    if (!sandboxed) return MacosWorkspaceAccessResult.allowed(resolved);

    final encodedBookmark = raw['bookmark']?.toString() ?? '';
    if (!_isBase64(encodedBookmark)) return _platformDenied(path);
    try {
      await _store.write(key: _bookmarkKey(path), value: encodedBookmark);
      if (resolved != path) {
        await _store.write(key: _bookmarkKey(resolved), value: encodedBookmark);
      }
    } on Exception {
      // Do not leave a scoped workspace usable only until restart. Revoke the
      // process-local scope before reporting a Keychain persistence failure.
      try {
        await _channel.invokeMethod<void>('stopWorkspaceAccess', {
          'path': resolved,
        });
      } on PlatformException {
        // The generic failure below remains the only user-visible result.
      }
      return MacosWorkspaceAccessResult.denied(
        path,
        'Workspace access could not be saved securely. Check Keychain and try again.',
      );
    }
    return MacosWorkspaceAccessResult.allowed(resolved);
  }

  MacosWorkspaceAccessResult _platformDenied(
    String path,
  ) => MacosWorkspaceAccessResult.denied(
    path,
    'Workspace access was not granted. Reopen the project folder and try again.',
  );

  static String _normalize(String path) {
    final trimmed = path.trim();
    return trimmed.isEmpty ? '' : p.normalize(trimmed);
  }

  static String _bookmarkKey(String path) =>
      '$_bookmarkPrefix${sha256.convert(utf8.encode(path)).toString()}';

  static bool _isBase64(String value) {
    if (value.isEmpty || value.length > 262144) return false;
    try {
      return base64Encode(base64Decode(value)) == value;
    } on FormatException {
      return false;
    }
  }

  static bool _supportsMacos() => Platform.isMacOS;
}

final macosWorkspaceAccessProvider = Provider<MacosWorkspaceAccess>(
  (ref) => NativeMacosWorkspaceAccess(),
);
