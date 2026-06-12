enum BrowserSitePermission { unknown, allowed, blocked }

class BrowserAnnotation {
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
}

class StudioBrowserSession {
  final String? currentUrl;
  final String addressDraft;
  final List<String> history;
  final int historyIndex;
  final int loadingProgress;
  final String? error;
  final BrowserSitePermission permission;
  final List<BrowserAnnotation> annotations;
  final int reloadNonce;

  const StudioBrowserSession({
    this.currentUrl,
    this.addressDraft = '',
    this.history = const [],
    this.historyIndex = -1,
    this.loadingProgress = 0,
    this.error,
    this.permission = BrowserSitePermission.unknown,
    this.annotations = const [],
    this.reloadNonce = 0,
  });

  bool get canGoBack => historyIndex > 0;
  bool get canGoForward =>
      historyIndex >= 0 && historyIndex < history.length - 1;

  StudioBrowserSession copyWith({
    Object? currentUrl = _sentinel,
    String? addressDraft,
    List<String>? history,
    int? historyIndex,
    int? loadingProgress,
    Object? error = _sentinel,
    BrowserSitePermission? permission,
    List<BrowserAnnotation>? annotations,
    int? reloadNonce,
  }) {
    return StudioBrowserSession(
      currentUrl: identical(currentUrl, _sentinel)
          ? this.currentUrl
          : currentUrl as String?,
      addressDraft: addressDraft ?? this.addressDraft,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
      loadingProgress: loadingProgress ?? this.loadingProgress,
      error: identical(error, _sentinel) ? this.error : error as String?,
      permission: permission ?? this.permission,
      annotations: annotations ?? this.annotations,
      reloadNonce: reloadNonce ?? this.reloadNonce,
    );
  }
}

String? normalizeBrowserUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri.toString();
}

const _sentinel = Object();
