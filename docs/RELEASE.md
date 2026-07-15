# CircuitCode release guide

## Local verification

From `circuit-ide/`:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build macos --release
codesign --display --entitlements :- build/macos/Build/Products/Release/CircuitCode.app
```

The release application should be copied only after the commands above pass.

## Continuous integration

`.github/workflows/ci.yml` first verifies that Flutter is the only root product
entry point and that the clean-clone onboarding documentation is complete. It
then runs a pinned Flutter macOS job that restores packages, checks formatting,
analyzes, tests, builds the release app, inspects entitlements, and uploads the
unsigned app as a CI artifact. A separate required security red-team job runs
the policy-injection, workspace/symlink, command/Git/network/MCP,
child-environment, credential-storage, and audit-redaction suites. The
aggregate CI job fails unless every required gate passes.

Repository administrators must still configure these as required
protected-branch checks. The broader secret, dependency, SBOM, and
signed-artifact scan remains tracked by `CC-REL-002` in the Product Parity
Master Checklist.

## Production signing and notarization

The current build is unsigned for local development. Use
`scripts/release_macos.sh` only in a protected macOS signing environment with
the following environment variables supplied by the secret store:

- `DEVELOPER_ID_APPLICATION`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`
- `CIRCUIT_UPDATE_FEED_URL` — the HTTPS Sparkle appcast for this channel
- `CIRCUIT_UPDATE_PUBLIC_ED_KEY` — the base64 32-byte Sparkle EdDSA public key

The script refuses to proceed without them and then:

1. builds and verifies the Flutter product, including its embedded Sparkle
   framework, trusted HTTPS appcast URL, public signing key, opt-in defaults,
   and data-compatibility marker;
2. signs nested executables and the app with the hardened runtime;
3. verifies the signature;
4. creates a DMG, submits it to Apple notarization, waits for success, and staples
   the ticket.

After the script succeeds, install the DMG on a clean Mac and record the
Gatekeeper/opening result as release evidence.

Do not label a build production-ready, signed, or notarized until that evidence
exists. Before release, copy and complete
[RELEASE_READINESS_CHECKLIST.md](RELEASE_READINESS_CHECKLIST.md), link the
current signed [SECURITY_REVIEW_CHECKLIST.md](SECURITY_REVIEW_CHECKLIST.md),
and store both with the protected release evidence. The remaining production
proof gates are a signed appcast rollout/rollback drill, clean-machine
notarization, the [native macOS acceptance checklist](MACOS_ACCEPTANCE.md),
and the induced-crash privacy audit.

## Signed update channels and rollback

The macOS app uses [Sparkle](https://sparkle-project.org/) for update download,
EdDSA validation, installation, and safe bundle replacement. The Flutter
surface cannot supply an update URL, package path, shell command, or signing
key. It only lets the user choose **Stable** or **Beta**, opt into automatic
checks/downloads, and ask Sparkle to check now. Release defaults are opt-in.
Automatic downloads require automatic checks at the native Sparkle boundary;
turning checks off immediately clears the automatic-download preference.

An appcast must be published over canonical public HTTPS and signed with the
private key that matches `CIRCUIT_UPDATE_PUBLIC_ED_KEY`. Its embedded feed URL
must not contain user credentials, query parameters, or a fragment, so no
access token or expiring per-request URL becomes part of the signed bundle.
Keep that private key only in the protected release-signing system. Each
candidate item must include release notes, a monotonic `sparkle:version`, a
valid Sparkle `sparkle:edSignature`, and a channel: omit `sparkle:channel` for
Stable or set it to `beta` for Beta.
Use a phased rollout interval for Stable until clean-machine and update-drill
evidence is reviewed.

Each release item must also carry a positive data requirement, using the
project appcast namespace, for example:

```xml
<circuit:minimumDataSchema>1</circuit:minimumDataSchema>
```

The app reads this requirement from the signed appcast before download and
refuses a release whose requirement is newer than the embedded
`CircuitDataSchemaVersion`. Bump that bundle value only after migration
fixtures prove that the candidate can safely read the supported historical
records. Do not use an application downgrade as rollback: halt the bad feed
item, preserve user data, and publish a signed hotfix with a higher bundle
version. Record the halted rollout, recovery path, and hotfix evidence in the
release checklist.

For a configured release candidate, run this before Developer ID signing:

```bash
bash circuit-ide/scripts/verify_update_release_configuration.sh \
  circuit-ide/build/macos/Build/Products/Release/CircuitCode.app
```

Then perform the staged update and rollback drill on a clean Mac. This local
verifier proves only that a signed build embeds a valid trust configuration; it
does not replace an actual appcast, notarization, or rollback acceptance run.
