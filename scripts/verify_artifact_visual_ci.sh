#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/ci.yml"

if [[ ! -f "$workflow" ]]; then
  echo "Missing required CI workflow: $workflow" >&2
  exit 1
fi

require() {
  local pattern="$1"
  if ! grep -Fq -- "$pattern" "$workflow"; then
    echo "CI artifact visual-render gate is missing: $pattern" >&2
    exit 1
  fi
}

require 'brew install --cask libreoffice'
require 'brew install poppler'
require 'CIRCUIT_SOFFICE_PATH="/Applications/LibreOffice.app/Contents/MacOS/soffice"'
require 'CIRCUIT_PDFTOPPM_PATH="$(brew --prefix poppler)/bin/pdftoppm"'
require 'bash scripts/verify_office_visual_render.sh'

echo 'CI requires full Office-compatible artifact rendering for DOCX, XLSX, and PPTX.'
