#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT_DIR/circuit-ide.command"

test -x "$LAUNCHER"
test -d "$ROOT_DIR/circuit-ide"
test -d "$ROOT_DIR/legacy/python"
test -d "$ROOT_DIR/legacy/docs"
test ! -e "$ROOT_DIR/circuit_agent"
test ! -e "$ROOT_DIR/circuit_ide"
test ! -e "$ROOT_DIR/circuit_ide_gui"
test ! -e "$ROOT_DIR/circuit_agent.py"
test ! -e "$ROOT_DIR/pyproject.toml"
test ! -e "$ROOT_DIR/docs/SETUP.md"

bash -n "$LAUNCHER"
if rg -n "python[0-9.]* .*circuit_|circuit_ide_gui|Circuit IDE Launcher" \
  "$LAUNCHER"; then
  echo "The root launcher must not start a retired Python product." >&2
  exit 1
fi

rg -q "The supported application is the Flutter" "$ROOT_DIR/README.md"
rg -q "desktop product in" "$ROOT_DIR/README.md"
rg -q "flutter run -d macos" "$LAUNCHER"
rg -q "Flutter application in .circuit-ide/." "$ROOT_DIR/docs/ARCHITECTURE.md"

echo "Canonical Flutter product boundary verified."
