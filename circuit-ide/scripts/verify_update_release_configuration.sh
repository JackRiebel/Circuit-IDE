#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-build/macos/Build/Products/Release/CircuitCode.app}"
info_plist="$app_path/Contents/Info.plist"

if [[ ! -f "$info_plist" ]]; then
  echo "Missing packaged app Info.plist: $info_plist" >&2
  exit 1
fi

if [[ ! -d "$app_path/Contents/Frameworks/Sparkle.framework" ]]; then
  echo "Sparkle.framework is not embedded in $app_path" >&2
  exit 1
fi

feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info_plist" 2>/dev/null || true)"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist" 2>/dev/null || true)"
automatic_checks="$(/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$info_plist" 2>/dev/null || true)"
automatic_updates="$(/usr/libexec/PlistBuddy -c 'Print :SUAutomaticallyUpdate' "$info_plist" 2>/dev/null || true)"
data_schema="$(/usr/libexec/PlistBuddy -c 'Print :CircuitDataSchemaVersion' "$info_plist" 2>/dev/null || true)"

if ! /usr/bin/python3 - "$feed_url" <<'PY'
import sys
from urllib.parse import urlsplit

value = sys.argv[1]
try:
    parsed = urlsplit(value)
    host = (parsed.hostname or '').lower()
except ValueError:
    raise SystemExit(1)

valid = (
    parsed.scheme.lower() == 'https'
    and bool(host)
    and '@' not in parsed.netloc
    and not parsed.query
    and not parsed.fragment
    and host != 'example'
    and not host.startswith('example.')
    and '.example.' not in host
)
raise SystemExit(0 if valid else 1)
PY
then
  echo 'SUFeedURL must be a canonical public HTTPS appcast URL without credentials, query, fragment, or example host.' >&2
  exit 1
fi

if ! /usr/bin/python3 - "$public_key" <<'PY'
import base64
import sys

try:
    key = base64.b64decode(sys.argv[1], validate=True)
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if len(key) == 32 and any(key) else 1)
PY
then
  echo 'SUPublicEDKey must be a non-zero 32-byte base64 EdDSA public key.' >&2
  exit 1
fi

if [[ "$automatic_checks" != 'false' ]] || [[ "$automatic_updates" != 'false' ]]; then
  echo 'Release defaults must keep automatic checks and download opt-in.' >&2
  exit 1
fi

if [[ ! "$data_schema" =~ ^[1-9][0-9]*$ ]]; then
  echo 'CircuitDataSchemaVersion must be a positive release compatibility version.' >&2
  exit 1
fi

echo "Verified signed update configuration for $app_path"
