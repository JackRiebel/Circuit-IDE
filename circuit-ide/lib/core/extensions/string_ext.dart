extension StringExt on String {
  String truncate(int maxLength, {String ellipsis = '...'}) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength - ellipsis.length)}$ellipsis';
  }

  String get fileNameFromPath {
    final parts = split(RegExp(r'[/\\]'));
    return parts.isNotEmpty ? parts.last : this;
  }

  String get directoryFromPath {
    final lastSep = lastIndexOf(RegExp(r'[/\\]'));
    return lastSep >= 0 ? substring(0, lastSep) : '';
  }

  int get estimatedTokens => (length / 4).ceil();

  bool get isNotBlank => trim().isNotEmpty;
}
