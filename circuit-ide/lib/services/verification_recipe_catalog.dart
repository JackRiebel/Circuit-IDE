/// Human-facing, deterministic explanations for approved project checks. The
/// command remains the executable value; this metadata is never interpolated
/// into a shell command.
class VerificationRecipeCatalog {
  const VerificationRecipeCatalog._();

  static String rationale(String command) {
    final value = command.trim().toLowerCase();
    if (value == 'flutter analyze') {
      return 'Static analysis catches Dart and Flutter API errors.';
    }
    if (value == 'flutter test') {
      return 'Runs the Flutter automated test suite.';
    }
    if (value == 'npm test' || value == 'npm run test') {
      return 'Runs the package test script declared by the project.';
    }
    if (value == 'npm run lint') {
      return 'Runs the project lint rules for code-quality regressions.';
    }
    if (value == 'npm run build') {
      return 'Builds the production bundle to catch integration errors.';
    }
    if (value == 'python -m pytest') {
      return 'Runs Python tests discovered by pytest.';
    }
    if (value == 'cargo test') {
      return 'Builds and runs Rust crate tests.';
    }
    if (value == 'go test ./...') {
      return 'Runs Go tests across all workspace packages.';
    }
    if (value == 'make test') {
      return 'Runs the repository-maintained test target.';
    }
    if (value == 'make lint') {
      return 'Runs the repository-maintained lint target.';
    }
    if (value == 'make build') {
      return 'Runs the repository-maintained build target.';
    }
    return 'Project-recommended verification check.';
  }
}
