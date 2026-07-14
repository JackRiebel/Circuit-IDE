#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== CircuitCode visual regression and artifact rendering gate =="
# Widget suites set a process-wide test surface size. Keep golden captures
# serial so another suite cannot resize the surface during a comparison.
flutter test --no-pub --concurrency=1 \
  test/studio_layout_contract_test.dart \
  test/studio_visual_regression_test.dart \
  test/artifact_template_selector_test.dart \
  test/artifact_visual_preview_renderer_test.dart \
  test/powerpoint_visual_preview_test.dart \
  test/artifact_visual_smoke_test.dart \
  --reporter compact

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '%s\n' '### Visual regression and artifact rendering gate'
    printf '%s\n' 'Checked-in production-dark Studio references cover no-project home, Settings, update deferral during active Studio work, rail history, source-acquisition repair progress, shell sizes, prose/review widths, long transcript conclusion, streaming draft, plan review, scoped approval, prepared patch, patch conflict, turn failure, interrupted recovery, populated artifact review, and artifact-template states; structural Word/PDF/Excel/PowerPoint review coverage and real macOS Quick Look previews for Word/PDF/Excel also passed.'
    printf '%s\n' 'The Quick Look checks verify generated previews are non-empty PNG renders; they do not replace human reference-review coverage for every product state and viewport.'
  } >> "$GITHUB_STEP_SUMMARY"
fi
