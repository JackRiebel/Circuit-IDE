#!/usr/bin/env bash
# Bounded launch, lifecycle, and crash-privacy smoke for the actual Release
# app bundle. UI-driven task journeys remain a separate integration
# requirement.
set -euo pipefail

app_path="${1:?usage: verify_packaged_app_launch.sh /path/to/CircuitCode.app}"
plist="$app_path/Contents/Info.plist"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Packaged app launch smoke requires macOS.' >&2
  exit 64
fi
if [[ ! -d "$app_path" || ! -f "$plist" ]]; then
  echo "Release app bundle is missing or malformed: $app_path" >&2
  exit 66
fi

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$plist"
}

bundle_id="$(read_plist CFBundleIdentifier)"
bundle_name="$(read_plist CFBundleName)"
executable_name="$(read_plist CFBundleExecutable)"
executable="$app_path/Contents/MacOS/$executable_name"

if [[ "$bundle_id" != 'com.circuitide.app' || "$bundle_name" != 'CircuitCode' ]]; then
  echo "Unexpected CircuitCode bundle identity: $bundle_id / $bundle_name" >&2
  exit 65
fi
if [[ ! -x "$executable" ]]; then
  echo "Release app executable is missing or not executable: $executable" >&2
  exit 66
fi

# `pgrep` normally provides the narrow process lookup used below. Some managed
# macOS hosts disable its sysmond dependency, though `ps` remains available to
# the current user. Retain the same exact-marker matching in that environment
# so a host diagnostic limitation cannot turn a valid packaged-app run into a
# false failure or make cleanup target an unrelated CircuitCode process.
find_marker_pid() {
  local marker="${1:?marker is required}"
  local pid=''
  if command -v pgrep >/dev/null 2>&1; then
    pid="$(pgrep -f "$marker" 2>/dev/null | tail -n 1 || true)"
  fi
  if [[ -n "$pid" ]]; then
    printf '%s\n' "$pid"
    return
  fi
  /bin/ps -axo pid=,command= 2>/dev/null |
    /usr/bin/awk -v marker="$marker" '
      index($0, marker) { pid = $1 }
      END { if (pid != "") print pid }
    '
}

pid=''
smoke_output=''
smoke_marker=''
privacy_output=''
cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  if [[ -n "$smoke_marker" ]]; then
    smoke_pid="$(find_marker_pid "$smoke_marker")"
    if [[ -n "$smoke_pid" ]] && kill -0 "$smoke_pid" 2>/dev/null; then
      kill -TERM "$smoke_pid" 2>/dev/null || true
    fi
  fi
  if [[ -n "$smoke_output" ]] && [[ -f "$smoke_output" ]]; then
    rm -f "$smoke_output"
  fi
  if [[ -n "$privacy_output" ]] && [[ -f "$privacy_output" ]]; then
    rm -f "$privacy_output"
  fi
}
trap cleanup EXIT

# AppKit applications must be launched through LaunchServices. Running a GUI
# executable directly from a non-UI shell can fail before Flutter starts. A
# unique inert argument lets this harness identify and stop exactly the app
# instance it launches without touching a user-owned CircuitCode process.
launch_marker="circuitcode-launch-smoke-${RANDOM}${RANDOM}"
/usr/bin/open -n -g "$app_path" --args "$launch_marker"

# AppKit/Flutter startup is asynchronous. Keep the window alive long enough
# to prove the packaged host has not immediately terminated, then shut down
# only the process created by this harness.
for _ in {1..20}; do
  pid="$(find_marker_pid "$launch_marker")"
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    echo 'Packaged CircuitCode app exited before completing its launch smoke.' >&2
    exit 1
  fi
  sleep 0.1
done

cleanup
pid=''

# This LaunchServices-selected path is not an end-user surface. It runs a
# provider-free Studio lifecycle inside the packaged app using an isolated
# temporary workspace, then exits with a machine-readable result.
smoke_marker="circuitcode-lifecycle-smoke-${RANDOM}${RANDOM}"
smoke_output="$(mktemp "${TMPDIR:-/tmp}/circuit-packaged-smoke.XXXXXX")"
set +e
/usr/bin/open -n -g --stdout "$smoke_output" --stderr "$smoke_output" "$app_path" \
  --args --circuitcode-packaged-smoke "$smoke_marker"
