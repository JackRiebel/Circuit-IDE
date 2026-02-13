import 'dart:developer' as developer;

enum LogLevel { debug, info, warning, error }

class Logger {
  static LogLevel minLevel = LogLevel.debug;

  static void debug(String message, [String? tag]) {
    _log(LogLevel.debug, message, tag);
  }

  static void info(String message, [String? tag]) {
    _log(LogLevel.info, message, tag);
  }

  static void warning(String message, [String? tag]) {
    _log(LogLevel.warning, message, tag);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, null, error, stackTrace);
  }

  static void _log(
    LogLevel level,
    String message, [
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < minLevel.index) return;

    final prefix = switch (level) {
      LogLevel.debug => '[DEBUG]',
      LogLevel.info => '[INFO]',
      LogLevel.warning => '[WARN]',
      LogLevel.error => '[ERROR]',
    };

    final tagStr = tag != null ? '[$tag] ' : '';
    developer.log(
      '$prefix $tagStr$message',
      error: error,
      stackTrace: stackTrace,
      name: 'CircuitIDE',
    );
  }
}
