import 'package:path/path.dart' as p;

class CommandSanitizer {
  static final _dangerousPatterns = <RegExp, String>{
    // File destruction
    RegExp(r'\brm\s+(-[a-zA-Z]*r[a-zA-Z]*\s+|.*-rf\s+)/'):
        'Recursive removal of root directory',
    RegExp(r'\brm\s+-[a-zA-Z]*r[a-zA-Z]*f'): 'Force recursive file deletion',
    RegExp(r'\brm\s+-[a-zA-Z]*f[a-zA-Z]*r'): 'Force recursive file deletion',
    RegExp(
      r'\brm\s+(?=(?:-[a-z]*r\b|--recursive\b|[^\n]*\s(?:-[a-z]*r\b|--recursive\b)))(?=(?:-[a-z]*f\b|--force\b|[^\n]*\s(?:-[a-z]*f\b|--force\b)))[^\n]*',
      caseSensitive: false,
    ): 'Force recursive file deletion',
    RegExp(r'>\s*/dev/sd[a-z]'): 'Writing to raw disk device',

    // Privileged operations
    RegExp(r'\bsudo\s+rm\b'): 'Privileged file deletion',
    RegExp(r'\bsudo\s+chmod\b'): 'Privileged permission change',
    RegExp(r'\bchmod\s+777\s+/'): 'Setting world-writable permissions on root',

    // System operations
    RegExp(r'\bmkfs\.'): 'Filesystem formatting',
    RegExp(r'\bdd\s+.*of=/dev/'): 'Raw disk writing',
    RegExp(r'\b(shutdown|reboot|halt|poweroff)\b'): 'System shutdown/reboot',
    RegExp(r':\(\)\s*\{\s*:\|:\s*&\s*\}\s*;'): 'Fork bomb',

    // Git dangers
    RegExp(r'\bgit\s+push\s+([^\n]*\s)?(-f|--force(?:-with-lease)?)\b'):
        'Force push (may overwrite history)',
    RegExp(r'\bgit\s+reset\s+--hard\b'): 'Hard reset (discards changes)',

    // Code execution from internet
    RegExp(r'\bcurl\s+.*\|\s*(ba)?sh\b'): 'Piping remote content to shell',
    RegExp(r'\bwget\s+.*\|\s*(ba)?sh\b'): 'Piping remote content to shell',

    // Reverse shells
    RegExp(r'/dev/tcp/'): 'Network device access (possible reverse shell)',
    RegExp(r'\bnc\s+-[a-zA-Z]*l'): 'Netcat listener (possible reverse shell)',
    RegExp(r'\bbash\s+-i\s+>&\s*/dev/tcp'): 'Bash reverse shell',

    // Dangerous redirects
    RegExp(r'>\s*/dev/null\s+2>&1\s*&'): 'Background process hiding output',

    // Command injection patterns
    RegExp(r'\$\([^)]+\)'): 'Command substitution',
    RegExp(r'`[^`]+`'): 'Backtick command substitution',
    RegExp(
      r'(^|\s)(bash|sh|zsh|fish|powershell|pwsh)\s+(-(?:[a-z]*c|command)|/c|--command)\b',
      caseSensitive: false,
    ): 'Nested shell command execution',

    // Secret/environment file access
    RegExp(
      r'(^|\s)(cat|less|more|head|tail|grep|rg|sed|awk|perl|ls|find|stat|du)\s+[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.ssh\b|\.ssh/|\.aws\b|\.aws/|aws/credentials|\.azure\b|\.azure/|\.kube/config|\.docker/config\.json|\.config/gh/hosts\.yml|\.config/gcloud)',
      caseSensitive: false,
    ): 'Secret or environment file access',
    RegExp(r'(^|\s)(env|printenv|set)\s*($|[|;&>])', caseSensitive: false):
        'Environment variable dump',
    RegExp(
      r'(<|>|>>|\bsource\b|\.)\s*[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.aws/|aws/credentials)',
      caseSensitive: false,
    ): 'Secret or environment file access',
    RegExp(
      r'(^|\s)(python|python3|node|ruby|php|perl)\b[^\n]*(open|readfilesync|file_get_contents|read_text|readbytes|read\s*\()[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.aws/|aws/credentials)',
      caseSensitive: false,
    ): 'Secret or environment file access',
    RegExp(
      r'(^|\s)(cp|rsync|tar|zip|7z|gzip|gpg|base64)\b[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.aws/|aws/credentials)',
      caseSensitive: false,
    ): 'Secret or environment file access',
    RegExp(
      r'(^|\s)(security\s+(find-generic-password|find-internet-password|dump-keychain)|gh\s+auth\s+token|gcloud\s+auth\s+(print-access-token|print-identity-token)|aws\s+configure\s+get|firebase\s+functions:secrets:access|npm\s+token\b|vercel\s+env\s+(pull|ls|add|rm)|op\s+(read|item\s+get)|pass\s+(show|find)|doppler\s+secrets|vault\s+(read|kv\s+get))\b',
      caseSensitive: false,
    ): 'Secret or credential manager access',
  };

