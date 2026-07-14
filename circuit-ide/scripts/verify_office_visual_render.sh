#!/usr/bin/env bash
# Protected-environment acceptance probe for full Office-compatible Word,
# Excel, and PowerPoint renders. It supplements, but does not replace, native macOS
# preview review because LibreOffice is not the customer's native renderer.
set -euo pipefail

renderer="${CIRCUIT_SOFFICE_PATH:-}"
if [[ -z "$renderer" || ! -x "$renderer" ]]; then
  echo 'CIRCUIT_SOFFICE_PATH must point to an executable soffice binary.' >&2
  exit 64
fi

rasterizer="${CIRCUIT_PDFTOPPM_PATH:-}"
if [[ -z "$rasterizer" || ! -x "$rasterizer" ]]; then
  echo 'CIRCUIT_PDFTOPPM_PATH must point to an executable pdftoppm binary.' >&2
  exit 64
fi

text_extractor="${CIRCUIT_PDFTOTEXT_PATH:-$(dirname "$rasterizer")/pdftotext}"
if [[ ! -x "$text_extractor" ]]; then
  echo 'CIRCUIT_PDFTOTEXT_PATH must point to an executable pdftotext binary.' >&2
  exit 64
fi
export CIRCUIT_PDFTOTEXT_PATH="$text_extractor"

flutter test test/artifact_visual_smoke_test.dart \
  --plain-name 'an Office-compatible renderer produces nonblank Excel workbook pages'
flutter test test/artifact_visual_smoke_test.dart \
  --plain-name 'an Office-compatible renderer produces nonblank Word document pages'
flutter test test/artifact_visual_smoke_test.dart \
  --plain-name 'an Office-compatible renderer validates every shipped Word and Excel template'
flutter test test/artifact_visual_smoke_test.dart \
  --plain-name 'Poppler rasterizes every generated PDF page and preserves final customer evidence'
flutter test test/artifact_visual_smoke_test.dart \
  --plain-name 'an Office-compatible renderer produces nonblank PowerPoint slide previews for every shipped template'
flutter test test/artifact_visual_smoke_test.dart \
  --plain-name 'an Office-compatible renderer rejects truncated Word Excel and PowerPoint packages'
flutter test test/zip_package_integrity_test.dart \
  --reporter compact
