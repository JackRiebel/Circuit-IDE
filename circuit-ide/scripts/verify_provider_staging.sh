#!/usr/bin/env bash
# Runs the real Circuit adapter only against an explicitly configured protected
# staging environment. This is deliberately not a normal PR gate: credentials
# belong in the secret-capable staging/release job, never in source or logs.
set -euo pipefail

required=(
  CIRCUIT_STAGING_APP_KEY
)

missing=0
for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required protected staging variable: $key" >&2
    missing=1
  fi
done
if (( missing != 0 )); then
  echo 'Provider staging verification was not started; no credential values were read or printed.' >&2
  exit 64
fi

access_token="${CIRCUIT_STAGING_ACCESS_TOKEN:-}"
client_id="${CIRCUIT_STAGING_CLIENT_ID:-}"
client_secret="${CIRCUIT_STAGING_CLIENT_SECRET:-}"
if [[ -n "$access_token" && ( -n "$client_id" || -n "$client_secret" ) ]]; then
  echo 'Configure either CIRCUIT_STAGING_ACCESS_TOKEN or the CIRCUIT_STAGING_CLIENT_ID/CIRCUIT_STAGING_CLIENT_SECRET pair, not both.' >&2
  exit 64
fi
if [[ -z "$access_token" && ( -z "$client_id" || -z "$client_secret" ) ]]; then
  echo 'Missing protected Circuit credential mode: set CIRCUIT_STAGING_ACCESS_TOKEN, or both CIRCUIT_STAGING_CLIENT_ID and CIRCUIT_STAGING_CLIENT_SECRET.' >&2
  exit 64
fi

exec dart run tool/provider_staging_probe.dart
