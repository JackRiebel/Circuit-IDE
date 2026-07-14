#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== CircuitCode intent-routing evaluation =="
flutter test test/intent_routing_eval_test.dart --reporter expanded

summary_file="${GITHUB_STEP_SUMMARY:-}"
if [[ -n "$summary_file" ]]; then
  cat >>"$summary_file" <<'EOF'
## CircuitCode intent-routing evaluation

| Evaluation | Score | Release threshold |
| --- | ---: | ---: |
| Intent routing micro precision | >=95% | >=95% |
| Intent routing micro recall | >=95% | >=95% |

The offline corpus covers greeting, discovery, direct edit, research, plan,
review, file generation, verification, and ambiguous requests. It also checks
that malformed and low-confidence typed model output falls back to Ask.
EOF
else
  echo 'Intent-routing thresholds: micro precision >=95%, micro recall >=95%.'
fi
