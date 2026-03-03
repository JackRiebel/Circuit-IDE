enum TestFramework {
  dartTest('Dart Test', 'dart'),
  pytest('pytest', 'py'),
  jest('Jest', 'js'),
  mocha('Mocha', 'js'),
  goTest('Go Test', 'go'),
  rustTest('Rust Test', 'rs');

  const TestFramework(this.displayName, this.ext);
  final String displayName;
  final String ext;
}

class TestGenerationRequest {
  final String sourceFilePath;
  final String sourceContent;
  final String language;
  final TestFramework framework;
  final bool includeEdgeCases;
  final bool includeMocks;

  const TestGenerationRequest({
    required this.sourceFilePath,
    required this.sourceContent,
    required this.language,
    required this.framework,
    this.includeEdgeCases = true,
    this.includeMocks = true,
  });
}

class TestGenerationResult {
  final String testFilePath;
  final String testContent;
  final int testCount;
  final String summary;
  final bool isGenerating;
  final String? error;

  const TestGenerationResult({
    required this.testFilePath,
    required this.testContent,
    required this.testCount,
    required this.summary,
    this.isGenerating = false,
    this.error,
  });
}
