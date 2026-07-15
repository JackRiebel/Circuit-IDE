#!/usr/bin/env bash
set -euo pipefail

adr="docs/adr/0008-local-first-sync-and-collaboration.md"

test -f "$adr"
rg -Fq "Status: Proposed" "$adr"
rg -Fq "Identity and local records" "$adr"
rg -Fq "Encryption and keys" "$adr"
rg -Fq "Conflict policy" "$adr"
rg -Fq "Sharing and organization boundaries" "$adr"
rg -Fq "Required verification before implementation" "$adr"
rg -Fq "disabled by default" "$adr"
rg -Fq "0008-local-first-sync-and-collaboration.md" docs/adr/README.md
rg -Fq "sync and collaboration ADR" docs/ARCHITECTURE.md

echo "CircuitCode local-first sync architecture verified."
