#!/usr/bin/env bash
# Builds, signs, notarizes, staples, and verifies a distributable CircuitCode
# macOS release. This script intentionally fails closed when release identity
# or Apple notarization credentials are unavailable.
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: scripts/release_macos.sh

Required environment variables:
  DEVELOPER_ID_APPLICATION  Full Developer ID Application certificate name
  APPLE_ID                  Apple ID authorized for notarization
  APPLE_TEAM_ID             Apple Developer team identifier
  APPLE_APP_PASSWORD        App-specific password for APPLE_ID
  CIRCUIT_UPDATE_FEED_URL   HTTPS Sparkle appcast URL for this release channel
  CIRCUIT_UPDATE_PUBLIC_ED_KEY
                            Base64 32-byte Sparkle EdDSA public key

The required certificate and its private key must already be present in the
active macOS keychain. The script produces a notarized DMG in dist/macos/.
EOF
  exit 0
fi

: "${DEVELOPER_ID_APPLICATION:?Set the Developer ID Application certificate name.}"
: "${APPLE_ID:?Set the Apple ID used for notarization.}"
: "${APPLE_TEAM_ID:?Set the Apple Developer team ID.}"
: "${APPLE_APP_PASSWORD:?Set an app-specific password for notarization.}"
: "${CIRCUIT_UPDATE_FEED_URL:?Set the signed HTTPS Sparkle appcast URL.}"
: "${CIRCUIT_UPDATE_PUBLIC_ED_KEY:?Set the Sparkle EdDSA public key.}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/circuit-ide"
DIST_DIR="$ROOT_DIR/dist/macos"
APP_PATH="$APP_DIR/build/macos/Build/Products/Release/CircuitCode.app"
DMG_PATH="$DIST_DIR/CircuitCode.dmg"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

for command in flutter codesign hdiutil xcrun spctl; do
  require_command "$command"
done

cd "$APP_DIR"
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build macos --release

[[ -d "$APP_PATH" ]] || {
  echo "Expected release app was not produced: $APP_PATH" >&2
  exit 1
}

# Refuse to sign a distribution where Sparkle is present but its trusted feed,
# public key, opt-in defaults, or data compatibility marker was not embedded.
bash "$APP_DIR/scripts/verify_update_release_configuration.sh" "$APP_PATH"

# Sign nested executables first. Do not use --deep: it can mask an invalid
# nested signature and makes signing behavior non-reviewable.
while IFS= read -r -d '' nested; do
  codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp \
    --options runtime "$nested"
done < <(
  find "$APP_PATH/Contents" -depth \
    \( -name '*.dylib' -o -name '*.framework' -o -name '*.app' -o -perm -111 \) \
    -print0
)

codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp \
  --options runtime \
  --entitlements "$APP_DIR/macos/Runner/Release.entitlements" \
  "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
hdiutil create -volname CircuitCode -srcfolder "$APP_PATH" -ov -format UDZO \
  "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" --wait \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"

echo "Notarized CircuitCode release ready: $DMG_PATH"
