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
  grep -Fq "$heading" "$security"
done

for control in CC-SEC-001 CC-SEC-002 CC-SEC-003 CC-SEC-004 CC-SEC-005 CC-SEC-007 CC-SEC-008; do
  grep -Fq "$control" "$review"
done

for heading in \
  "Required engineering gates" \
  "Security, signing, and distribution" \
  "Release smoke test" \
  "Exceptions, rollback, and sign-off"; do
  grep -Fq "$heading" "$release"
done

grep -Fq "SECURITY_REVIEW_CHECKLIST.md" "$release"
grep -Fq "RELEASE_READINESS_CHECKLIST.md" docs/RELEASE.md
grep -Fq "MACOS_ACCEPTANCE.md" "$release"
grep -Fq "ACCESSIBILITY.md" "$release"
grep -Fq "Reduce motion" docs/ACCESSIBILITY.md
grep -Fq "target format's screen reader" docs/ACCESSIBILITY.md
grep -Fq "Browser preview privacy and origin controls" docs/MACOS_ACCEPTANCE.md
grep -Fq "loopback WebKit host-test" "$review"
grep -Fq "required aggregate CI run's \`Security scanner fixture exercise\` job" "$review"
grep -Fq "full-history Gitleaks scan" "$security"

echo "CircuitCode threat-model and release-readiness documentation verified."
