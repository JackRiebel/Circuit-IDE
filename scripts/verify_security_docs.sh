#!/usr/bin/env bash
set -euo pipefail

security="docs/SECURITY.md"
review="docs/SECURITY_REVIEW_CHECKLIST.md"
release="docs/RELEASE_READINESS_CHECKLIST.md"

for file in "$security" "$review" "$release"; do
  test -f "$file"
done

for heading in \
  "Threat model" \
  "Incident response" \
  "P0 control mapping" \
  "Residual risks"; do
  rg -Fq "$heading" "$security"
done

for control in CC-SEC-001 CC-SEC-002 CC-SEC-003 CC-SEC-004 CC-SEC-005 CC-SEC-007 CC-SEC-008; do
  rg -Fq "$control" "$review"
done

for heading in \
  "Required engineering gates" \
  "Security, signing, and distribution" \
  "Release smoke test" \
  "Exceptions, rollback, and sign-off"; do
  rg -Fq "$heading" "$release"
done

rg -Fq "SECURITY_REVIEW_CHECKLIST.md" "$release"
rg -Fq "RELEASE_READINESS_CHECKLIST.md" docs/RELEASE.md
rg -Fq "MACOS_ACCEPTANCE.md" "$release"
rg -Fq "ACCESSIBILITY.md" "$release"
rg -Fq "Reduce motion" docs/ACCESSIBILITY.md
rg -Fq "target format's screen reader" docs/ACCESSIBILITY.md
rg -Fq "Browser preview privacy and origin controls" docs/MACOS_ACCEPTANCE.md
rg -Fq "loopback WebKit host-test" "$review"

echo "CircuitCode threat-model and release-readiness documentation verified."
