import 'package:circuit_ide/services/verification_recipe_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'verification recipes explain checks without changing executable text',
    () {
      expect(
        VerificationRecipeCatalog.rationale('flutter analyze'),
        contains('Static analysis'),
      );
      expect(
        VerificationRecipeCatalog.rationale('npm test'),
        contains('package test'),
      );
      expect(
        VerificationRecipeCatalog.rationale('python -m pytest'),
        contains('Python'),
      );
      expect(
        VerificationRecipeCatalog.rationale('cargo test'),
        contains('Rust'),
      );
      expect(
        VerificationRecipeCatalog.rationale('go test ./...'),
        contains('Go'),
      );
    },
  );
}
