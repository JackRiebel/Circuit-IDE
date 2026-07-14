/// Produces the minimal environment inherited by Circuit-launched processes.
///
/// Connector credentials are deliberately supplied by the caller; the host
/// process environment is never copied wholesale into an MCP or command
/// process.
abstract final class ChildProcessEnvironment {
  static Map<String, String> build({
    required Map<String, String> baseEnvironment,
    Map<String, String> injected = const {},
    Map<String, String> fixed = const {},
    String terminal = 'dumb',
  }) {
    final environment = <String, String>{};
    for (final entry in baseEnvironment.entries) {
      if (_isAllowedBaseKey(entry.key) && !_isSensitiveKey(entry.key)) {
        environment[entry.key] = entry.value;
      }
    }
    for (final entry in injected.entries) {
      if (_isAllowedInjectedKey(entry.key)) {
        environment[entry.key] = entry.value;
      }
    }
    for (final entry in fixed.entries) {
      if (_isSafeFixedKey(entry.key)) {
        environment[entry.key] = entry.value;
      }
    }
    environment['TERM'] = terminal;
    return environment;
  }

  /// Removes declared secret values and common key-value representations from
  /// child output before it reaches diagnostic logging.
  static String redactOutput(String output, Iterable<String> secretValues) {
    var redacted = output;
    for (final value in secretValues) {
      final normalized = value.trim();
      if (normalized.length >= 3) {
        redacted = redacted.replaceAll(normalized, '[REDACTED]');
      }
    }
    final keyValue = RegExp(
      r'''\b([a-z][a-z0-9_-]*)\s*([:=])\s*([^\s,;]+)''',
      caseSensitive: false,
    );
    return redacted.replaceAllMapped(keyValue, (match) {
      final key = match.group(1) ?? '';
      if (!_isSensitiveKey(key)) return match.group(0)!;
      return '$key${match.group(2)}[REDACTED]';
    });
  }

  static bool _isAllowedBaseKey(String key) {
    final upper = key.toUpperCase();
    return upper.startsWith('LC_') ||
        const {
          'ANDROID_HOME',
          'ANDROID_SDK_ROOT',
          'CI',
          'DART_SDK',
          'DEVELOPER_DIR',
          'FLUTTER_ROOT',
          'GEM_HOME',
          'GEM_PATH',
          'GRADLE_USER_HOME',
          'HOME',
          'JAVA_HOME',
          'LANG',
          'LOGNAME',
          'NPM_CONFIG_CACHE',
          'PATH',
          'PUB_CACHE',
          'PWD',
          'SDKROOT',
          'SHELL',
          'TMP',
          'TMPDIR',
          'TEMP',
          'USER',
          'XCODE_DEVELOPER_DIR_PATH',
        }.contains(upper);
  }

  static bool _isAllowedInjectedKey(String key) {
    final upper = key.toUpperCase();
    if (!RegExp(r'^[A-Z_][A-Z0-9_]*$').hasMatch(upper)) return false;
    if (_isAllowedBaseKey(upper)) return false;
    return !RegExp(
      r'^(?:DYLD_|LD_|PYTHON(?:HOME|PATH|STARTUP)|RUBYOPT|PERL5OPT|NODE_OPTIONS|BASH_ENV|ENV$|ZDOTDIR$)',
    ).hasMatch(upper);
  }

  static bool _isSafeFixedKey(String key) =>
      RegExp(r'^[A-Z_][A-Z0-9_]*$').hasMatch(key) && !_isSensitiveKey(key);

  static bool _isSensitiveKey(String key) => RegExp(
    r'(TOKEN|SECRET|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|COOKIE|SESSION|AUTH|API[_-]?KEY|ACCESS[_-]?KEY|CLIENT[_-]?SECRET|SSH_AUTH_SOCK)',
  ).hasMatch(key.toUpperCase());
}
