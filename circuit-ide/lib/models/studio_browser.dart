import 'dart:typed_data';

enum BrowserSitePermission { unknown, allowed, blocked }

/// A bounded, untrusted observation from the user-controlled browser preview.
///
/// It is session state only. The assistant receives browser content only when
/// the user explicitly shares [selectedText] with the current task.
class BrowserPageSnapshot {
  static const maxTitleLength = 300;
  static const maxSelectionLength = 12000;
  static const maxTextPreviewLength = 12000;
  static const maxDomPathLength = 1000;
  static const maxVisualSnapshotBytes = 4 * 1024 * 1024;
  static const maxVisualSnapshotDimension = 8192;
  static const maxVisualSnapshotPixels = 32 * 1024 * 1024;
  static const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

  final String url;
  final String title;
  final String selectedText;
  final String selectedDomPath;
  final String textPreview;
  final Uint8List? visualPngBytes;
  final DateTime capturedAt;

  BrowserPageSnapshot({
    required this.url,
    required String title,
    required String selectedText,
    required String selectedDomPath,
    required String textPreview,
    Uint8List? visualPngBytes,
    required this.capturedAt,
  }) : title = _bound(title, maxTitleLength),
       selectedText = _bound(selectedText, maxSelectionLength),
       selectedDomPath = _bound(selectedDomPath, maxDomPathLength),
       textPreview = _bound(textPreview, maxTextPreviewLength),
       visualPngBytes = _boundVisualSnapshot(visualPngBytes);

  bool get hasSelection => selectedText.trim().isNotEmpty;
  bool get hasVisualSnapshot => visualPngBytes != null;

  static String _bound(String value, int maximum) {
    final normalized = value.trim();
    if (normalized.length <= maximum) return normalized;
    return '${normalized.substring(0, maximum)}\n[Browser observation truncated]';
  }

  static Uint8List? _boundVisualSnapshot(Uint8List? value) {
    if (!isValidVisualPng(value)) return null;
    return Uint8List.fromList(value!);
  }

  /// Validates a bounded PNG container without decoding it. Native capture
  /// data crosses a platform channel and later reaches a private local archive,
  /// so a magic header alone is not sufficient evidence that it is a usable,
  /// reasonably sized image.
  static bool isValidVisualPng(Uint8List? value) {
    if (value == null ||
        value.lengthInBytes > maxVisualSnapshotBytes ||
        value.lengthInBytes < 57) {
      return false;
    }
    for (var index = 0; index < _pngSignature.length; index++) {
      if (value[index] != _pngSignature[index]) return false;
    }

    var offset = _pngSignature.length;
    var hasHeader = false;
    var hasImageData = false;
    while (offset < value.lengthInBytes) {
      if (value.lengthInBytes - offset < 12) return false;
      final length = _pngUint32(value, offset);
      final typeOffset = offset + 4;
      final dataOffset = offset + 8;
      if (length > value.lengthInBytes - dataOffset - 4) return false;
      final nextOffset = dataOffset + length + 4;
      final isHeader = _pngChunkType(value, typeOffset, 'IHDR');
      final isImageData = _pngChunkType(value, typeOffset, 'IDAT');
      final isEnd = _pngChunkType(value, typeOffset, 'IEND');

      if (!hasHeader) {
        if (!isHeader || length != 13) return false;
        final width = _pngUint32(value, dataOffset);
        final height = _pngUint32(value, dataOffset + 4);
        if (width <= 0 ||
            height <= 0 ||
            width > maxVisualSnapshotDimension ||
            height > maxVisualSnapshotDimension ||
            width * height > maxVisualSnapshotPixels) {
          return false;
        }
        hasHeader = true;
      } else if (isHeader) {
        return false;
      }

      if (isImageData && length > 0) hasImageData = true;
      if (isEnd) {
        return hasHeader &&
            hasImageData &&
            length == 0 &&
            nextOffset == value.lengthInBytes;
      }
      offset = nextOffset;
    }
    return false;
  }

  static int _pngUint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static bool _pngChunkType(Uint8List bytes, int offset, String type) =>
      bytes[offset] == type.codeUnitAt(0) &&
      bytes[offset + 1] == type.codeUnitAt(1) &&
      bytes[offset + 2] == type.codeUnitAt(2) &&
      bytes[offset + 3] == type.codeUnitAt(3);
}

class BrowserAnnotation {
  static const maxNoteLength = 2000;

  final String id;
  final String url;
  final String note;
  final DateTime createdAt;

  const BrowserAnnotation({
    required this.id,
    required this.url,
    required this.note,
    required this.createdAt,
  });

  static String boundNote(String value) {
    final normalized = value.trim();
    if (normalized.length <= maxNoteLength) return normalized;
    const suffix = '\n[Browser annotation truncated]';
    return '${normalized.substring(0, maxNoteLength - suffix.length)}$suffix';
  }
}

class StudioBrowserTab {
  static const maxHistoryEntries = 100;
  static const maxAddressDraftLength = 4096;

  final String id;
  final String? currentUrl;
  final String addressDraft;
  final List<String> history;
  final int historyIndex;
  final int loadingProgress;
  final String? error;
  final BrowserPageSnapshot? snapshot;
  final int reloadNonce;

  const StudioBrowserTab({
    required this.id,
    this.currentUrl,
    this.addressDraft = '',
    this.history = const [],
    this.historyIndex = -1,
    this.loadingProgress = 0,
    this.error,
    this.snapshot,
    this.reloadNonce = 0,
  });

