# CircuitCode Flutter desktop app

This directory contains the supported CircuitCode product.

## Development

```bash
flutter pub get
flutter run -d macos
```

Use the pinned Flutter release declared in `pubspec.yaml` (3.41.2). Before
submitting a change, run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build macos --release
```

## Product boundaries

Studio turns are the supported conversational workflow. The app makes a
distinction between read-only inspection, patch proposal, app-side patch
application, command verification, Git mutation, network access, and MCP
dispatch. A model prompt or project instruction is guidance only; client policy
and approval state decide whether a tool may run.

For architecture, provider behavior, credentials, security limitations, and
release instructions, see the repository-level documentation:

- [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md)
- [`../docs/PROVIDER_PROTOCOL.md`](../docs/PROVIDER_PROTOCOL.md)
- [`../docs/SECURITY.md`](../docs/SECURITY.md)
- [`../docs/RELEASE.md`](../docs/RELEASE.md)
