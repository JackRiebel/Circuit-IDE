#!/usr/bin/env bash
# A real macOS Flutter-engine journey through the production Studio shell.
# Fixtures use only a temporary project and deterministic local provider, so
# this never needs credentials, external network access, or user files.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Desktop integration suite requires macOS.' >&2
  exit 64
fi

output="$(mktemp "${TMPDIR:-/tmp}/circuit-desktop-integration.XXXXXX")"
cleanup() {
  rm -f "$output"
}
trap cleanup EXIT

# Flutter can report a green test fallback even when macOS LaunchServices
# refuses to foreground the test host. Preserve the regular test exit status,
# but make that host-level refusal a hard gate so this script remains evidence
# for a real desktop journey rather than only a widget fallback.
set +e
flutter test integration_test/studio_desktop_journey_test.dart \
  --reporter failures-only 2>&1 | tee "$output"
test_status=${PIPESTATUS[0]}
set -e
if (( test_status != 0 )); then
  exit "$test_status"
fi
if grep -Fq -- 'Failed to foreground app; open returned' "$output"; then
  echo 'Desktop integration journey did not foreground the macOS app host.' >&2
  exit 1
fi
