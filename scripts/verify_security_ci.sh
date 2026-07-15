#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/ci.yml"
fixture_workflow=".github/workflows/security-scan-fixture-exercise.yml"
staging_workflow=".github/workflows/provider-staging-acceptance.yml"

if [[ ! -f "$workflow" ]]; then
  echo "Missing required CI workflow: $workflow" >&2
  exit 1
fi

require() {
  local pattern="$1"
  if ! grep -Fq -- "$pattern" "$workflow"; then
    echo "CI security gate is missing: $pattern" >&2
    exit 1
  fi
}

require_fixture() {
  local pattern="$1"
  if ! grep -Fq -- "$pattern" "$fixture_workflow"; then
    echo "CI security fixture exercise is missing: $pattern" >&2
    exit 1
  fi
}

require_staging() {
  local pattern="$1"
  if ! grep -Fq -- "$pattern" "$staging_workflow"; then
    echo "Provider staging acceptance workflow is missing: $pattern" >&2
    exit 1
  fi
}

require 'actions/setup-go@v6'
require 'go-version: "1.26.2"'
require 'go install github.com/zricethezav/gitleaks/v8@v8.29.0'
require '--config=.gitleaks.toml'
require '--redact=100'
require '--log-opts="--all"'
require '--report-format=json'
require 'Gitleaks finding: rule='
require 'google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@v2.3.8'
require 'anchore/sbom-action@v0'
require 'bash scripts/verify_release_entitlements.sh "$APP"'
require 'secret-scan'
require 'dependency-vulnerability-scan'
require 'sbom'
require 'security-events: write'
require 'security-scanner-fixture-exercise:'
require 'github.com/zricethezav/gitleaks/v8@v8.29.0'
require 'github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.3.8'
require 'needs: [product-boundary, flutter-macos, security-red-team, secret-scan, dependency-vulnerability-scan, sbom, security-scanner-fixture-exercise]'
require 'needs.security-scanner-fixture-exercise.result'

if [[ ! -f "$fixture_workflow" ]]; then
  echo "Missing required CI scanner fixture workflow: $fixture_workflow" >&2
  exit 1
fi

require_fixture 'workflow_dispatch:'
require_fixture 'gitleaks-rejects-temporary-fixture'
require_fixture 'gitleaks" dir "$fixture"'
require_fixture 'osv-rejects-temporary-fixture'
require_fixture 'github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.3.8'
require_fixture '--lockfile "osv-scanner:$fixture/osv-scanner-deps.json"'
require_fixture 'scanner_exit" -ne 1'

if [[ ! -f "$staging_workflow" ]]; then
  echo "Missing protected provider staging workflow: $staging_workflow" >&2
  exit 1
fi

if grep -Fq -- 'pull_request:' "$staging_workflow"; then
  echo 'Provider staging acceptance must not run on pull requests.' >&2
  exit 1
fi

require_staging 'workflow_dispatch:'
require_staging 'CIRCUIT_STAGING_APP_KEY: ${{ secrets.CIRCUIT_STAGING_APP_KEY }}'
require_staging 'bash scripts/verify_provider_staging.sh'
require_staging 'bash scripts/verify_vision_staging.sh'
require_staging 'actions/upload-artifact@v6'
require_staging 'provider-staging-evidence-${{ github.run_id }}'
require_staging 'vision-staging-evidence-${{ github.run_id }}'

echo 'Security CI topology, scanner-fixture exercise, and protected provider staging workflow are present.'
