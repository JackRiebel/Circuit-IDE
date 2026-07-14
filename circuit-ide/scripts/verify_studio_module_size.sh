#!/usr/bin/env bash
set -euo pipefail

# Resolve all paths from the Flutter product root so this gate is equally
# reliable when invoked as `bash scripts/...` from circuit-ide/ or as
# `bash circuit-ide/scripts/...` from the repository root.
cd "$(dirname "$0")/.."

# CC-ARCH-003 guardrail. Keep Studio UI features small enough that rebuild
# ownership is visible from the module boundary, and prevent state providers
# from becoming unreviewable catch-all stores. Exceptions must be documented
# in docs/adr/studio-size-exceptions.md with a named owner and removal date.

readonly MAX_STUDIO_UI_LINES=800
readonly MAX_PROVIDER_LINES=1000
readonly EXCEPTIONS_FILE="../docs/adr/studio-size-exceptions.md"

if [[ ! -f "$EXCEPTIONS_FILE" ]]; then
  echo "Missing architecture size-exception register: $EXCEPTIONS_FILE" >&2
  exit 2
fi

is_excepted() {
  local path="$1"
  grep -Fq -- "\`$path\`" "$EXCEPTIONS_FILE"
}

check_directory() {
  local directory="$1"
  local limit="$2"
  local label="$3"
  local failed=0
  while IFS= read -r file; do
    local lines
    lines=$(wc -l < "$file" | tr -d ' ')
    if (( lines > limit )); then
      if is_excepted "$file"; then
        echo "EXEMPT $label $file: $lines lines (ADR exception)"
      else
        echo "FAIL $label $file: $lines lines (limit $limit)" >&2
        failed=1
      fi
    fi
  done < <(find "$directory" -type f -name '*.dart' -print | sort)
  return "$failed"
}

failed=0
check_directory "lib/ui/studio" "$MAX_STUDIO_UI_LINES" "Studio UI" || failed=1
check_directory "lib/state" "$MAX_PROVIDER_LINES" "State provider" || failed=1
check_directory "lib/agent/providers" "$MAX_PROVIDER_LINES" "Provider adapter" || failed=1

if (( failed != 0 )); then
  echo "Split the listed feature/state boundary or add a time-bounded ADR exception." >&2
  exit 1
fi

echo "Studio module size limits pass."
