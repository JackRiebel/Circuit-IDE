#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

report_path="${ARTIFACT_QUALITY_MATRIX_REPORT:-}"
if [[ -z "$report_path" ]]; then
  report_path="$(mktemp -t circuit-artifact-quality-matrix.XXXXXX.json)"
fi
export ARTIFACT_QUALITY_MATRIX_REPORT="$report_path"

echo "== CircuitCode artifact quality matrix gate =="
flutter test test/artifact_quality_matrix_test.dart --reporter expanded

if [[ ! -s "$report_path" ]]; then
  echo "Artifact quality matrix report was not written" >&2
  exit 1
fi

cat "$report_path"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '%s\n' '### Artifact quality matrix gate'
    printf '%s\n' 'Every registered output kind passed structural validity, persisted visual review, content completeness, source/citation provenance, and automated accessibility checks.'
    printf '%s\n' '```json'
    cat "$report_path"
    printf '%s\n' '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
