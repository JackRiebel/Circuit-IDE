#!/usr/bin/env bash
set -euo pipefail

flutter test \
  test/history_scale_benchmark_test.dart \
  test/file_indexer_performance_test.dart \
  --reporter expanded

flutter test \
  test/studio_thread_test.dart \
  --plain-name 'StudioTurnController batches a 10k-token burst into bounded turn updates' \
  --reporter expanded

flutter test \
  test/release_performance_series_test.dart \
  test/release_performance_baseline_test.dart \
  --reporter expanded

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '%s\n' '### Deterministic performance fixture budgets'
    printf '%s\n' 'The checked-in `test/fixtures/performance_budgets.json` limits history metadata paging, selected-thread hydration, and 10k-delta update fan-out.'
    printf '%s\n' 'Release-profile startup, scroll-frame, memory, and timeline evidence remains a separate required acceptance gate.'
  } >> "$GITHUB_STEP_SUMMARY"
fi
