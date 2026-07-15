# CircuitCode

CircuitCode is a private, macOS-first AI workspace for planning, researching,
reviewing code, preparing patches, running approved verification, and creating
structured business artifacts. The supported application is the Flutter
desktop product in [`circuit-ide/`](circuit-ide/).

The retired Python GUI, TUI, CLI, and historical plans now live in
[`legacy/`](legacy/) for reference only. They are not supported, packaged,
launched, or used for release validation.

## Run CircuitCode

Requirements:

- macOS with Xcode command-line tools
- Flutter 3.41.2 (Dart 3.11.0)
- Git

```bash
git clone https://github.com/JackRiebel/Circuit-IDE.git
cd Circuit-IDE/circuit-ide
flutter pub get
flutter run -d macos
```

On macOS, double-click `circuit-ide.command` at the repository root to open an
existing Flutter release build, or start the same Flutter application from
source when no build is present.

For a release-style local build:

```bash
cd circuit-ide
flutter analyze
flutter test
flutter build macos --release
```

The built application is at
`circuit-ide/build/macos/Build/Products/Release/CircuitCode.app`.

## Credentials and privacy

Configure Circuit Company AI credentials from **Settings** in the app. CircuitCode
stores credentials in macOS Keychain through `flutter_secure_storage`; it does
not intentionally store API secrets in its JSON preferences. Existing legacy
credential preferences are migrated only after Keychain storage succeeds.

Do not place credentials in project instruction files, chat messages, source
files, or `.env` files exposed to a task. Studio policy blocks direct reads of
common secret paths and removes ambient secret variables from agent-launched
commands and MCP child processes.

## Repository guide

- [`circuit-ide/`](circuit-ide/) — supported Flutter desktop application
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — current runtime boundaries
- [`docs/PROVIDER_PROTOCOL.md`](docs/PROVIDER_PROTOCOL.md) — provider event and
  capability expectations
- [`docs/SECURITY.md`](docs/SECURITY.md) — current controls and open security
  limitations
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — setup, provider,
  approval, policy, and release recovery
- [`docs/RELEASE.md`](docs/RELEASE.md) — build, CI, signing, and release steps
- [`docs/RELEASE_READINESS_CHECKLIST.md`](docs/RELEASE_READINESS_CHECKLIST.md)
  — required per-release evidence and sign-off record
- [`docs/SECURITY_REVIEW_CHECKLIST.md`](docs/SECURITY_REVIEW_CHECKLIST.md)
  — quarterly threat-model/control review and incident exercise
- [`docs/CIRCUITCODE_PRODUCT_PARITY_MASTER_CHECKLIST.md`](docs/CIRCUITCODE_PRODUCT_PARITY_MASTER_CHECKLIST.md)
  — evidence-based product-parity work ledger

## Contributing

Every product change must keep `flutter analyze`, the relevant test suite, and
the macOS build green. Do not mark a product-parity checklist item complete
until its implementation and verification gates are both satisfied.
