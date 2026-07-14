#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for file in README.md circuit-ide/README.md docs/ARCHITECTURE.md \
  docs/PROVIDER_PROTOCOL.md docs/RELEASE.md docs/SECURITY.md \
  docs/SECURITY_REVIEW_CHECKLIST.md docs/RELEASE_READINESS_CHECKLIST.md \
  docs/MACOS_ACCEPTANCE.md docs/ACCESSIBILITY.md docs/TROUBLESHOOTING.md; do
  test -f "$ROOT_DIR/$file"
done

rg -q "Flutter 3.41.2" "$ROOT_DIR/README.md"
rg -q "flutter pub get" "$ROOT_DIR/README.md"
rg -q "flutter run -d macos" "$ROOT_DIR/README.md"
rg -q "flutter build macos --release" "$ROOT_DIR/README.md"
rg -q "Keychain" "$ROOT_DIR/README.md"
rg -q "PROVIDER_PROTOCOL.md" "$ROOT_DIR/README.md"
rg -q "RELEASE.md" "$ROOT_DIR/README.md"
rg -q "SECURITY.md" "$ROOT_DIR/README.md"
rg -q "TROUBLESHOOTING.md" "$ROOT_DIR/README.md"
rg -qi "pending approvals expire" "$ROOT_DIR/docs/TROUBLESHOOTING.md"
rg -Fq "CC-UI-012" "$ROOT_DIR/docs/MACOS_ACCEPTANCE.md"
rg -Fq "MACOS_ACCEPTANCE.md" "$ROOT_DIR/docs/RELEASE.md"
rg -Fq "ACCESSIBILITY.md" "$ROOT_DIR/docs/RELEASE_READINESS_CHECKLIST.md"
bash "$ROOT_DIR/scripts/verify_security_docs.sh"

echo "CircuitCode clean-clone onboarding documentation verified."
