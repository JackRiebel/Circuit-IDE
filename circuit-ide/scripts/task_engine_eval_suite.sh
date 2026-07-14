#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

report_path="${TASK_ENGINE_EVAL_REPORT:-}"
temporary_report=false
if [[ -z "$report_path" ]]; then
  report_path="$(mktemp -t circuit-task-engine-eval.XXXXXX.json)"
  temporary_report=true
fi
export TASK_ENGINE_EVAL_REPORT="$report_path"

cleanup() {
  if [[ "$temporary_report" == true ]]; then
    rm -f "$report_path"
  fi
}
trap cleanup EXIT

echo "== CircuitCode deterministic task-engine evaluation =="
flutter test test/agent_task_engine_eval_test.dart --reporter failures-only

if [[ ! -s "$report_path" ]]; then
  echo 'Task-engine evaluation report was not written.' >&2
  exit 1
fi

# The summary must describe the fixture inventory that passed, not merely a
# wrapper-owned success string. Keep this structural check dependency-free for
# both local and macOS CI environments.
for required in \
  '"schemaVersion":1' \
  '"evaluation":"deterministic-task-engine"' \
  '"allPassed":true' \
  '"requiredPassRate":1.0' \
  '"chat"' \
  '"ask"' \
  '"plan"' \
  '"code"' \
  '"review"' \
  '"verify"'; do
  if ! rg -Fq "$required" "$report_path"; then
    echo "Task-engine evaluation report is missing required field: $required" >&2
    exit 1
  fi
done
if ! rg -q -e '"promptRoutingScenarioCount":[1-9][0-9]*' "$report_path"; then
  echo 'Task-engine evaluation report has no prompt-routing fixtures.' >&2
  exit 1
fi

echo 'Task-engine deterministic evaluation report:'
cat "$report_path"
printf '\n'

summary_file="${GITHUB_STEP_SUMMARY:-}"
if [[ -n "$summary_file" ]]; then
  cat >>"$summary_file" <<'EOF'
## CircuitCode task-engine evaluation

| Evaluation | Score | Release threshold |
| --- | ---: | ---: |
| Deterministic task-engine contracts | 100% | 100% |

The score is emitted only when every deterministic fixture passes and its
aggregate fixture inventory is structurally valid. The report intentionally
contains no prompts, workspace paths, provider payloads, or customer data.

```json
EOF
  cat "$report_path" >>"$summary_file"
  printf '\n' >>"$summary_file"
  cat >>"$summary_file" <<'EOF'
```
EOF
else
  echo 'Task-engine deterministic contract score: 100% (all fixtures passed and reported).'
fi
