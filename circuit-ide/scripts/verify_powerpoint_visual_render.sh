#!/usr/bin/env bash
# Optional protected-environment acceptance probe for a real PowerPoint render.
# The renderer is Office-compatible (LibreOffice), not macOS Quick Look, so its
# evidence supplements rather than replaces native macOS review.
set -euo pipefail

renderer="${CIRCUIT_SOFFICE_PATH:-}"
if [[ -z "$renderer" ]]; then
  echo 'CIRCUIT_SOFFICE_PATH must point to an executable soffice binary.' >&2
  exit 64
fi
if [[ ! -x "$renderer" ]]; then
  echo 'CIRCUIT_SOFFICE_PATH does not point to an executable soffice binary.' >&2
  exit 64
fi

rasterizer="${CIRCUIT_PDFTOPPM_PATH:-}"
if [[ -z "$rasterizer" ]]; then
  echo 'CIRCUIT_PDFTOPPM_PATH must point to an executable pdftoppm binary.' >&2
  exit 64
fi
if [[ ! -x "$rasterizer" ]]; then
  echo 'CIRCUIT_PDFTOPPM_PATH does not point to an executable pdftoppm binary.' >&2
  exit 64
fi

flutter test test/artifact_visual_smoke_test.dart \
  --plain-name 'an Office-compatible renderer produces a nonblank PowerPoint slide preview'
