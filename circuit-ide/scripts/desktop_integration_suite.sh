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
test_pid=''

terminate_process_tree() {
  local pid="$1"
  local child=''
  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    terminate_process_tree "$child"
  done
  kill -TERM "$pid" 2>/dev/null || true
}

cleanup() {
  if [[ -n "$test_pid" ]] && kill -0 "$test_pid" 2>/dev/null; then
    terminate_process_tree "$test_pid"
    wait "$test_pid" 2>/dev/null || true
  fi
  rm -f "$output"
}
trap cleanup EXIT

# Flutter can report a green test fallback even when macOS LaunchServices
# refuses to foreground the test host. Preserve the regular test exit status,
# but make that host-level refusal a hard gate so this script remains evidence
# for a real desktop journey rather than only a widget fallback.
if [[ "${CIRCUIT_ALLOW_HEADLESS_DESKTOP_FALLBACK:-}" == "1" ]]; then
  set +e
  flutter test integration_test/studio_desktop_journey_test.dart \
    --reporter failures-only 2>&1 | tee "$output"
  test_status=${PIPESTATUS[0]}
  set -e
else
  # On an interactive Mac, a LaunchServices foreground refusal is conclusive
  # acceptance evidence. Stop the isolated test process tree as soon as the
  # Flutter host reports it instead of leaving a headless widget fallback to
  # run until its own timeout. Hosted CI opts into the fallback above.
  set +e
  flutter test integration_test/studio_desktop_journey_test.dart \
    --reporter failures-only >"$output" 2>&1 &
  test_pid="$!"
  while kill -0 "$test_pid" 2>/dev/null; do
    if grep -Fq -- 'Failed to foreground app; open returned' "$output"; then
      terminate_process_tree "$test_pid"
      wait "$test_pid" 2>/dev/null || true
      cat "$output"
      echo 'Desktop integration journey did not foreground the macOS app host.' >&2
      exit 1
    fi
    sleep 0.1
  done
  wait "$test_pid"
  test_status="$?"
  set -e
  test_pid=''
  cat "$output"
fi

if (( test_status != 0 )); then
  exit "$test_status"
fi
if grep -Fq -- 'Failed to foreground app; open returned' "$output"; then
  if [[ "${CIRCUIT_ALLOW_HEADLESS_DESKTOP_FALLBACK:-}" == "1" ]]; then
    echo 'Desktop journey passed its deterministic Flutter coverage, but this host could not foreground a macOS app.'
    echo 'Headless fallback was explicitly allowed; clean interactive macOS foreground acceptance remains required.'
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      {
        printf '%s\n' '### Desktop Studio journey host boundary'
        printf '%s\n' 'The deterministic Studio journey passed, but this hosted macOS runner could not foreground a GUI app. CI retained the Flutter journey plus the separate native RunnerTests smoke; a clean interactive Mac must still retain the foreground and Release-bundle acceptance result.'
      } >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 0
  fi
  echo 'Desktop integration journey did not foreground the macOS app host.' >&2
  exit 1
fi
