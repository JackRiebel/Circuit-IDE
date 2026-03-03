import 'rules_loader.dart';

class SmartRulesMatcher {
  /// Filter rules to only those matching the given file path.
  /// Rules without patterns are always included.
  static List<ProjectRule> filterRules(
    List<ProjectRule> rules,
    String? activeFilePath,
  ) {
    if (activeFilePath == null) return rules;

    return rules.where((rule) {
      // Rules with no patterns are always active
      if (rule.patterns.isEmpty) return true;

      // Check if any pattern matches the active file
      return rule.patterns.any((p) => matchesPattern(activeFilePath, p));
    }).toList();
  }

  /// Check if a file path matches a glob pattern.
  /// Supports: `*` (any filename chars), `**` (any path segments), `?` (single char).
  static bool matchesPattern(String filePath, String pattern) {
    // Normalize separators
    final normalizedPath = filePath.replaceAll('\\', '/');
    final normalizedPattern = pattern.replaceAll('\\', '/');

    // Convert glob to regex
    final regexStr = _globToRegex(normalizedPattern);
    try {
      final regex = RegExp('^$regexStr\$');
      return regex.hasMatch(normalizedPath);
    } catch (_) {
      return false;
    }
  }

  static String _globToRegex(String glob) {
    final buffer = StringBuffer();
    final chars = glob.split('');

    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      switch (c) {
        case '*':
          if (i + 1 < chars.length && chars[i + 1] == '*') {
            // ** — match any path segments
            i++;
            // Skip trailing /
            if (i + 1 < chars.length && chars[i + 1] == '/') {
              i++;
            }
            buffer.write('.*');
          } else {
            // * — match any chars except /
            buffer.write('[^/]*');
          }
          break;
        case '?':
          buffer.write('[^/]');
          break;
        case '.':
          buffer.write(r'\.');
          break;
        case '{':
          buffer.write('(');
          break;
        case '}':
          buffer.write(')');
          break;
        case ',':
          // Inside braces, comma becomes |
          buffer.write('|');
          break;
        default:
          if (RegExp(r'[\\^$+\[\]|()]').hasMatch(c)) {
            buffer.write('\\$c');
          } else {
            buffer.write(c);
          }
      }
    }

    return buffer.toString();
  }
}
