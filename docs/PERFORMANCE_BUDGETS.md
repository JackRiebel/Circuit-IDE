# CircuitCode Performance Budgets

## Status and evidence boundaries

CircuitCode has two performance evidence tiers. They must not be conflated.

1. **Deterministic CI fixtures** protect durable-store and state-update regressions on every change. The exact limits are versioned in `circuit-ide/test/fixtures/performance_budgets.json`; the named `scripts/performance_budget_suite.sh` gate fails if a fixture exceeds its limit.
2. **Packaged release evidence** runs the actual `CircuitCode.app` through LaunchServices after every macOS Release build. `scripts/verify_release_performance_series.sh` invokes the one-shot probe at least five times, validates every redacted sample, and records min/median/nearest-rank-p95/max plus the five raw metric rows, build version, macOS version, architecture, hardware model, and fixture revision. On the recorded reference machine, it also applies the versioned `test/fixtures/release_performance_baseline_macos_arm64.json` p95 guard and fails a material regression. Other hardware reports an explicit baseline skip rather than comparing incomparable measurements.
3. **Release-profile macOS measurements** prove startup, UI-frame pacing, and memory behavior on reference hardware. They are required before CC-PERF-001, CC-PERF-002, and CC-PROJ-003 may be checked off; widget-test timing and a single packaged evidence sample are not substitutes.

## Deterministic CI budget contract

| Metric | Fixture | Limit |
| --- | --- | ---: |
| `task_summary_page_5000` | First 24 task summaries from a 5,000-task JSONL index | 1,000 ms |
| `thread_summary_page_1000` | First 24 thread summaries from a 1,000-thread JSONL index | 1,000 ms |
| `thread_hydration_1000` | Hydrate the selected 1,000-turn durable transcript | 2,000 ms |
| `project_metadata_pages_500` | Page task and thread metadata across 500 projects | 5,000 ms |
| `stream_state_updates_10000` | 10,000 streamed deltas | At most 4 Studio-thread updates |

The suite prints a machine-readable `PERFORMANCE_BUDGET` line for every result. A changed budget requires a documented reason and an updated fixture; it may not be silently relaxed in an individual test.

## Packaged release evidence probe

After `flutter build macos --release`, run the required five-sample collector:

```bash
bash scripts/verify_release_performance_series.sh \
  build/macos/Build/Products/Release/CircuitCode.app 5
```

The collector launches the signed app host through LaunchServices and emits one machine-readable `PACKAGED_RELEASE_PERFORMANCE_SERIES` JSON record. Every raw sample and aggregate field is deliberately limited to `dartMainToFirstFrameMilliseconds`, `projectBindMilliseconds`, `firstStreamFrameMilliseconds`, `streamTenThousandDeltaBurstMilliseconds`, `streamTenThousandDeltaStateUpdates`, `taskSwitchMilliseconds`, `durableReloadMilliseconds`, `taskSummaryPage5000Milliseconds`, `threadSummaryPage1000Milliseconds`, `threadHydration1000Milliseconds`, `projectRecoveryAndMetadata500Milliseconds`, `semanticIndexRebuild1200Milliseconds`, `durableCheckpointPersistenceMilliseconds`, `residentSetBytes`, the timed paced-stream values `streamFrameTimingSampleCount`, `streamFrameBuildP95Milliseconds`, `streamFrameRasterP95Milliseconds`, and `streamFrameTotalP95Milliseconds`, and the virtualized transcript-scroll values `transcriptScrollFrameTimingSampleCount`, `transcriptScrollFrameBuildP95Milliseconds`, `transcriptScrollFrameRasterP95Milliseconds`, and `transcriptScrollFrameTotalP95Milliseconds`; no prompt, source path, project title, provider response, command output, or pixel data is retained. If an unexpected runtime error occurs, the failure stage contains only a fixed lifecycle phase (such as `unexpected_mount_shell`) and never the exception type, message, or stack trace. The 1,200-file semantic-index fixture, task/thread checkpoint fixture, 500-project recovery-and-metadata fixture, and 1,000-turn transcript fixture are created only in the probe's temporary workspace, and their retained evidence is limited to elapsed milliseconds and frame-duration summaries. The paced trace requires at least five real Flutter frames and measures build/raster/total timing after the normal 10,000-delta coalescing burst. The metadata is limited to app build version, macOS version, architecture, hardware model, and the deterministic fixture revision. The macOS CI product gate captures this series in its step summary after the normal packaged-app smoke. `verify_release_performance_probe.sh` remains the underlying one-shot diagnostic for local diagnosis.

This route is repeatable p95 evidence collection. It now captures a packaged worker-isolate semantic-index rebuild, worker-backed recovery plus first-page metadata across 500 durable projects, direct durable checkpoint write, and virtualized 1,000-turn transcript-scroll frame trace in addition to the paced 10,000-delta frame trace. `release_performance_baseline_macos_arm64.json` stores the Mac16,7/arm64/macOS-26 baseline observations, source-fixture revision, and p95 ceilings; it applies only when all of those environment facts match. Set `CIRCUIT_REQUIRE_RELEASE_PERFORMANCE_BASELINE=1` for a release-candidate run that must fail rather than skip on a nonmatching machine. This does not establish clean-machine acceptance or replace retained timeline traces.

## Release-profile acceptance targets

Reference hardware is an Apple-silicon Mac with 16 GB RAM running a supported macOS release, with the production build installed locally and no debugger attached. Capture at least five runs for each scenario, retain raw traces outside the repository's customer data, and record median plus p95.

| Metric | Acceptance target | Scenario |
| --- | ---: | --- |
| Cold launch to interactive Studio | p95 <= 2.5 s | Fresh process, persisted 500-project index available |
| Initial project metadata page | p95 <= 300 ms | 5,000 tasks; no transcript hydration |
| 500-project rail recovery and first metadata pages | p95 <= 5 s | Recover durable paths in the worker, then page two task/thread rows per project |
| Task switch | p95 <= 200 ms | Switch between two already-indexed tasks |
| First streamed text paint | p95 <= 150 ms | From received first provider-text byte; network time excluded |
| Transcript scroll frame | p95 <= 16.7 ms | 1,000-turn transcript at 60 Hz while no stream is active |
| Streaming frame | p95 <= 16.7 ms | 10,000-delta fixture while composer remains interactive |
| Resident memory | <= 450 MB | 5,000 tasks plus selected 1,000-turn transcript |
| File index rebuild | p95 <= 10 s | 1,200 source files with bounded content indexing |
| Durable task/thread persistence | p95 <= 500 ms | Save metadata and selected-thread checkpoint |

### Required release evidence

For each release candidate, collect a release-profile timeline trace and the macOS memory sample for every scenario above. Attach the evidence location, build hash, macOS version, hardware, fixture revision, and raw median/p95 values to the release readiness checklist. Any target breach blocks stable release unless the exception records user impact, owner, mitigation, and an expiry.

These targets deliberately do not define network/provider latency. Provider timing is recorded separately from first-byte through first-text lifecycle diagnostics.
