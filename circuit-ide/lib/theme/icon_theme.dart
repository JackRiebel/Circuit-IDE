import 'package:flutter/material.dart';

class FileIconTheme {
  static IconData getIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    final name = fileName.toLowerCase();

    // Special filenames
    if (name == 'pubspec.yaml' || name == 'pubspec.yml') {
      return Icons.flutter_dash;
    }
    if (name == 'dockerfile' || name.startsWith('docker')) {
      return Icons.directions_boat;
    }
    if (name == '.gitignore' || name == '.gitmodules') {
      return Icons.source;
    }
    if (name == 'readme.md') return Icons.description;
    if (name == 'license') return Icons.gavel;

    return _extensionIcons[ext] ?? Icons.insert_drive_file;
  }

  static Color getColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return _extensionColors[ext] ?? const Color(0xFF8B949E);
  }

  static const _extensionIcons = {
    'dart': Icons.flutter_dash,
    'py': Icons.code,
    'js': Icons.javascript,
    'jsx': Icons.javascript,
    'ts': Icons.code,
    'tsx': Icons.code,
    'html': Icons.html,
    'css': Icons.css,
    'json': Icons.data_object,
    'yaml': Icons.settings,
    'yml': Icons.settings,
    'md': Icons.description,
    'txt': Icons.text_snippet,
    'sh': Icons.terminal,
    'bash': Icons.terminal,
    'xml': Icons.code,
    'svg': Icons.image,
    'png': Icons.image,
    'jpg': Icons.image,
    'jpeg': Icons.image,
    'gif': Icons.gif,
    'pdf': Icons.picture_as_pdf,
    'zip': Icons.archive,
    'tar': Icons.archive,
    'gz': Icons.archive,
    'sql': Icons.storage,
    'go': Icons.code,
    'rs': Icons.code,
    'java': Icons.coffee,
    'kt': Icons.code,
    'swift': Icons.code,
    'c': Icons.code,
    'cpp': Icons.code,
    'h': Icons.code,
    'rb': Icons.diamond,
    'php': Icons.code,
    'toml': Icons.settings,
    'ini': Icons.settings,
    'cfg': Icons.settings,
    'env': Icons.vpn_key,
    'lock': Icons.lock,
    'log': Icons.list_alt,
  };

  static const _extensionColors = {
    'dart': Color(0xFF02569B),
    'py': Color(0xFF3572A5),
    'js': Color(0xFFF7DF1E),
    'jsx': Color(0xFF61DAFB),
    'ts': Color(0xFF3178C6),
    'tsx': Color(0xFF3178C6),
    'html': Color(0xFFE34C26),
    'css': Color(0xFF563D7C),
    'json': Color(0xFFA0A0A0),
    'yaml': Color(0xFFCB171E),
    'yml': Color(0xFFCB171E),
    'md': Color(0xFF083FA1),
    'sh': Color(0xFF89E051),
    'go': Color(0xFF00ADD8),
    'rs': Color(0xFFDEA584),
    'java': Color(0xFFB07219),
    'kt': Color(0xFF7F52FF),
    'swift': Color(0xFFF05138),
    'c': Color(0xFF555555),
    'cpp': Color(0xFFF34B7D),
    'rb': Color(0xFF701516),
    'php': Color(0xFF4F5D95),
    'sql': Color(0xFFE38C00),
  };
}