  /// Check if a command matches any dangerous patterns.
  /// Returns description of the danger, or null if safe.
  static String? checkDangerous(String command) {
    final unsafeSyntax = _unsafeShellSyntax(command);
    if (unsafeSyntax != null) return unsafeSyntax;
    for (final entry in _dangerousPatterns.entries) {
      if (entry.key.hasMatch(command)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Detect commands that can initiate network access.
  ///
  /// Policy decides whether a reviewed Studio turn may run one of these. This
  /// low-level guard exists so direct CommandTools callers fail closed instead
  /// of bypassing the Studio permission policy.
  static String? checkNetworkAccess(String command) {
    final normalized = command.trim().toLowerCase();
    if (RegExp(
      r'(^|\s)(curl|wget|scp|ssh|ftp|sftp|nc|ncat|telnet|openssl\s+s_client|iwr|irm|invoke-webrequest|invoke-restmethod|bitsadmin|start-bitstransfer|ping|traceroute|tracepath|dig|nslookup|host|whois)\b',
    ).hasMatch(normalized)) {
      return 'Network command requires explicit approval';
    }
    if (RegExp(r'(^|\s)certutil\s+[^\n]*-urlcache\b').hasMatch(normalized)) {
      return 'Network command requires explicit approval';
    }
    if (RegExp(
      r"""\b(?:https?|wss?|ftp)://[^\s'"<>]+""",
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return 'Network URL requires explicit approval';
    }
    if (_looksLikeProgrammaticNetworkAccess(normalized)) {
      return 'Programmatic network access requires explicit approval';
    }
    if (_looksLikePackageNetworkAccess(normalized)) {
      return 'Dependency or package network command requires explicit approval';
    }
    if (_looksLikeCloudAuthAccess(normalized)) {
      return 'Cloud authentication command requires explicit approval';
    }
    if (_looksLikeCloudDeployAccess(normalized)) {
      return 'Cloud deploy or remote mutation command requires explicit approval';
    }
    return null;
  }

  /// Detect network targets that should never be reachable from Studio command
  /// execution, even after a user approves public-network access.
  static String? checkBlockedNetworkTarget(String command) {
    final targets = _networkTargetCandidates(command);
    for (final target in targets) {
      final normalized = _normalizeNetworkTarget(target);
      if (normalized.isEmpty) continue;
      final reason = _blockedNetworkTargetReason(normalized);
      if (reason != null) return reason;
    }
    return null;
  }

  /// Detect shell commands that appear to read or mutate files outside the
  /// active workspace. This is intentionally conservative and mirrors the
  /// policy-layer path boundary as an execution-layer fail-safe.
  static String? checkWorkspaceBoundary(String command, String workingDir) {
    final normalizedWorkingDir = p.normalize(workingDir.trim());
    if (normalizedWorkingDir.isEmpty) {
      return 'No active workspace is bound for command execution';
    }
    if (!_looksLikeCommandFileAccess(command)) return null;

    final candidates = <String>{
      ..._absolutePathCandidates(command),
      ..._homePathCandidates(command),
      ..._environmentPathCandidates(command),
      ..._parentTraversalPathCandidates(command),
    };
    for (final candidate in candidates) {
      final sanitized = candidate.trim().replaceAll('\\', '/');
      if (sanitized.isEmpty) continue;
      if (_looksLikeShellExpandedPath(sanitized)) {
        return 'Shell commands may not access paths outside the active workspace';
      }
      if (_looksLikeWindowsAbsolutePath(sanitized)) {
        return 'Shell commands may not access paths outside the active workspace';
      }
      final resolved = p.normalize(
        p.isAbsolute(sanitized)
            ? sanitized
            : p.join(normalizedWorkingDir, sanitized),
      );
      if (resolved != normalizedWorkingDir &&
          !p.isWithin(normalizedWorkingDir, resolved)) {
        return 'Shell commands may not access paths outside the active workspace';
      }
    }
    return null;
  }

  static bool _looksLikeProgrammaticNetworkAccess(String command) {
    final patterns = <RegExp>[
      RegExp(
        r'\b(urllib\.request|requests\.(get|post|put|patch|delete)|fetch\s*\(|https?\.get\s*\(|https?\.request\s*\(|axios\.|net/http|invoke-webrequest|invoke-restmethod)\b',
      ),
      RegExp(
        r'\b(socket\.create_connection|socket\.socket\s*\([^)]*\)\.connect|socket\(\)\.connect|socket\.gethostbyname|socket\.getaddrinfo|tcpsocket\.open|io::socket::inet)\b',
      ),
      RegExp(r'\bimport\s+socket\b[\s\S]*\.\s*connect\s*\('),
      RegExp(
        r'\bfrom\s+urllib\.request\s+import\s+urlopen\b[\s\S]*\burlopen\s*\(',
      ),
      RegExp(
        r"""\brequire\(\s*['"](net|tls|dgram)['"]\s*\)\.(connect|createserver|createconnection)\b""",
      ),
      RegExp(
        r'\b(net\.connect\s*\(|net\.createconnection\s*\(|tls\.connect\s*\(|dgram\.createsocket\s*\()',
      ),
    ];
    return patterns.any((pattern) => pattern.hasMatch(command));
  }

  static bool _looksLikePackageNetworkAccess(String command) {
    final patterns = <RegExp>[
      RegExp(
        r'(^|\s)(npm|pnpm|yarn|bun)\s+(install|add|update|upgrade|ci|create)\b',
      ),
      RegExp(r'(^|\s)(npx|pnpm\s+dlx|yarn\s+dlx|bunx)\b'),
      RegExp(r'(^|\s)(pip|pip3|pipx)\s+install\b'),
      RegExp(r'(^|\s)(python|python3|py)\s+-m\s+pip\s+install\b'),
      RegExp(r'(^|\s)uv\s+pip\s+install\b'),
      RegExp(r'(^|\s)uvx\b'),
      RegExp(r'(^|\s)poetry\s+(add|install|update)\b'),
      RegExp(r'(^|\s)(bundle|gem|composer)\s+(install|update|require)\b'),
      RegExp(r'(^|\s)cargo\s+(install|fetch|update)\b'),
      RegExp(r'(^|\s)go\s+(get|install)\b'),
      RegExp(r'(^|\s)go\s+mod\s+download\b'),
      RegExp(r'(^|\s)brew\s+(install|update|upgrade)\b'),
      RegExp(r'(^|\s)(flutter|dart)\s+pub\s+(get|add|upgrade)\b'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(command));
  }

  static bool _looksLikeCloudAuthAccess(String command) {
    return RegExp(
      r'(^|\s)(firebase|gh|gcloud|aws|az|vercel|netlify|flyctl|railway|render|doppler|vault)\s+([^\n]*\s)?(login|auth\s+login|sso\s+login)\b',
    ).hasMatch(command);
  }

  static bool _looksLikeCloudDeployAccess(String command) {
    if (RegExp(
      r'(^|\s)(firebase|vercel|netlify|flyctl|railway|render|gcloud|aws|az|kubectl|helm|gh)\s+([^\n]*\s)?(deploy|apply|sync|publish|release|workflow\s+run|run\s+deploy|functions:deploy|hosting:deploy|push|upload)\b',
    ).hasMatch(command)) {
      return true;
    }
    return RegExp(
      r'(^|\s)(npm|pnpm|yarn|bun)\s+(run\s+)?(deploy|publish|release|upload|sync)\b',
    ).hasMatch(command);
  }

  static Iterable<String> _networkTargetCandidates(String command) sync* {
    final urlPattern = RegExp(
      r"""\b(?:https?|wss?|ftp)://[^\s'"<>]+""",
      caseSensitive: false,
    );
    for (final match in urlPattern.allMatches(command)) {
      final value = match.group(0);
      if (value != null && value.isNotEmpty) yield value;
    }

    final hostPattern = RegExp(
      r'\b(localhost(?:\.localdomain)?|(?:\d{1,3}\.){3}\d{1,3}|0x[0-9a-f]+(?:\.[0-9a-fx]+)*|0[0-7]+(?:\.[0-7]+)*|\[(?:::1|fe80:[^\]]+|fd[0-9a-f]{2}:[^\]]+)\]|[a-z0-9-]+\.(?:local|internal|lan))\b',
      caseSensitive: false,
    );
    for (final match in hostPattern.allMatches(command)) {
      final value = match.group(0);
      if (value != null && value.isNotEmpty) yield value;
    }
  }

  static String _normalizeNetworkTarget(String target) {
    final trimmed = target.trim().replaceAll(RegExp(r'''[.,;:]+$'''), '');
    final uri = Uri.tryParse(trimmed);
    final parsedHost = uri?.host;
    var host = parsedHost == null || parsedHost.isEmpty
        ? trimmed.toLowerCase()
        : parsedHost.toLowerCase();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    return host;
  }

  static String? _blockedNetworkTargetReason(String host) {
    if (host == 'localhost' ||
        host == 'localhost.localdomain' ||
        host.endsWith('.localhost')) {
      return 'localhost network targets are blocked';
    }
    if (host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.lan')) {
      return 'private network hostnames are blocked';
    }
    if (_looksLikeAmbiguousIpv4Alias(host)) {
      return 'ambiguous numeric IPv4 network targets are blocked';
    }
    final ipv4Reason = _blockedIpv4Reason(host);
    if (ipv4Reason != null) return ipv4Reason;
    final ipv6Reason = _blockedIpv6Reason(host);
    if (ipv6Reason != null) return ipv6Reason;
    return null;
  }

  static bool _looksLikeAmbiguousIpv4Alias(String host) {
    if (RegExp(r'^0x[0-9a-f]+$', caseSensitive: false).hasMatch(host)) {
      return true;
    }
    if (RegExp(r'^0[0-7]+$').hasMatch(host) && host.length > 1) return true;
    if (RegExp(r'^\d+$').hasMatch(host)) return true;
    return host
        .split('.')
        .any(
          (part) =>
              part.startsWith('0x') ||
              (part.length > 1 &&
                  part.startsWith('0') &&
                  RegExp(r'^[0-7]+$').hasMatch(part)),
        );
  }

  static String? _blockedIpv4Reason(String host) {
    final match = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    ).firstMatch(host);
    if (match == null) return null;
    final octets = [
      for (var i = 1; i <= 4; i++) int.tryParse(match.group(i) ?? ''),
    ];
    if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
      return 'invalid IPv4 network targets are blocked';
    }
    final first = octets[0]!;
    final second = octets[1]!;
    if (first == 0) return 'unspecified IPv4 network targets are blocked';
    if (first == 10) return 'private IPv4 network targets are blocked';
    if (first == 127) return 'loopback IPv4 network targets are blocked';
    if (first == 169 && second == 254) {
      return 'link-local IPv4 network targets are blocked';
    }
    if (first == 172 && second >= 16 && second <= 31) {
      return 'private IPv4 network targets are blocked';
    }
    if (first == 192 && second == 168) {
      return 'private IPv4 network targets are blocked';
    }
    if (first >= 224) {
      return 'multicast/reserved IPv4 network targets are blocked';
    }
    return null;
  }

  static String? _blockedIpv6Reason(String host) {
    final normalized = host.toLowerCase();
    if (normalized == '::1') return 'loopback IPv6 network targets are blocked';
    if (normalized.startsWith('fe80:')) {
      return 'link-local IPv6 network targets are blocked';
    }
    if (RegExp(r'^f[c-d][0-9a-f]{2}:').hasMatch(normalized)) {
      return 'private IPv6 network targets are blocked';
    }
    return null;
  }

  static bool _looksLikeCommandFileAccess(String command) {
    final lower = command.toLowerCase();
    return RegExp(
          r'''(^|[\s|;&'"`(])(?:cat|less|more|head|tail|grep|rg|sed|awk|perl|ls|find|stat|du|python|python3|node|ruby|php|git|cp|mv|rm|touch|chmod|chown|tar|zip|unzip|pytest|dart|flutter|npm|pnpm|yarn|bun|cargo|go)\b''',
        ).hasMatch(lower) ||
        RegExp(
          r'''(^|[\s|;&'"`(])/(?:usr/bin|bin|usr/local/bin|opt/homebrew/bin)/(?:cat|less|more|head|tail|grep|rg|sed|awk|perl|ls|find|stat|du|python|python3|node|ruby|php|git|cp|mv|rm|touch|chmod|chown|tar|zip|unzip|pytest|dart|flutter|npm|pnpm|yarn|bun|cargo|go)\b''',
        ).hasMatch(lower) ||
        RegExp(
          r'\b(?:open\s*\(|readfilesync\s*\(|read_text\s*\(|readbytes\s*\(|file_get_contents\s*\()',
        ).hasMatch(lower);
  }

  static Iterable<String> _absolutePathCandidates(String command) sync* {
    final pathPattern = RegExp(r'''/(?:[^\s'"`|;&<>),\]]+)''');
    for (final match in pathPattern.allMatches(command)) {
      if (match.start > 0 && command[match.start - 1] == ':') continue;
      if (match.start > 0 &&
          !RegExp(r'''[\s'"`|;&<>()\[]''').hasMatch(command[match.start - 1])) {
        continue;
      }
      final candidate = _cleanCommandPathCandidate(match.group(0) ?? '');
      if (candidate.isEmpty) continue;
      if (candidate.startsWith('//')) continue;
      if (candidate.startsWith('/usr/bin/') ||
          candidate.startsWith('/bin/') ||
          candidate.startsWith('/usr/local/bin/') ||
          candidate.startsWith('/opt/homebrew/bin/')) {
        continue;
      }
      yield candidate;
    }
  }

  static Iterable<String> _homePathCandidates(String command) sync* {
    final pathPattern = RegExp(
      r'''(?:^|[\s'"(=])((?:~|~[A-Za-z0-9._-]+)(?:/|\\)[^\s'"`|;&<>),\]]*)''',
    );
    for (final match in pathPattern.allMatches(command)) {
      final candidate = _cleanCommandPathCandidate(match.group(1) ?? '');
      if (candidate.isNotEmpty) yield candidate;
    }
  }

  static Iterable<String> _environmentPathCandidates(String command) sync* {
    final pathPattern = RegExp(
      r'''(?:^|[\s'"(=])((?:\$[A-Za-z_][A-Za-z0-9_]*|\$\{[A-Za-z_][A-Za-z0-9_]*\})(?:/|\\)[^\s'"`|;&<>),\]]*)''',
      caseSensitive: false,
    );
    for (final match in pathPattern.allMatches(command)) {
      final candidate = _cleanCommandPathCandidate(match.group(1) ?? '');
      if (candidate.isNotEmpty) yield candidate;
    }
  }

  static Iterable<String> _parentTraversalPathCandidates(String command) sync* {
    final pathPattern = RegExp(
      r'''(?:^|[\s'"(=])((?:\.\./|\./\.\./)[^\s'"`|;&<>),\]]+)''',
    );
    for (final match in pathPattern.allMatches(command)) {
      final candidate = _cleanCommandPathCandidate(match.group(1) ?? '');
      if (candidate.isNotEmpty) yield candidate;
    }
  }

  static String _cleanCommandPathCandidate(String candidate) {
    return candidate.trim().replaceAll(RegExp(r'''[.,:]+$'''), '');
  }

  static bool _looksLikeShellExpandedPath(String sanitizedPath) {
    final lower = sanitizedPath.toLowerCase();
    return sanitizedPath.startsWith('~/') ||
        RegExp(r'^~[A-Za-z0-9._-]+/').hasMatch(sanitizedPath) ||
        RegExp(r'^\$[A-Za-z_][A-Za-z0-9_]*/').hasMatch(sanitizedPath) ||
        RegExp(r'^\$\{[A-Za-z_][A-Za-z0-9_]*\}/').hasMatch(sanitizedPath) ||
        lower.startsWith(r'$home/') ||
        lower.startsWith(r'${home}/') ||
        lower.startsWith(r'$userprofile/') ||
        lower.startsWith(r'${userprofile}/') ||
        lower.startsWith(r'$tmpdir/') ||
        lower.startsWith(r'${tmpdir}/') ||
        lower.startsWith(r'$tmp/') ||
        lower.startsWith(r'${tmp}/') ||
        lower.startsWith(r'$temp/') ||
        lower.startsWith(r'${temp}/') ||
        lower.startsWith(r'$xdg_config_home/') ||
        lower.startsWith(r'${xdg_config_home}/');
  }

  static bool _looksLikeWindowsAbsolutePath(String sanitizedPath) {
    return RegExp(r'^[A-Za-z]:/').hasMatch(sanitizedPath) ||
        sanitizedPath.startsWith('//');
  }

  static String? _unsafeShellSyntax(String command) {
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var escaped = false;
    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
        continue;
      }
      if (char == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
        continue;
      }
      if (inSingleQuote || inDoubleQuote) continue;
      if (char == '\n' || char == '\r') {
        return 'Multiple shell commands are blocked';
      }
      if (char == ';') {
        return 'Command separators are blocked';
      }
      if (char == '|' || char == '&') {
        return 'Shell control operators are blocked';
      }
      if (char == '<' || char == '>') {
        return 'Shell redirection is blocked';
      }
    }
    return null;
  }

  /// Get all matching dangers (for detailed warnings)
  static List<String> allDangers(String command) {
    final dangers = <String>[];
    final unsafeSyntax = _unsafeShellSyntax(command);
    if (unsafeSyntax != null) dangers.add(unsafeSyntax);
    for (final entry in _dangerousPatterns.entries) {
      if (entry.key.hasMatch(command)) {
        dangers.add(entry.value);
      }
    }
    return dangers;
  }
}
