class SecretMatch {
  final String type;
  final String severity;
  final int line;
  final String preview;

  const SecretMatch({
    required this.type,
    required this.severity,
    required this.line,
    required this.preview,
  });
}

class SecretDetector {
  static final _patterns = <_SecretPattern>[
    // API Keys (HIGH severity)
    _SecretPattern(
      RegExp(
        r"""(api[_-]?key|apikey)\s*[:=]\s*["']?([a-zA-Z0-9\-_]{20,})["']?""",
        caseSensitive: false,
      ),
      'API Key',
      'high',
    ),
    _SecretPattern(
      RegExp(
        r"""(secret[_-]?key|secretkey)\s*[:=]\s*["']?([a-zA-Z0-9\-_]{20,})["']?""",
        caseSensitive: false,
      ),
      'Secret Key',
      'high',
    ),

    // Passwords (CRITICAL severity)
    _SecretPattern(
      RegExp(
        r"""(password|passwd|pwd)\s*[:=]\s*["']([^"']{4,})["']""",
        caseSensitive: false,
      ),
      'Password',
      'critical',
    ),
    _SecretPattern(
      RegExp(
        r"""(password|passwd|pwd)\s*[:=]\s*([^\s"']{8,})""",
        caseSensitive: false,
      ),
      'Password',
      'critical',
    ),

    // AWS (CRITICAL severity)
    _SecretPattern(
      RegExp(r'AKIA[0-9A-Z]{16}'),
      'AWS Access Key ID',
      'critical',
    ),
    _SecretPattern(
      RegExp(
        r"""aws[_-]?secret[_-]?access[_-]?key\s*[:=]\s*["']?([a-zA-Z0-9/+=]{40})["']?""",
        caseSensitive: false,
      ),
      'AWS Secret Access Key',
      'critical',
    ),

    // GitHub tokens (CRITICAL severity)
    _SecretPattern(
      RegExp(r'ghp_[a-zA-Z0-9]{36}'),
      'GitHub Personal Access Token',
      'critical',
    ),
    _SecretPattern(
      RegExp(r'gho_[a-zA-Z0-9]{36}'),
      'GitHub OAuth Token',
      'critical',
    ),
    _SecretPattern(
      RegExp(r'github_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{59}'),
      'GitHub Fine-Grained PAT',
      'critical',
    ),

    // OpenAI (CRITICAL severity)
    _SecretPattern(RegExp(r'sk-[a-zA-Z0-9]{48}'), 'OpenAI API Key', 'critical'),
    _SecretPattern(
      RegExp(r'sk-proj-[a-zA-Z0-9\-_]{48,}'),
      'OpenAI Project API Key',
      'critical',
    ),

    // Slack (CRITICAL severity)
    _SecretPattern(
      RegExp(r'xox[baprs]-[a-zA-Z0-9\-]{10,}'),
      'Slack Token',
      'critical',
    ),

    // Private Keys (CRITICAL severity)
    _SecretPattern(
      RegExp(r'-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'),
      'Private Key',
      'critical',
    ),
    _SecretPattern(
      RegExp(r'-----BEGIN PGP PRIVATE KEY BLOCK-----'),
      'PGP Private Key',
      'critical',
    ),

    // Database URLs (CRITICAL severity)
    _SecretPattern(
      RegExp(
        r"""(mongodb|postgres|mysql|redis)://[^\s<>"']+:[^\s<>"']+@[^\s<>"']+""",
        caseSensitive: false,
      ),
      'Database Connection String',
      'critical',
    ),

    // Generic tokens (HIGH severity)
    _SecretPattern(
      RegExp(
        r"""(auth[_-]?token|access[_-]?token|bearer)\s*[:=]\s*["']?([a-zA-Z0-9\-_.]{20,})["']?""",
        caseSensitive: false,
      ),
      'Auth Token',
      'high',
    ),
    _SecretPattern(
      RegExp(
        r"""(client[_-]?secret)\s*[:=]\s*["']?([a-zA-Z0-9\-_]{20,})["']?""",
        caseSensitive: false,
      ),
      'Client Secret',
      'high',
    ),
  ];

  List<SecretMatch> scan(String content) {
    final matches = <SecretMatch>[];
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      for (final pattern in _patterns) {
        if (pattern.regex.hasMatch(lines[i])) {
          final match = pattern.regex.firstMatch(lines[i])!;
          final preview = _redactPreview(lines[i], match);
          matches.add(
            SecretMatch(
              type: pattern.type,
              severity: pattern.severity,
              line: i + 1,
              preview: preview,
            ),
          );
        }
      }
    }
    return matches;
  }

  bool hasSecrets(String content) => scan(content).isNotEmpty;

  String _redactPreview(String line, RegExpMatch match) {
    final matched = match.group(0) ?? '';
    if (matched.length <= 8) return line;
    final redacted =
        '${matched.substring(0, 4)}${'*' * (matched.length - 8)}${matched.substring(matched.length - 4)}';
    return line.replaceFirst(matched, redacted);
  }
}

class _SecretPattern {
  final RegExp regex;
  final String type;
  final String severity;

  const _SecretPattern(this.regex, this.type, this.severity);
}
