#!/usr/bin/env bash
# Captures a bounded, redacted release-bundle performance evidence line. This
# is not a replacement for the repeated reference-hardware traces required by
# docs/PERFORMANCE_BUDGETS.md.
set -euo pipefail

app_path="${1:?usage: verify_release_performance_probe.sh /path/to/CircuitCode.app}"
plist="$app_path/Contents/Info.plist"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Release performance probe requires macOS.' >&2
  exit 64
fi
if [[ ! -d "$app_path" || ! -f "$plist" ]]; then
  echo "Release app bundle is missing or malformed: $app_path" >&2
  exit 66
fi

read_plist() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$plist"
}

if [[ "$(read_plist CFBundleIdentifier)" != 'com.circuitide.app' ]] || \
  [[ "$(read_plist CFBundleName)" != 'CircuitCode' ]]; then
  echo 'Unexpected CircuitCode bundle identity.' >&2
  exit 65
fi

output="$(mktemp "${TMPDIR:-/tmp}/circuit-release-performance.XXXXXX")"
marker="circuitcode-release-performance-${RANDOM}${RANDOM}"
cleanup() {
  local probe_pid
  probe_pid="$(pgrep -f "$marker" | tail -n 1 || true)"
  if [[ -n "$probe_pid" ]] && kill -0 "$probe_pid" 2>/dev/null; then
    kill -TERM "$probe_pid" 2>/dev/null || true
  fi
  rm -f "$output"
}
trap cleanup EXIT

set +e
/usr/bin/open -n -g --stdout "$output" --stderr "$output" "$app_path" \
  --args --circuitcode-packaged-performance-probe "$marker"
open_status=$?
set -e

for _ in {1..200}; do
  if grep -Fq 'PACKAGED_RELEASE_PERFORMANCE=' "$output"; then
    break
  fi
  sleep 0.1
done

line="$(sed -n 's/^PACKAGED_RELEASE_PERFORMANCE=//p' "$output" | tail -n 1)"
if [[ -z "$line" ]]; then
  echo 'Packaged CircuitCode release performance probe did not produce metrics.' >&2
  if [[ "$open_status" -ne 0 ]]; then
    echo "LaunchServices returned status $open_status." >&2
  fi
  cat "$output" >&2
  exit 1
fi
if ! grep -Eq '"passed":true' <<<"$line" || \
  ! grep -Eq '"stage":"ok"' <<<"$line"; then
  echo 'Packaged CircuitCode release performance probe reported a failure.' >&2
  echo "$line" >&2
  exit 1
fi
for metric in \
  dartMainToFirstFrameMilliseconds \
  projectBindMilliseconds \
  firstStreamFrameMilliseconds \
  streamTenThousandDeltaBurstMilliseconds \
  streamTenThousandDeltaStateUpdates \
  taskSwitchMilliseconds \
  durableReloadMilliseconds \
  taskSummaryPage5000Milliseconds \
  threadSummaryPage1000Milliseconds \
  threadHydration1000Milliseconds \
  projectRecoveryAndMetadata500Milliseconds \
  semanticIndexRebuild1200Milliseconds \
  durableCheckpointPersistenceMilliseconds \
  residentSetBytes \
  streamFrameTimingSampleCount \
  streamFrameBuildP95Milliseconds \
  streamFrameRasterP95Milliseconds \
  streamFrameTotalP95Milliseconds \
  transcriptScrollFrameTimingSampleCount \
  transcriptScrollFrameBuildP95Milliseconds \
  transcriptScrollFrameRasterP95Milliseconds \
  transcriptScrollFrameTotalP95Milliseconds; do
  if ! grep -Eq "\"$metric\":[0-9]+" <<<"$line"; then
    echo "Packaged CircuitCode release performance probe omitted $metric." >&2
    echo "$line" >&2
    exit 1
  fi
done
if ! grep -Eq '"streamFrameTimingSampleCount":([5-9]|[1-9][0-9]+)' <<<"$line"; then
  echo 'Packaged CircuitCode release performance probe captured too few stream frames.' >&2
  echo "$line" >&2
  exit 1
fi
if ! grep -Eq '"transcriptScrollFrameTimingSampleCount":([5-9]|[1-9][0-9]+)' <<<"$line"; then
  echo 'Packaged CircuitCode release performance probe captured too few transcript-scroll frames.' >&2
  echo "$line" >&2
  exit 1
fi

echo "PACKAGED_RELEASE_PERFORMANCE=$line"
echo 'Packaged CircuitCode release performance evidence probe passed.'

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '%s\n' '### Packaged release performance evidence'
    printf '%s\n' 'This bounded Release-bundle probe records real-shell startup, bind, first-stream-frame, a 10,000-delta coalescing burst, paced Flutter build/raster frame timings, a virtualized 1,000-turn transcript-scroll frame trace, task-switch, durable-reload, 5,000-task/1,000-thread durable-history reads, recovery plus first-page metadata across 500 durable projects, a 1,200-file semantic-index rebuild, direct task/thread checkpoint persistence, and RSS values. It is not a replacement for the five-run reference-hardware release-profile acceptance traces.'
    printf '%s\n' '```json'
    printf '%s\n' "$line"
    printf '%s\n' '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
