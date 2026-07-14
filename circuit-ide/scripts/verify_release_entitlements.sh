#!/usr/bin/env bash
set -euo pipefail

app_path="${1:?usage: verify_release_entitlements.sh /path/to/CircuitCode.app}"

if [[ ! -d "$app_path" ]]; then
  echo "Release app is missing: $app_path" >&2
  exit 1
fi

echo "== Verify embedded macOS signature =="
codesign --verify --deep --strict --verbose=2 "$app_path"

entitlements="$(mktemp)"
trap 'rm -f "$entitlements"' EXIT
codesign --display --entitlements :- "$app_path" >"$entitlements" 2>/dev/null

reject_entitlement() {
  local key="$1"
  if grep -Fq "<key>${key}</key>" "$entitlements"; then
    echo "Forbidden release entitlement: ${key}" >&2
    exit 1
  fi
}

echo "== Verify reviewed release entitlements =="
reject_entitlement 'com.apple.security.network.server'
reject_entitlement 'com.apple.security.get-task-allow'
reject_entitlement 'com.apple.security.cs.allow-jit'
reject_entitlement 'com.apple.security.cs.disable-library-validation'

if ! grep -A1 -F '<key>com.apple.security.network.client</key>' "$entitlements" | grep -Fq '<true/>'; then
  echo 'CircuitCode must declare network-client access for configured providers.' >&2
  exit 1
fi

echo "== Record signing identity =="
codesign --display --verbose=4 "$app_path" 2>&1 | sed -n '/^Authority=/p;/^TeamIdentifier=/p;/^Signature=/p'

if [[ "${CIRCUIT_REQUIRE_DEVELOPER_ID:-0}" == '1' ]]; then
  if ! codesign --display --verbose=4 "$app_path" 2>&1 | grep -Fq 'Authority=Developer ID Application:'; then
    echo 'Developer ID Application signing is required for a release candidate.' >&2
    exit 1
  fi
fi

echo 'Release entitlement gate passed.'
