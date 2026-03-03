import 'package:path/path.dart' as p;

import '../models/test_generation_models.dart';

class TestGeneratorService {
  /// Auto-detect the test framework from the file language/extension.
  static TestFramework detectFramework(String language) {
    return switch (language) {
      'dart' => TestFramework.dartTest,
      'python' => TestFramework.pytest,
      'javascript' => TestFramework.jest,
      'typescript' => TestFramework.jest,
      'go' => TestFramework.goTest,
      'rust' => TestFramework.rustTest,
      _ => TestFramework.jest,
    };
  }

  /// Derive the test file path from the source path using conventions.
  static String deriveTestPath(String sourcePath, String language) {
    final dir = p.dirname(sourcePath);
    final baseName = p.basenameWithoutExtension(sourcePath);
    final ext = p.extension(sourcePath);

    return switch (language) {
      'dart' => () {
          // lib/foo.dart → test/foo_test.dart
          final testPath = dir.replaceFirst('lib', 'test');
          return p.join(testPath, '${baseName}_test$ext');
        }(),
      'python' => () {
          // src/foo.py → tests/test_foo.py
          final testPath = dir.replaceFirst('src', 'tests');
          return p.join(testPath, 'test_$baseName$ext');
        }(),
      'javascript' || 'typescript' => () {
          // src/foo.ts → src/__tests__/foo.test.ts
          return p.join(dir, '__tests__', '$baseName.test$ext');
        }(),
      'go' => () {
          // foo.go → foo_test.go
          return p.join(dir, '${baseName}_test$ext');
        }(),
      'rust' => () {
          // src/foo.rs → tests/foo_test.rs
          return p.join(p.dirname(dir), 'tests', '${baseName}_test$ext');
        }(),
      _ => p.join(dir, '${baseName}_test$ext'),
    };
  }

  /// Build a comprehensive test generation prompt.
  static String buildPrompt(TestGenerationRequest request) {
    final frameworkInstructions = switch (request.framework) {
      TestFramework.dartTest => '''Use the `test` package with `group()` and `test()`.
Import `package:test/test.dart`.
Use `expect()` with matchers like `equals`, `isTrue`, `throwsA`, etc.''',
      TestFramework.pytest => '''Use pytest conventions.
Use `def test_` function naming.
Use `assert` statements and pytest fixtures where appropriate.''',
      TestFramework.jest => '''Use Jest with `describe()` and `it()`.
Use `expect().toBe()`, `toEqual()`, `toThrow()`, etc.
Use `jest.fn()` for mocks if needed.''',
      TestFramework.mocha => '''Use Mocha with `describe()` and `it()`.
Use Chai's `expect` for assertions.''',
      TestFramework.goTest => '''Use the `testing` package.
Use `func Test` naming convention.
Use `t.Error()`, `t.Fatal()`, etc.''',
      TestFramework.rustTest => '''Use `#[cfg(test)]` module with `#[test]` attribute.
Use `assert!`, `assert_eq!`, `assert_ne!` macros.''',
    };

    final buffer = StringBuffer();
    buffer.writeln(
        'Generate comprehensive tests for the following source file.\n');
    buffer.writeln('File: ${p.basename(request.sourceFilePath)}');
    buffer.writeln('Language: ${request.language}');
    buffer.writeln('Framework: ${request.framework.displayName}\n');
    buffer.writeln('Framework-specific instructions:');
    buffer.writeln(frameworkInstructions);
    buffer.writeln();

    if (request.includeEdgeCases) {
      buffer.writeln(
          'Include edge case tests (null/empty inputs, boundary values, error conditions).');
    }
    if (request.includeMocks) {
      buffer.writeln(
          'Include mocks/stubs for external dependencies where appropriate.');
    }

    buffer.writeln(
        '\nSource code:\n```${request.language}\n${request.sourceContent}\n```');
    buffer.writeln(
        '\nGenerate the complete test file. Return ONLY the test code, no markdown fences, no explanation.');

    return buffer.toString();
  }

  /// Parse the AI response, stripping markdown fences if present.
  static String parseResponse(String response) {
    var cleaned = response.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```\w*\n?'), '')
          .replaceFirst(RegExp(r'\n?```$'), '');
    }
    return cleaned;
  }

  /// Count the number of test functions/cases in generated code.
  static int countTests(String testContent, TestFramework framework) {
    final pattern = switch (framework) {
      TestFramework.dartTest => RegExp(r'test\(|testWidgets\('),
      TestFramework.pytest => RegExp(r'def test_'),
      TestFramework.jest || TestFramework.mocha => RegExp(r'it\(|test\('),
      TestFramework.goTest => RegExp(r'func Test'),
      TestFramework.rustTest => RegExp(r'#\[test\]'),
    };
    return pattern.allMatches(testContent).length;
  }
}
