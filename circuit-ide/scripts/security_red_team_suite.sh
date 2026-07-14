#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== Security red-team: policy injection and boundary decisions =="
flutter test test/agent_permission_boundary_test.dart

echo "== Security red-team: disabled computer-use session boundary =="
flutter test test/computer_use_safety_policy_test.dart

echo "== Security red-team: command, Git, connector, and network routes =="
flutter test test/backend_agent_core_test.dart

echo "== Security red-team: command-process cleanup and diagnostic redaction =="
flutter test test/command_run_test.dart \
  --plain-name "CommandTools redacts an unexpected callback error and terminates its child"

echo "== Security red-team: credentialed redirects and DNS boundary enforcement =="
flutter test \
  test/cisco_provider_stream_test.dart \
  test/cisco_token_authenticator_test.dart \
  test/credentialed_transport_redirect_test.dart \
  test/mcp_endpoint_policy_test.dart \
  test/web_tools_test.dart

echo "== Security red-team: patch and symlink escape =="
flutter test test/v3_coding_loop_test.dart \
  --plain-name "PatchProposalController rejects paths that traverse symlinks"
flutter test test/backend_agent_core_test.dart \
  --plain-name "apply_patch_set rejects paths that traverse symlinks"

echo "== Security red-team: child process and MCP secret boundaries =="
flutter test test/child_process_environment_test.dart
flutter test test/mcp_config_security_test.dart
flutter test test/audit_logger_security_test.dart

echo "Security red-team suite passed."
