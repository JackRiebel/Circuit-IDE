class CommandSanitizer {
  static final _dangerousPatterns = <RegExp, String>{
    // File destruction
    RegExp(r'\brm\s+(-[a-zA-Z]*r[a-zA-Z]*\s+|.*-rf\s+)/'):
        'Recursive removal of root directory',
    RegExp(r'\brm\s+-[a-zA-Z]*r[a-zA-Z]*f'):
        'Force recursive file deletion',
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
    RegExp(r'\bgit\s+push\s+--force\b'): 'Force push (may overwrite history)',
    RegExp(r'\bgit\s+reset\s+--hard\b'): 'Hard reset (discards changes)',

    // Code execution from internet
    RegExp(r'\bcurl\s+.*\|\s*(ba)?sh\b'):
        'Piping remote content to shell',
    RegExp(r'\bwget\s+.*\|\s*(ba)?sh\b'):
        'Piping remote content to shell',

    // Reverse shells
    RegExp(r'/dev/tcp/'): 'Network device access (possible reverse shell)',
    RegExp(r'\bnc\s+-[a-zA-Z]*l'):
        'Netcat listener (possible reverse shell)',
    RegExp(r'\bbash\s+-i\s+>&\s*/dev/tcp'):
        'Bash reverse shell',

    // Dangerous redirects
    RegExp(r'>\s*/dev/null\s+2>&1\s*&'):
        'Background process hiding output',

    // Command injection patterns
    RegExp(r'\$\([^)]+\)'): 'Command substitution',
    RegExp(r'`[^`]+`'): 'Backtick command substitution',
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
