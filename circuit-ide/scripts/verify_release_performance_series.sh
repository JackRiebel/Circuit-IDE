#!/usr/bin/env bash
# Collects five or more real LaunchServices Release probes, then emits a
# redacted min/median/p95/max summary. This remains evidence collection, not a
# substitute for release-profile frame timelines or reference-hardware review.
set -euo pipefail

app_path="${1:?usage: verify_release_performance_series.sh /path/to/CircuitCode.app [runs]}"
runs="${2:-5}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

if ! [[ "$runs" =~ ^[0-9]+$ ]] || [[ "$runs" -lt 5 ]]; then
  echo 'Release performance series requires at least five runs.' >&2
  exit 64
fi

samples="$(mktemp "${TMPDIR:-/tmp}/circuit-release-performance-series.XXXXXX")"
# BSD/macOS mktemp requires the X placeholder to terminate the template. The
# aggregate is JSON by content, so an extension is unnecessary and would make
# the evidence collector fail before taking its first Release sample.
series_file="$(mktemp "${TMPDIR:-/tmp}/circuit-release-performance-summary.XXXXXX")"
cleanup() {
  rm -f "$samples" "$series_file"
}
trap cleanup EXIT

plist="$app_path/Contents/Info.plist"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo unknown)"
macos_version="$(sw_vers -productVersion 2>/dev/null || uname -r)"
architecture="$(uname -m)"
hardware_model="$(sysctl -n hw.model 2>/dev/null || uname -m)"
fixture_revision="$(shasum -a 256 "$repo_root/test/fixtures/performance_budgets.json" | awk '{print $1}')"

for ((run = 1; run <= runs; run++)); do
  if ! output="$(bash "$script_dir/verify_release_performance_probe.sh" "$app_path")"; then
    echo "Release performance sample $run of $runs failed." >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  line="$(printf '%s\n' "$output" | sed -n 's/^PACKAGED_RELEASE_PERFORMANCE=//p' | tail -n 1)"
  if [[ -z "$line" ]]; then
    echo "Release performance sample $run of $runs omitted its metrics." >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  printf '%s\n' "$line" >> "$samples"
  echo "Captured redacted Release performance sample $run of $runs."
done

cd "$repo_root"
if ! aggregate_output="$(dart run scripts/aggregate_release_performance.dart "$samples" \
  --build-version "$build_version" \
  --macos-version "$macos_version" \
  --architecture "$architecture" \
  --hardware-model "$hardware_model" \
  --fixture-revision "$fixture_revision")"; then
  echo 'Could not aggregate packaged Release performance samples.' >&2
  printf '%s\n' "$aggregate_output" >&2
  exit 1
fi
if [[ "$aggregate_output" =~ (\{\"schemaVersion\":.*\})$ ]]; then
  series="${BASH_REMATCH[1]}"
else
  echo 'Release performance aggregation omitted its versioned JSON summary.' >&2
  printf '%s\n' "$aggregate_output" >&2
  exit 1
fi
echo "PACKAGED_RELEASE_PERFORMANCE_SERIES=$series"
printf '%s\n' "$series" > "$series_file"
baseline_path="${CIRCUIT_RELEASE_PERFORMANCE_BASELINE:-$repo_root/test/fixtures/release_performance_baseline_macos_arm64.json}"
if [[ ! -f "$baseline_path" ]]; then
  echo "Release performance baseline is missing: $baseline_path" >&2
  exit 1
fi
baseline_args=("$baseline_path" "$series_file")
if [[ "${CIRCUIT_REQUIRE_RELEASE_PERFORMANCE_BASELINE:-0}" == "1" ]]; then
  baseline_args+=(--require-match)
fi
if ! baseline_output="$(dart run scripts/check_release_performance_baseline.dart "${baseline_args[@]}")"; then
  echo 'Packaged Release performance baseline failed.' >&2
  printf '%s\n' "$baseline_output" >&2
  exit 1
fi
baseline_result="$(printf '%s' "$baseline_output" | tr -d '\r\n' | sed -n 's/.*\({"schemaVersion":.*}\)$/\1/p')"
if [[ -z "$baseline_result" ]]; then
  echo 'Release performance baseline omitted its versioned JSON result.' >&2
  printf '%s\n' "$baseline_output" >&2
  exit 1
fi
echo "PACKAGED_RELEASE_PERFORMANCE_BASELINE=$baseline_result"
echo 'Packaged CircuitCode Release performance series passed.'

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '%s\n' '### Packaged release performance series'
    printf '%s\n' 'Five or more LaunchServices samples were aggregated as nearest-rank p95 evidence. This redacted collector does not replace reference-hardware frame timelines, index rebuild traces, clean-machine testing, or release acceptance.'
    printf '%s\n' '```json'
    printf '%s\n' "$series"
    printf '%s\n' '```'
    printf '%s\n' 'Hardware-scoped baseline result:'
    printf '%s\n' '```json'
    printf '%s\n' "$baseline_result"
    printf '%s\n' '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
