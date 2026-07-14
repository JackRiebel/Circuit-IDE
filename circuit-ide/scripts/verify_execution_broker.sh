#!/bin/bash
# Exercises the packaged CircuitExecutionBroker from an ordinary macOS process.
# This must run after a macOS app build, not inside an already sandboxed tool,
# because macOS refuses a second Seatbelt profile in an inherited sandbox.
set -euo pipefail

broker="${1:-}"
if [[ -z "$broker" ]]; then
  echo "Usage: bash scripts/verify_execution_broker.sh /path/to/CircuitExecutionBroker" >&2
  exit 64
fi
if [[ ! -x "$broker" ]]; then
  echo "Circuit execution broker is missing or not executable: $broker" >&2
  exit 66
fi

root="$(mktemp -d "${TMPDIR:-/tmp}/circuit-broker-harness.XXXXXX")"
workspace="$root/workspace"
outside="$root/outside"
stdout="$root/stdout"
stderr="$root/stderr"

cleanup() {
  rm -rf "$root"
}
trap cleanup EXIT

mkdir -p "$workspace" "$outside"
printf 'workspace-visible\n' > "$workspace/input.txt"
printf 'outside-secret\n' > "$outside/secret.txt"
ln -s "$outside/secret.txt" "$workspace/escape-link"
export CIRCUIT_BROKER_HARNESS_SECRET='must-not-reach-child'
# The broker must not carry host-specific lookup or terminal metadata into a
# model-approved command. Keep the normal system lookup path after the marker
# so this harness itself remains portable.
export PATH="$outside/path-sentinel:${PATH}"
export TERM='broker-harness-term-sentinel'
expected_broker_denial='Circuit execution broker denied launch. Check the execution boundary and try again.'

run_broker() {
  "$broker" \
    --workspace "$workspace" \
    --network deny \
    --cpu-limit 10 \
    -- /bin/sh -c "$1" \
    >"$stdout" \
    2>"$stderr"
}

fail() {
  echo "Execution broker harness failed: $1" >&2
  if [[ -s "$stdout" ]]; then
    echo "--- broker stdout ---" >&2
    cat "$stdout" >&2
  fi
  if [[ -s "$stderr" ]]; then
    echo "--- broker stderr ---" >&2
    cat "$stderr" >&2
  fi
  exit 1
}

expect_allowed() {
  : > "$stdout"
  : > "$stderr"
  if ! run_broker "$2"; then
    fail "$1 should be permitted"
  fi
}

expect_denied() {
  : > "$stdout"
  : > "$stderr"
  set +e
  run_broker "$2"
  local status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    fail "$1 unexpectedly succeeded"
  fi
}

expect_allowed \
  "workspace read/write" \
  'value="$(cat input.txt)"; test "$value" = "workspace-visible"; printf "broker-created\n" > output.txt; test -f output.txt'
if grep -q 'Error opening /private/var/select/sh' "$stderr"; then
  fail "system-selected shell was denied by the Seatbelt profile"
fi

expect_allowed \
  "sanitized child environment" \
  'test -z "${CIRCUIT_BROKER_HARNESS_SECRET-}"; test "$PATH" = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"; test "$TERM" = "dumb"; case "$HOME" in *broker-tmp-*) exit 0 ;; *) exit 81 ;; esac'

expect_allowed \
  "core dumps disabled" \
  'test "$(ulimit -c)" = "0"'

expect_allowed \
  "process and output-file resource limits" \
  'test "$(ulimit -u)" -le 512; test "$(ulimit -f)" -le 524288'

# A repository can contain its own `.circuitcode` entry. It must never turn
# the broker's private temporary directory into an outside-workspace sandbox
# allowance through a symlinked parent.
symlink_workspace="$root/symlink-workspace"
mkdir -p "$symlink_workspace"
ln -s "$outside" "$symlink_workspace/.circuitcode"
: > "$stdout"
: > "$stderr"
set +e
"$broker" \
  --workspace "$symlink_workspace" \
  --network deny \
  --cpu-limit 10 \
  -- /bin/sh -c 'exit 0' \
  >"$stdout" \
  2>"$stderr"
temporary_symlink_status=$?
set -e
if [[ "$temporary_symlink_status" -eq 0 ]]; then
  fail "temporary-directory symlink unexpectedly succeeded"
fi
if ! grep -Fxq "$expected_broker_denial" "$stderr"; then
  fail "temporary-directory symlink did not return the safe broker denial"
fi
if find "$outside" -name 'broker-tmp-*' -print -quit | grep -q .; then
  fail "temporary-directory symlink created an outside broker directory"
fi

expect_denied "outside-workspace read" 'cat ../outside/secret.txt >/dev/null'
expect_denied "symlink escape read" 'cat escape-link >/dev/null'
expect_denied "outside-workspace write" 'printf forbidden > ../outside/escaped.txt'
if [[ -e "$outside/escaped.txt" ]]; then
  fail "outside-workspace write created a file"
fi

# PATH entries are only executable lookup hints. A compromised host process
# must not turn an entry such as `/` into a blanket read/execute grant.
: > "$stdout"
: > "$stderr"
set +e
"$broker" \
  --workspace "$workspace" \
  --network deny \
  --cpu-limit 10 \
  --tool-root / \
  -- /bin/sh -c 'exit 0' \
  >"$stdout" \
  2>"$stderr"
unsafe_tool_root_status=$?
set -e
if [[ "$unsafe_tool_root_status" -eq 0 ]]; then
  fail "untrusted tool root unexpectedly succeeded"
fi
if ! grep -Fxq "$expected_broker_denial" "$stderr"; then
  fail "untrusted tool root did not return the safe broker denial"
fi

# Broker argument failures are forwarded through Studio command stderr. Keep
# their diagnostic useful without exposing a caller path or command text.
denial_workspace="$root/broker-launch-denial-path-sentinel"
: > "$stdout"
: > "$stderr"
set +e
"$broker" \
  --workspace "$denial_workspace" \
  --network deny \
  --cpu-limit 10 \
  -- /bin/sh -c 'printf broker-launch-denial-command-sentinel' \
  >"$stdout" \
  2>"$stderr"
launch_denial_status=$?
set -e
if [[ "$launch_denial_status" -eq 0 ]]; then
  fail "broker launch denial unexpectedly succeeded"
fi
if ! grep -Fxq "$expected_broker_denial" "$stderr"; then
  fail "broker launch denial did not return the safe diagnostic"
fi
if grep -Fq 'broker-launch-denial-path-sentinel' "$stderr" ||
   grep -Fq 'broker-launch-denial-command-sentinel' "$stderr"; then
  fail "broker launch denial exposed request details"
fi

# The default-deny Seatbelt profile has no process-inspection capability.
expect_denied "unrelated process inspection" '/bin/ps -p 1 -o pid='

# System and user Keychain stores are not command inputs. The broker grants
# system runtime roots for executable resolution, so assert that its explicit
# Keychain deny remains effective before a reviewed process can inspect the
# system store's metadata. This never reads an item or creates a credential.
expect_denied \
  "system Keychain metadata" \
  '/usr/bin/stat /Library/Keychains >/dev/null'

# A direct public request is deliberately used instead of a private fixture so
# this verifies the broker's outbound-network denial rather than URL policy.
expect_denied \
  "network egress" \
  '/usr/bin/curl -fsS --connect-timeout 2 --max-time 5 https://example.com/ >/dev/null'

echo "Execution broker escape harness passed"
