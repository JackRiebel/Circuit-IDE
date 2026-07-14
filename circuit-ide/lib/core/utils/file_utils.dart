import 'dart:io';

import 'package:path/path.dart' as p;

class FileUtils {
  static String getLanguageFromPath(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return _extensionToLanguage[ext] ?? 'plaintext';
  }

  static const _extensionToLanguage = {
    '.dart': 'dart',
    '.py': 'python',
    '.js': 'javascript',
    '.jsx': 'javascript',
    '.ts': 'typescript',
    '.tsx': 'typescript',
    '.html': 'html',
    '.htm': 'html',
    '.css': 'css',
    '.scss': 'scss',
    '.json': 'json',
    '.yaml': 'yaml',
    '.yml': 'yaml',
    '.xml': 'xml',
    '.md': 'markdown',
    '.sh': 'bash',
    '.bash': 'bash',
    '.zsh': 'bash',
    '.rs': 'rust',
    '.go': 'go',
    '.java': 'java',
    '.kt': 'kotlin',
    '.swift': 'swift',
    '.c': 'c',
    '.cpp': 'cpp',
    '.h': 'c',
    '.hpp': 'cpp',
    '.rb': 'ruby',
    '.php': 'php',
    '.sql': 'sql',
    '.r': 'r',
    '.lua': 'lua',
    '.toml': 'toml',
    '.ini': 'ini',
    '.cfg': 'ini',
    '.dockerfile': 'dockerfile',
    '.gradle': 'groovy',
    '.ps1': 'powershell',
    '.bat': 'batch',
    '.cmd': 'batch',
  };

  static bool isBinaryFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return _binaryExtensions.contains(ext);
  }

  static const _binaryExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.bmp',
    '.ico',
    '.webp',
    '.mp3',
    '.mp4',
    '.avi',
    '.mov',
    '.wav',
    '.flac',
    '.zip',
    '.tar',
    '.gz',
    '.bz2',
    '.7z',
    '.rar',
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.exe',
    '.dll',
    '.so',
    '.dylib',
    '.o',
    '.class',
    '.pyc',
    '.pyo',
    '.woff',
    '.woff2',
    '.ttf',
    '.otf',
    '.eot',
  };

  static String safePath(String basePath, String relativePath) {
    final normalized = p.normalize(p.join(basePath, relativePath));
    if (!p.isWithin(basePath, normalized) && normalized != basePath) {
      throw ArgumentError('Path traversal detected: $relativePath');
    }
    return normalized;
  }

  static Future<bool> exists(String path) async {
    final type = await FileSystemEntity.type(path);
    return type != FileSystemEntityType.notFound;
  }

  static String humanFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
