enum VulnerabilityType {
  sqlInjection,
  xss,
  commandInjection,
  pathTraversal,
  insecureCrypto,
  hardcodedSecret,
  insecureDeserialization,
  openRedirect,
  missingAuth,
  insecureRandom,
}

extension VulnerabilityTypeExt on VulnerabilityType {
  String get displayName => switch (this) {
    VulnerabilityType.sqlInjection => 'SQL Injection',
    VulnerabilityType.xss => 'Cross-Site Scripting (XSS)',
    VulnerabilityType.commandInjection => 'Command Injection',
    VulnerabilityType.pathTraversal => 'Path Traversal',
    VulnerabilityType.insecureCrypto => 'Insecure Cryptography',
    VulnerabilityType.hardcodedSecret => 'Hardcoded Secret',
    VulnerabilityType.insecureDeserialization => 'Insecure Deserialization',
    VulnerabilityType.openRedirect => 'Open Redirect',
    VulnerabilityType.missingAuth => 'Missing Authentication',
    VulnerabilityType.insecureRandom => 'Insecure Randomness',
  };

  String get icon => switch (this) {
    VulnerabilityType.sqlInjection => 'database',
    VulnerabilityType.xss => 'web',
    VulnerabilityType.commandInjection => 'terminal',
    VulnerabilityType.pathTraversal => 'folder',
    VulnerabilityType.insecureCrypto => 'lock',
    VulnerabilityType.hardcodedSecret => 'key',
    VulnerabilityType.insecureDeserialization => 'data',
    VulnerabilityType.openRedirect => 'redirect',
    VulnerabilityType.missingAuth => 'shield',
    VulnerabilityType.insecureRandom => 'shuffle',
  };
}

class SecurityFinding {
  final VulnerabilityType type;
  final String severity; // critical, high, medium, low
  final String filePath;
  final int line;
  final String preview;
  final String description;
  final String recommendation;

  const SecurityFinding({
    required this.type,
    required this.severity,
    required this.filePath,
    required this.line,
    required this.preview,
    required this.description,
    required this.recommendation,
  });

  int get severityOrder => switch (severity) {
    'critical' => 0,
    'high' => 1,
    'medium' => 2,
    'low' => 3,
    _ => 4,
  };
}

class ScanResult {
  final List<SecurityFinding> findings;
  final int filesScanned;
  final Duration scanDuration;
  final DateTime timestamp;

  const ScanResult({
    required this.findings,
    required this.filesScanned,
    required this.scanDuration,
    required this.timestamp,
  });

  int get criticalCount =>
      findings.where((f) => f.severity == 'critical').length;
  int get highCount => findings.where((f) => f.severity == 'high').length;
  int get mediumCount => findings.where((f) => f.severity == 'medium').length;
  int get lowCount => findings.where((f) => f.severity == 'low').length;
}
