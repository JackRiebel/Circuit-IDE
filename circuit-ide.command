#!/bin/bash
# CircuitCode macOS launcher. This is the only supported desktop entry point.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/circuit-ide/build/macos/Build/Products/Release/CircuitCode.app"

if [[ -d "$APP_DIR" ]]; then
  open -n "$APP_DIR"
  exit 0
fi

cd "$ROOT_DIR/circuit-ide"
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter 3.41.2 is required to launch CircuitCode from source." >&2
  exit 1
fi

echo "No release build is available; starting the Flutter macOS app from source."
flutter pub get
exec flutter run -d macos "$@"
