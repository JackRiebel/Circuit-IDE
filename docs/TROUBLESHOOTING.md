# CircuitCode troubleshooting

These steps apply to the supported Flutter desktop app in `circuit-ide/`.
The retired Python applications under `legacy/` are not a recovery path.

## Flutter or dependency setup fails

Confirm the pinned toolchain first:

```bash
flutter --version
```

CircuitCode requires Flutter 3.41.2. From the repository root, then run:

```bash
cd circuit-ide
flutter pub get
flutter analyze
flutter test
```

If macOS dependencies changed, run `flutter clean`, then repeat `flutter pub
get`. Keep the resulting lockfile change only when it was intentional.

## The macOS app does not build or open

Install the current Xcode command-line tools and accept the Xcode license, then
run:

```bash
cd circuit-ide
flutter build macos --release
open build/macos/Build/Products/Release/CircuitCode.app
```

For a source run, use `flutter run -d macos`. The root
`circuit-ide.command` opens the same release app when it exists, otherwise it
starts this Flutter target from source.

## Circuit Company AI cannot connect

Open **Settings** and enter the Circuit credentials again. Credentials are kept
in macOS Keychain; deleting JSON preferences does not restore a missing
credential. Do not paste credentials into a prompt, project file, terminal
output, or issue report.

If requests still fail, collect the connector status, model, HTTP/error category,
and approximate time of the request. Do not attach full prompts, file contents,
or tokens. See [SECURITY.md](SECURITY.md) for diagnostic limitations.

## A task is interrupted or waiting for approval

Pending approvals expire on restart; they are never resumed automatically.
Reopen the task, review the persisted patch/command evidence, then submit a new
request if the action is still wanted. An interrupted patch may remain available
for review or continuation; an incomplete command must be run again with a new
approval.

## A command or tool action is blocked

Studio permits inspection first, reviewable patch proposals, app-side patch
application, and approved verification commands. It blocks secret paths,
outside-workspace access, destructive or privileged shell commands, private
network targets, and undeclared MCP/browser actions. Change the task to a
smaller, workspace-scoped action or inspect the policy message; never work
around the denial by embedding a second shell command or copying a secret into
the prompt.

## Release verification fails

Run the documented local release sequence in [RELEASE.md](RELEASE.md). A local
release build is unsigned. Only the protected signing environment may run
`scripts/release_macos.sh`; do not claim signing or notarization without the
clean-Mac installation evidence described there.