open_status=$?
set -e
for _ in {1..200}; do
  if grep -Fq 'PACKAGED_STUDIO_SMOKE=PASS:ok' "$smoke_output"; then
    break
  fi
  sleep 0.1
done
if ! grep -Fq 'PACKAGED_STUDIO_SMOKE=PASS:ok' "$smoke_output"; then
  echo 'Packaged CircuitCode Studio lifecycle smoke failed.' >&2
  if [[ "$open_status" -ne 0 ]]; then
    echo "LaunchServices returned status $open_status." >&2
  fi
  cat "$smoke_output" >&2
  exit 1
fi

# This isolated mode runs both installed crash boundaries with seeded private
# values, confirms that their local ledger is redacted, then sends SIGABRT to
# only this harness-launched app. The ledger is deliberately left in the
# temporary directory for the operating system to clean up; it contains no
# prompt, token, or source-path content and is the evidence inspected below.
privacy_marker="circuitcode-privacy-audit-${RANDOM}${RANDOM}"
privacy_output="$(mktemp "${TMPDIR:-/tmp}/circuit-packaged-privacy.XXXXXX")"
set +e
/usr/bin/open -n -g --stdout "$privacy_output" --stderr "$privacy_output" "$app_path" \
  --args --circuitcode-packaged-privacy-crash "$privacy_marker"
privacy_open_status=$?
set -e
for _ in {1..200}; do
  if grep -Fq 'PACKAGED_PRIVACY_CRASH_AUDIT=READY pid=' "$privacy_output"; then
    break
  fi
  sleep 0.1
done
if ! grep -Fq 'PACKAGED_PRIVACY_CRASH_AUDIT=READY pid=' "$privacy_output"; then
  echo 'Packaged CircuitCode process-terminating privacy audit did not become ready.' >&2
  if [[ "$privacy_open_status" -ne 0 ]]; then
    echo "LaunchServices returned status $privacy_open_status." >&2
  fi
  cat "$privacy_output" >&2
  exit 1
fi

privacy_pid="$(sed -n 's/^PACKAGED_PRIVACY_CRASH_AUDIT=READY pid=\([0-9][0-9]*\) ledger=.*$/\1/p' "$privacy_output" | tail -n 1)"
privacy_ledger="$(sed -n 's/^PACKAGED_PRIVACY_CRASH_AUDIT=READY pid=[0-9][0-9]* ledger=//p' "$privacy_output" | tail -n 1)"
if [[ ! "$privacy_pid" =~ ^[0-9]+$ ]] || [[ -z "$privacy_ledger" || ! -f "$privacy_ledger" ]]; then
  echo 'Packaged CircuitCode privacy audit did not produce an inspectable ledger.' >&2
  cat "$privacy_output" >&2
  exit 1
fi
if ! grep -Fq '"source":"flutter"' "$privacy_ledger" || \
  ! grep -Fq '"source":"platform"' "$privacy_ledger" || \
  ! grep -Fq '[PATH]' "$privacy_ledger"; then
  echo 'Packaged CircuitCode privacy ledger is missing expected redacted boundary evidence.' >&2
  cat "$privacy_ledger" >&2
  exit 1
fi
if grep -Fq 'private packaged crash customer content' "$privacy_ledger" || \
  grep -Fq 'packaged-crash-smoke-token' "$privacy_ledger"; then
  echo 'Packaged CircuitCode privacy ledger leaked seeded private content.' >&2
  cat "$privacy_ledger" >&2
  exit 1
fi

privacy_process_terminated=false
for _ in {1..20}; do
  if ! kill -0 "$privacy_pid" 2>/dev/null; then
    privacy_process_terminated=true
    break
  fi
  sleep 0.1
done
if [[ "$privacy_process_terminated" != true ]]; then
  echo 'Packaged CircuitCode privacy-audit process did not terminate after SIGABRT.' >&2
  exit 1
fi

echo 'Packaged CircuitCode process-terminating privacy smoke passed.'
echo 'Packaged CircuitCode release launch and Studio lifecycle smoke passed.'
