import 'dart:io';

import 'package:path/path.dart' as p;

class SmartError {
  static String fileNotFound(String path, String workingDir) {
    final dir = Directory(p.dirname(p.join(workingDir, path)));
    final suggestions = <String>[];

    try {
      if (dir.existsSync()) {
        final fileName = p.basename(path).toLowerCase();
        for (final entity in dir.listSync()) {
          final name = p.basename(entity.path).toLowerCase();
          if (_similarity(name, fileName) > 0.5) {
            suggestions.add(p.relative(entity.path, from: workingDir));
          }
        }
      }
    } catch (_) {}

    final msg = StringBuffer('File not found: $path');
    if (suggestions.isNotEmpty) {
      msg.write('\n\nDid you mean one of these?\n');
      for (final s in suggestions.take(5)) {
        msg.write('  - $s\n');
      }
    }
    return msg.toString();
  }

  static String textNotFound(String path, String searchText, String fileContent) {
    final preview =
        searchText.length > 60 ? '${searchText.substring(0, 60)}...' : searchText;
    final msg = StringBuffer('Text not found in $path: "$preview"');

    // Try to find similar text
    final searchLower = searchText.toLowerCase().trim();
    final lines = fileContent.split('\n');
    final similar = <String>[];

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().contains(
          searchLower.substring(0, (searchLower.length * 0.5).ceil().clamp(1, 30)))) {
        similar.add('  Line ${i + 1}: ${lines[i].trimRight()}');
      }
    }

    if (similar.isNotEmpty) {
      msg.write('\n\nSimilar text found:\n');
      for (final s in similar.take(3)) {
        msg.write('$s\n');
      }
    }
    return msg.toString();
  }

  static String gitError(String operation, String output) {
    final msg = StringBuffer('Git $operation failed');

    if (output.contains('not a git repository')) {
      msg.write(': Not a git repository. Run "git init" first.');
    } else if (output.contains('nothing to commit')) {
      msg.write(': No changes to commit.');
    } else if (output.contains('merge conflict')) {
      msg.write(': Merge conflicts detected. Resolve conflicts first.');
    } else if (output.contains('detached HEAD')) {
      msg.write(': HEAD is detached. Create or switch to a branch first.');
    } else {
      msg.write(':\n$output');
    }

    return msg.toString();
  }

  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final longer = a.length > b.length ? a : b;
    final shorter = a.length > b.length ? b : a;

    int matches = 0;
    for (int i = 0; i < shorter.length; i++) {
      if (i < longer.length && shorter[i] == longer[i]) {
        matches++;
      }
    }
    return matches / longer.length;
  }
}
