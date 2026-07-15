import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/vericoding_models.dart';

const _uuid = Uuid();

/// Detected project type.
enum ProjectType {
  flutter('Flutter'),
  dart('Dart'),
  node('Node.js'),
  typescript('TypeScript'),
  python('Python'),
  rust('Rust'),
  go('Go'),
  java('Java'),
  kotlin('Kotlin'),
  csharp('C#/.NET'),
  ruby('Ruby'),
  swift('Swift'),
  cpp('C/C++'),
  unknown('Unknown');

  final String label;
  const ProjectType(this.label);
}

/// Result of scanning a project directory.
class ProjectDetectionResult {
  final ProjectType primaryType;
  final Set<ProjectType> allTypes;
  final List<VericodeCheck> suggestedChecks;
  final Map<String, bool> detectedFeatures;

  const ProjectDetectionResult({
    required this.primaryType,
    required this.allTypes,
    required this.suggestedChecks,
    required this.detectedFeatures,
  });
}

/// Scans a project directory and detects the project type, testing frameworks,
/// linters, and formatters to suggest appropriate verification checks.
class ProjectDetector {
  final String rootPath;

  ProjectDetector({required this.rootPath});

  Future<ProjectDetectionResult> detect() async {
    final types = <ProjectType>{};
    final features = <String, bool>{};
    final checks = <VericodeCheck>[];
    int order = 0;

    // ── Dart / Flutter ──────────────────────────────────────────────
    final pubspec = File(p.join(rootPath, 'pubspec.yaml'));
    if (await pubspec.exists()) {
      final content = await pubspec.readAsString();
      final isFlutter =
          content.contains('flutter:') &&
          (content.contains('sdk: flutter') ||
              content.contains('flutter/flutter'));

      if (isFlutter) {
        types.add(ProjectType.flutter);
        features['flutter'] = true;

        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'Flutter Analyze',
            command: 'flutter analyze',
            type: VericodeCheckType.dartAnalyze,
            enabled: true,
            order: order++,
            timeoutSeconds: 90,
          ),
        );

        final testDir = Directory(p.join(rootPath, 'test'));
        final hasTests =
            await testDir.exists() &&
            await testDir.list().any((e) => e.path.endsWith('_test.dart'));
        features['tests'] = hasTests;

        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'Flutter Test',
            command: 'flutter test',
            type: VericodeCheckType.flutterTest,
            enabled: hasTests,
            order: order++,
            timeoutSeconds: 180,
          ),
        );

        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'Dart Format',
            command: 'dart format --set-exit-if-changed .',
            type: VericodeCheckType.flutterFormat,
            enabled: false,
            order: order++,
            timeoutSeconds: 30,
          ),
        );

        // Check for build_runner
        if (content.contains('build_runner')) {
          features['build_runner'] = true;
          checks.add(
            VericodeCheck(
              id: _id(),
              name: 'Build Runner',
              command:
                  'dart run build_runner build --delete-conflicting-outputs',
              type: VericodeCheckType.customCommand,
              enabled: false,
              order: order++,
              timeoutSeconds: 120,
            ),
          );
        }
      } else {
        types.add(ProjectType.dart);
        features['dart'] = true;

        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'Dart Analyze',
            command: 'dart analyze',
            type: VericodeCheckType.dartAnalyze,
            enabled: true,
            order: order++,
            timeoutSeconds: 60,
          ),
        );

        final testDir = Directory(p.join(rootPath, 'test'));
        final hasTests = await testDir.exists();
        features['tests'] = hasTests;

        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'Dart Test',
            command: 'dart test',
            type: VericodeCheckType.flutterTest,
            enabled: hasTests,
            order: order++,
            timeoutSeconds: 120,
          ),
        );

        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'Dart Format',
            command: 'dart format --set-exit-if-changed .',
            type: VericodeCheckType.flutterFormat,
            enabled: false,
            order: order++,
            timeoutSeconds: 30,
          ),
        );
      }
    }

    // ── Node.js / TypeScript ────────────────────────────────────────
    final packageJson = File(p.join(rootPath, 'package.json'));
    if (await packageJson.exists()) {
      types.add(ProjectType.node);
      features['node'] = true;

      String pkgContent = '';
      try {
        pkgContent = await packageJson.readAsString();
      } catch (_) {}

      // Check for TypeScript
      final tsConfig = File(p.join(rootPath, 'tsconfig.json'));
      final hasTs = await tsConfig.exists();
      if (hasTs) {
        types.add(ProjectType.typescript);
        features['typescript'] = true;
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'TypeScript Check',
            command: 'npx tsc --noEmit',
            type: VericodeCheckType.customCommand,
            enabled: true,
            order: order++,
            timeoutSeconds: 90,
          ),
        );
      }

      // Detect test runner
      final hasTestScript = pkgContent.contains('"test"');
      features['npm_test'] = hasTestScript;
      if (hasTestScript) {
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'npm test',
            command: 'npm test',
            type: VericodeCheckType.customCommand,
            enabled: true,
            order: order++,
            timeoutSeconds: 120,
          ),
        );
      }

      // Detect ESLint
      final hasEslint = await _anyExists([
        '.eslintrc',
        '.eslintrc.js',
        '.eslintrc.cjs',
        '.eslintrc.json',
        '.eslintrc.yml',
        'eslint.config.js',
        'eslint.config.mjs',
        'eslint.config.cjs',
      ]);
      features['eslint'] = hasEslint;
      if (hasEslint) {
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'ESLint',
            command: 'npx eslint .',
            type: VericodeCheckType.customCommand,
            enabled: true,
            order: order++,
            timeoutSeconds: 60,
          ),
        );
      }

      // Detect Prettier
      final hasPrettier = await _anyExists([
        '.prettierrc',
        '.prettierrc.js',
        '.prettierrc.json',
        '.prettierrc.yml',
        'prettier.config.js',
      ]);
      features['prettier'] = hasPrettier;
      if (hasPrettier) {
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'Prettier Check',
            command: 'npx prettier --check .',
            type: VericodeCheckType.customCommand,
            enabled: false,
            order: order++,
            timeoutSeconds: 30,
          ),
        );
      }

      // Detect package manager
      final hasYarnLock = await File(p.join(rootPath, 'yarn.lock')).exists();
      final hasPnpmLock = await File(
        p.join(rootPath, 'pnpm-lock.yaml'),
      ).exists();
      if (hasYarnLock) {
        features['yarn'] = true;
      } else if (hasPnpmLock) {
        features['pnpm'] = true;
      }
    }

    // ── Python ──────────────────────────────────────────────────────
    final hasPython = await _anyExists([
      'requirements.txt',
      'pyproject.toml',
      'setup.py',
      'setup.cfg',
      'Pipfile',
      'poetry.lock',
    ]);
    if (hasPython) {
      types.add(ProjectType.python);
      features['python'] = true;

      // Detect test framework
      final hasTestDir =
          await Directory(p.join(rootPath, 'tests')).exists() ||
          await Directory(p.join(rootPath, 'test')).exists();
      final hasPytest =
          await _anyExists(['pytest.ini', 'conftest.py']) || hasTestDir;
      features['pytest'] = hasPytest;

      if (hasPytest) {
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'pytest',
            command: 'python -m pytest',
            type: VericodeCheckType.customCommand,
            enabled: true,
            order: order++,
            timeoutSeconds: 120,
          ),
        );
      }

      // Detect linters
      final pyprojectFile = File(p.join(rootPath, 'pyproject.toml'));
      String pyContent = '';
      if (await pyprojectFile.exists()) {
        try {
          pyContent = await pyprojectFile.readAsString();
        } catch (_) {}
      }

      final hasRuff =
          pyContent.contains('[tool.ruff]') ||
          await File(p.join(rootPath, 'ruff.toml')).exists() ||
          await File(p.join(rootPath, '.ruff.toml')).exists();
      features['ruff'] = hasRuff;
      if (hasRuff) {
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'Ruff Lint',
            command: 'ruff check .',
            type: VericodeCheckType.customCommand,
            enabled: true,
            order: order++,
            timeoutSeconds: 30,
          ),
        );
      }

      final hasMypy =
          pyContent.contains('[tool.mypy]') ||
          await File(p.join(rootPath, 'mypy.ini')).exists() ||
          await File(p.join(rootPath, '.mypy.ini')).exists();
      features['mypy'] = hasMypy;
      if (hasMypy) {
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'mypy Type Check',
            command: 'python -m mypy .',
            type: VericodeCheckType.customCommand,
            enabled: true,
            order: order++,
            timeoutSeconds: 90,
          ),
        );
      }

      // Fallback: flake8 if no ruff
      if (!hasRuff) {
        final hasFlake8 =
            await _anyExists(['.flake8', 'setup.cfg']) ||
            pyContent.contains('[tool.flake8]');
        features['flake8'] = hasFlake8;
        if (hasFlake8) {
          checks.add(
            VericodeCheck(
              id: _id(),
              name: 'flake8 Lint',
              command: 'flake8 .',
              type: VericodeCheckType.customCommand,
              enabled: true,
              order: order++,
              timeoutSeconds: 30,
            ),
          );
        }
      }

      // Black / isort formatter
      final hasBlack = pyContent.contains('[tool.black]');
      features['black'] = hasBlack;
      if (hasBlack) {
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'Black Format Check',
            command: 'python -m black --check .',
            type: VericodeCheckType.customCommand,
            enabled: false,
            order: order++,
            timeoutSeconds: 30,
          ),
        );
      }
    }

    // ── Rust ────────────────────────────────────────────────────────
    final cargoToml = File(p.join(rootPath, 'Cargo.toml'));
    if (await cargoToml.exists()) {
      types.add(ProjectType.rust);
      features['rust'] = true;

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Cargo Check',
          command: 'cargo check',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 120,
        ),
      );

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Cargo Test',
          command: 'cargo test',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 180,
        ),
      );

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Clippy',
          command: 'cargo clippy -- -D warnings',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 120,
        ),
      );

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Rust Format Check',
          command: 'cargo fmt --check',
          type: VericodeCheckType.customCommand,
          enabled: false,
          order: order++,
          timeoutSeconds: 30,
        ),
      );
    }

    // ── Go ──────────────────────────────────────────────────────────
    final goMod = File(p.join(rootPath, 'go.mod'));
    if (await goMod.exists()) {
      types.add(ProjectType.go);
      features['go'] = true;

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Go Vet',
          command: 'go vet ./...',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 60,
        ),
      );

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Go Test',
          command: 'go test ./...',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 120,
        ),
      );

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Go Build',
          command: 'go build ./...',
          type: VericodeCheckType.customCommand,
          enabled: false,
          order: order++,
          timeoutSeconds: 90,
        ),
      );

      // Detect golangci-lint
      final hasGolangCiLint =
          await File(p.join(rootPath, '.golangci.yml')).exists() ||
          await File(p.join(rootPath, '.golangci.yaml')).exists();
      features['golangci-lint'] = hasGolangCiLint;
      if (hasGolangCiLint) {
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'golangci-lint',
            command: 'golangci-lint run',
            type: VericodeCheckType.customCommand,
            enabled: true,
            order: order++,
            timeoutSeconds: 90,
          ),
        );
      }
    }

    // ── Java / Kotlin (Maven) ───────────────────────────────────────
    final pomXml = File(p.join(rootPath, 'pom.xml'));
    if (await pomXml.exists()) {
      types.add(ProjectType.java);
      features['maven'] = true;

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Maven Compile',
          command: 'mvn compile -q',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 180,
        ),
      );

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Maven Test',
          command: 'mvn test -q',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 300,
        ),
      );
    }

    // ── Java / Kotlin (Gradle) ──────────────────────────────────────
    final buildGradle = File(p.join(rootPath, 'build.gradle'));
    final buildGradleKts = File(p.join(rootPath, 'build.gradle.kts'));
    if (await buildGradle.exists() || await buildGradleKts.exists()) {
      types.add(ProjectType.java);
      features['gradle'] = true;

      final gradlew = File(p.join(rootPath, 'gradlew'));
      final cmd = await gradlew.exists() ? './gradlew' : 'gradle';

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Gradle Build',
          command: '$cmd build -x test',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 180,
        ),
      );

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Gradle Test',
          command: '$cmd test',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 300,
        ),
      );
    }

    // ── .NET / C# ──────────────────────────────────────────────────
    final hasDotnet = await _anyExtension(['.sln', '.csproj', '.fsproj']);
    if (hasDotnet) {
      types.add(ProjectType.csharp);
      features['dotnet'] = true;

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'dotnet build',
          command: 'dotnet build --no-restore',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 120,
        ),
      );

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'dotnet test',
          command: 'dotnet test --no-build',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 180,
        ),
      );
    }

    // ── Ruby ────────────────────────────────────────────────────────
    final gemfile = File(p.join(rootPath, 'Gemfile'));
    if (await gemfile.exists()) {
      types.add(ProjectType.ruby);
      features['ruby'] = true;

      final hasRspec = await Directory(p.join(rootPath, 'spec')).exists();
      features['rspec'] = hasRspec;
      if (hasRspec) {
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'RSpec',
            command: 'bundle exec rspec',
            type: VericodeCheckType.customCommand,
            enabled: true,
            order: order++,
            timeoutSeconds: 120,
          ),
        );
      }

      final hasRubocop = await File(p.join(rootPath, '.rubocop.yml')).exists();
      features['rubocop'] = hasRubocop;
      if (hasRubocop) {
        checks.add(
          VericodeCheck(
            id: _id(),
            name: 'RuboCop',
            command: 'bundle exec rubocop',
            type: VericodeCheckType.customCommand,
            enabled: true,
            order: order++,
            timeoutSeconds: 60,
          ),
        );
      }
    }

    // ── Swift ───────────────────────────────────────────────────────
    final swiftPackage = File(p.join(rootPath, 'Package.swift'));
    if (await swiftPackage.exists()) {
      types.add(ProjectType.swift);
      features['swift'] = true;

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Swift Build',
          command: 'swift build',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 120,
        ),
      );

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Swift Test',
          command: 'swift test',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 120,
        ),
      );
    }

    // ── C/C++ (CMake) ──────────────────────────────────────────────
    final cmakeLists = File(p.join(rootPath, 'CMakeLists.txt'));
    if (await cmakeLists.exists()) {
      types.add(ProjectType.cpp);
      features['cmake'] = true;

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'CMake Build',
          command: 'cmake --build build',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 180,
        ),
      );
    }

    // ── C/C++ (Makefile) ───────────────────────────────────────────
    final makefile = File(p.join(rootPath, 'Makefile'));
    if (await makefile.exists() && !types.contains(ProjectType.cpp)) {
      types.add(ProjectType.cpp);
      features['make'] = true;

      checks.add(
        VericodeCheck(
          id: _id(),
          name: 'Make',
          command: 'make',
          type: VericodeCheckType.customCommand,
          enabled: true,
          order: order++,
          timeoutSeconds: 120,
        ),
      );

      // Check if Makefile has test target
      try {
        final makeContent = await makefile.readAsString();
        if (makeContent.contains('test:') || makeContent.contains('test :')) {
          checks.add(
            VericodeCheck(
              id: _id(),
              name: 'Make Test',
              command: 'make test',
              type: VericodeCheckType.customCommand,
              enabled: true,
              order: order++,
              timeoutSeconds: 120,
            ),
          );
        }
      } catch (_) {}
    }

    // ── Determine primary type ──────────────────────────────────────
    final primary = types.isNotEmpty ? types.first : ProjectType.unknown;

    return ProjectDetectionResult(
      primaryType: primary,
      allTypes: types,
      suggestedChecks: checks,
      detectedFeatures: features,
    );
  }

  /// Check if any of the given filenames exist in rootPath.
  Future<bool> _anyExists(List<String> filenames) async {
    for (final name in filenames) {
      if (await File(p.join(rootPath, name)).exists()) return true;
    }
    return false;
  }

  /// Check if any file with the given extensions exists in rootPath (top level).
  Future<bool> _anyExtension(List<String> extensions) async {
    try {
      await for (final entity in Directory(rootPath).list()) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (extensions.contains(ext)) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  String _id() => _uuid.v4().substring(0, 8);
}
