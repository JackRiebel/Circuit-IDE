class AppConstants {
  // Agent
  static const int maxToolCallIterations = 6;
  static const int commandTimeoutDefault = 60;
  static const int commandTimeoutMin = 5;
  static const int commandTimeoutMax = 300;
  static const int commandOutputMaxBytes = 1024 * 1024;
  static const int maxFileReadLines = 500;
  static const int maxSearchResults = 50;
  static const int maxListFiles = 100;

  // Context
  static const int defaultContextWindow = 120000;
  static const int reserveTokens = 10000;
  static const double charsPerToken = 4.0;

  // UI
  static const int completionDebounceMs = 300;
  static const int searchDebounceMs = 200;
  static const int fileWatcherDebounceMs = 500;

  // App
  static const String appName = 'Circuit IDE';
  static const String appVersion = '1.0.0';
  static const String configDirName = '.circuit-ide';
  static const String configFileName = 'config.json';
  static const String sessionsDirName = 'sessions';
  static const String auditDirName = 'audit';
  static const String pluginsDirName = 'plugins';

  // Cisco API
  static const String ciscoTokenUrl =
      'https://id.cisco.com/oauth2/default/v1/token';
  static const String ciscoChatBaseUrl =
      'https://chat-ai.cisco.com/openai/deployments';
  static const String ciscoApiVersion = '2025-04-01-preview';
}
