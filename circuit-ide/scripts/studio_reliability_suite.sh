#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== Studio reliability: static checks =="
flutter analyze
git diff --check

echo "== Studio reliability: core contracts =="
flutter test test/studio_core_reliability_contract_test.dart

echo "== Studio reliability: runtime golden paths =="
flutter test test/studio_turn_runtime_flow_test.dart --plain-name "AgentTurnRuntime classified hello stays chat-only and tool-free"
flutter test test/studio_turn_runtime_flow_test.dart --plain-name "AgentTurnRuntime golden path plans, patches, applies, and verifies"
flutter test test/studio_turn_runtime_flow_test.dart --plain-name "AgentTurnRuntime continuation batch completes source accepted plan"

echo "== Studio reliability: UI and workflow regressions =="
flutter test test/studio_shell_v5_test.dart --plain-name "Broad build ideas start discovery before code"
flutter test test/studio_shell_v5_test.dart --plain-name "Streaming assistant draft does not render twice"
flutter test test/studio_shell_v5_test.dart --plain-name "Streaming plan draft renders inside plan card"
flutter test test/studio_shell_v5_test.dart --plain-name "Long streaming plan draft remains bounded in chat"
flutter test test/studio_shell_v5_test.dart --plain-name "Patch verification helper runs suggested checks without model mediation"
flutter test test/studio_shell_v5_test.dart --plain-name "Plan implementation sends structured context and offers next batch after partial apply"
flutter test test/studio_shell_v5_test.dart --plain-name "Studio rail collapses long project histories"
flutter test test/studio_keyboard_journey_test.dart

echo "== Studio reliability: persistence and review recovery =="
flutter test test/studio_thread_test.dart --plain-name "StudioThreadStore reloads partial accepted-plan apply as continuation ready"
flutter test test/studio_thread_test.dart --plain-name "StudioThreadStore reloads patch conflict as review without stale provider error"
flutter test test/studio_v7_drawer_test.dart --plain-name "Studio Diff drawer defaults to selected thread patch history"
flutter test test/studio_v7_drawer_test.dart --plain-name "Studio Diff drawer refreshes conflicted patch in place"
flutter test test/studio_v7_drawer_test.dart --plain-name "Studio Diff drawer explains stale selected patch review"
flutter test test/studio_v7_drawer_test.dart --plain-name "Studio source artifacts quarantine notes but retain explicit selections"

echo "== Studio reliability: suite manifest =="
flutter test test/studio_end_to_end_reliability_suite_test.dart

echo "Studio reliability suite passed."
