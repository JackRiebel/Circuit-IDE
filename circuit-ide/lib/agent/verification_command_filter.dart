import 'security/command_sanitizer.dart';

bool isRunnableVerificationCommand(String value) {
  final command = value.trim();
  if (command.isEmpty) return false;
  if (command.contains('\n')) return false;
  if (CommandSanitizer.checkDangerous(command) != null) return false;
  if (CommandSanitizer.checkNetworkAccess(command) != null) return false;
  if (_hasUnsafePathArgument(command)) return false;
  final first = command.split(RegExp(r'\s+')).first.toLowerCase();
  if (first == 'test') return _isSafeFileExistenceCheck(command);
  const knownCommands = {
    'cargo',
    'dart',
    'flutter',
    'go',
    'make',
    'npm',
    'pnpm',
    'python',
    'python3',
    'swift',
    'yarn',
    'xcodebuild',
  };
  return knownCommands.contains(first);
}

/// Allows the smallest useful subset of the POSIX `test` builtin for a patch
/// verification: checking whether one safe file or directory exists inside the
/// workspace. This does not permit arbitrary shell predicates, sensitive
/// paths, absolute paths, or traversal outside the bound project.
bool _isSafeFileExistenceCheck(String command) {
  final tokens = command.split(RegExp(r'\s+'));
  if (tokens.length != 3) return false;
  if (!const {'-d', '-e', '-f'}.contains(tokens[1])) return false;
  final target = _normalizeToken(tokens[2]);
  if (target.isEmpty || CommandSanitizer.looksSensitivePath(target)) {
    return false;
  }
  return !_isUnsafePathToken(target);
}

bool _hasUnsafePathArgument(String command) {
  for (final rawToken in command.split(RegExp(r'\s+'))) {
    final token = _normalizeToken(rawToken);
    if (token.isEmpty) continue;
    if (token.startsWith('-') && !token.startsWith('--/')) continue;
    if (_isUnsafePathToken(token)) return true;
  }
  return false;
}

String _normalizeToken(String token) {
  var normalized = token.trim();
  const wrappers = {'"': '"', "'": "'", '`': '`', '(': ')', '[': ']', '{': '}'};
  var changed = true;
  while (changed && normalized.length > 1) {
    changed = false;
    final first = normalized[0];
    final last = normalized[normalized.length - 1];
    if (wrappers[first] == last) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
      changed = true;
      continue;
    }
    if (',.;:'.contains(last)) {
      normalized = normalized.substring(0, normalized.length - 1).trim();
      changed = true;
    }
  }
  return normalized;
}

bool _isUnsafePathToken(String token) {
  final normalized = token.replaceAll('\\', '/');
  if (normalized.startsWith('/')) return true;
  if (normalized.startsWith('~/') || normalized == '~') return true;
  if (normalized.startsWith('//')) return true;
  if (RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) return true;
  if (normalized == '..' ||
      normalized.startsWith('../') ||
      normalized.endsWith('/..') ||
      normalized.contains('/../')) {
    return true;
  }
  return false;
}

bool isSafePackageScriptBody(Object? value) {
  if (value is! String) return false;
  final script = value.trim();
  if (script.isEmpty) return false;
  if (script.contains('\n')) return false;
  if (CommandSanitizer.checkDangerous(script) != null) return false;
  if (CommandSanitizer.checkNetworkAccess(script) != null) return false;
  return true;
}
