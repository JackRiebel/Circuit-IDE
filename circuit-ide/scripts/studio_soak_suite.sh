#!/usr/bin/env bash
set -euo pipefail

report_path="${STUDIO_SOAK_REPORT_PATH:-}"
temporary_report=''
if [[ -z "$report_path" ]]; then
  temporary_report="$(mktemp "${TMPDIR:-/tmp}/circuitcode-studio-soak.XXXXXX.json")"
  report_path="$temporary_report"
fi
export STUDIO_SOAK_REPORT_PATH="$report_path"

cleanup() {
  if [[ -n "$temporary_report" ]]; then
    rm -f "$temporary_report"
  fi
}
trap cleanup EXIT

flutter test test/studio_soak_harness_test.dart --reporter expanded

if [[ ! -s "$report_path" ]]; then
  echo 'Studio soak did not produce a report.' >&2
  exit 1
fi

echo '== Studio soak report =='
cat "$report_path"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '%s\n' '### Studio soak report'
    printf '%s\n' 'The report below contains only cycle counts, timestamps, RSS measurements, a configured RSS-growth budget verdict, bundled-broker selection, and typed failure stages.'
    printf '%s\n' '```json'
    cat "$report_path"
    printf '%s\n' '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
