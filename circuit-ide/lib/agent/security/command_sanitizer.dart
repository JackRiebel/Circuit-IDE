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

    // Secret/environment file access
    RegExp(
      r'(^|\s)(cat|less|more|head|tail|grep|rg|sed|awk|perl)\s+[^\n]*(\.env\b|\.env\.|secret|credentials|\.npmrc\b|\.netrc\b|id_rsa\b|id_ed25519\b|\.aws/|aws/credentials)',
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
  };

  /// Check if a command matches any dangerous patterns.
  /// Returns description of the danger, or null if safe.
  static String? checkDangerous(String command) {
    for (final entry in _dangerousPatterns.entries) {
      if (entry.key.hasMatch(command)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Get all matching dangers (for detailed warnings)
  static List<String> allDangers(String command) {
    final dangers = <String>[];
    for (final entry in _dangerousPatterns.entries) {
      if (entry.key.hasMatch(command)) {
        dangers.add(entry.value);
      }
    }
    return dangers;
  }
}