  bool get canGoBack => historyIndex > 0;
  bool get canGoForward =>
      historyIndex >= 0 && historyIndex < history.length - 1;

  String get label {
    final title = snapshot?.title.trim() ?? '';
    if (title.isNotEmpty) return title;
    final uri = currentUrl == null ? null : Uri.tryParse(currentUrl!);
    if (uri?.host.isNotEmpty == true) return uri!.host;
    return 'New page';
  }

  StudioBrowserTab copyWith({
    Object? currentUrl = _sentinel,
    String? addressDraft,
    List<String>? history,
    int? historyIndex,
    int? loadingProgress,
    Object? error = _sentinel,
    Object? snapshot = _sentinel,
    int? reloadNonce,
  }) {
    return StudioBrowserTab(
      id: id,
      currentUrl: identical(currentUrl, _sentinel)
          ? this.currentUrl
          : currentUrl as String?,
      addressDraft: addressDraft ?? this.addressDraft,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
      loadingProgress: loadingProgress ?? this.loadingProgress,
      error: identical(error, _sentinel) ? this.error : error as String?,
      snapshot: identical(snapshot, _sentinel)
          ? this.snapshot
          : snapshot as BrowserPageSnapshot?,
      reloadNonce: reloadNonce ?? this.reloadNonce,
    );
  }
}

/// Browser pages are bounded user-controlled state. Each tab retains its own
/// URL/history/snapshot, while permissions and private annotations remain at
/// the preview-session level. Browser state is never assistant context by
/// itself.
class StudioBrowserSession {
  static const maxTabCount = 6;
  static const maxAnnotationCount = 40;

  final List<StudioBrowserTab> tabs;
  final String activeTabId;
  final Map<String, BrowserSitePermission> sitePermissions;
  final List<BrowserAnnotation> annotations;

  const StudioBrowserSession({
    this.tabs = const [StudioBrowserTab(id: 'browser-tab-1')],
    this.activeTabId = 'browser-tab-1',
    this.sitePermissions = const {},
    this.annotations = const [],
  });

  StudioBrowserTab get activeTab {
    for (final tab in tabs) {
      if (tab.id == activeTabId) return tab;
    }
    if (tabs.isNotEmpty) return tabs.first;
    return const StudioBrowserTab(id: 'browser-tab-1');
  }

  String? get currentUrl => activeTab.currentUrl;
  String get addressDraft => activeTab.addressDraft;
  List<String> get history => activeTab.history;
  int get historyIndex => activeTab.historyIndex;
  int get loadingProgress => activeTab.loadingProgress;
  String? get error => activeTab.error;
  BrowserPageSnapshot? get snapshot => activeTab.snapshot;
  int get reloadNonce => activeTab.reloadNonce;

  bool get canGoBack => activeTab.canGoBack;
  bool get canGoForward => activeTab.canGoForward;

  BrowserSitePermission permissionFor(String? url) {
    final scope = browserPermissionScope(url);
    if (scope == null) return BrowserSitePermission.unknown;
    return sitePermissions[scope] ?? BrowserSitePermission.unknown;
  }

  bool isBlocked(String? url) =>
      permissionFor(url) == BrowserSitePermission.blocked;

  StudioBrowserSession copyWith({
    List<StudioBrowserTab>? tabs,
    String? activeTabId,
    Map<String, BrowserSitePermission>? sitePermissions,
    List<BrowserAnnotation>? annotations,
  }) {
    return StudioBrowserSession(
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
      sitePermissions: sitePermissions ?? this.sitePermissions,
      annotations: annotations ?? this.annotations,
    );
  }
}

String? normalizeBrowserUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty ||
      trimmed.length > StudioBrowserTab.maxAddressDraftLength) {
    return null;
  }
  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri == null ||
      !uri.hasScheme ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri.toString();
}

/// The only browser URL shape that may be retained in a durable source
/// artifact or supplied as request-local provenance. Browser navigation may
/// need a query or fragment while it remains in session memory, but those
/// values often carry credentials or per-user state and must not accompany a
/// selected-text citation or locally saved visual snapshot.
String? browserProvenanceUrl(String? input) {
  if (input == null) return null;
  final normalized = normalizeBrowserUrl(input);
  if (normalized == null) return null;
  final uri = Uri.parse(normalized);
  return Uri(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

/// Re-redacts browser URLs in legacy persisted selection artifacts before they
/// become context. The selected text itself remains user-authorized; this only
/// removes ambient URL credentials, query values, and fragments that older
/// artifact records added as provenance headers.
String sanitizeBrowserProvenanceText(String value) {
  final urlPattern = RegExp(r'''https?://[^\s<>"')\]]+''');
  return value.replaceAllMapped(urlPattern, (match) {
    return browserProvenanceUrl(match.group(0)) ?? '[browser URL omitted]';
  });
}

/// Permissions are constrained to a concrete web origin. A localhost preview
/// on one port must not silently authorize another local service.
String? browserPermissionScope(String? input) {
  if (input == null) return null;
  final normalized = normalizeBrowserUrl(input);
  if (normalized == null) return null;
  final uri = Uri.parse(normalized);
  final port = uri.hasPort
      ? ':${uri.port}'
      : uri.scheme == 'https'
      ? ':443'
      : ':80';
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$port';
}

const _sentinel = Object();
