#!/bin/bash
# Exercises the packaged CircuitExecutionBroker from an ordinary macOS process.
# This must run after a macOS app build, not inside an already sandboxed tool,
# because macOS refuses a second Seatbelt profile in an inherited sandbox.
# macOS 26 also refuses sandbox-exec from a binary located inside an `.app`,
# so this mirrors the app's verified fresh staging to a private runtime path.
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

if ! /usr/bin/codesign --verify --strict "$broker"; then
  echo "Circuit execution broker signature verification failed: $broker" >&2
  exit 65
fi
staged_broker="$root/CircuitExecutionBroker"
cp "$broker" "$staged_broker"
chmod 700 "$staged_broker"
broker="$staged_broker"

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

run_broker_with_network() {
  "$broker" \
    --workspace "$workspace" \
    --network allow \
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

expect_network_allowed() {
  : > "$stdout"
  : > "$stderr"
  if ! run_broker_with_network "$2"; then
    fail "$1 should be permitted with reviewed network access"
  fi
}

expect_network_denied() {
  : > "$stdout"
  : > "$stderr"
  set +e
  run_broker_with_network "$2"
  local status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    fail "$1 unexpectedly succeeded with reviewed network access"
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

# Reviewed network access is mediated by a fresh broker-owned loopback HTTP
# proxy. Its port is intentionally ephemeral; the child receives no direct
# public-network capability or inherited proxy configuration.
expect_network_allowed \
  "loopback-only network proxy environment" \
  'case "$HTTPS_PROXY" in http://127.0.0.1:*) ;; *) exit 82 ;; esac; test "$HTTPS_PROXY" = "$https_proxy"; test "$HTTPS_PROXY" = "$ALL_PROXY"; test -z "$NO_PROXY"'

# A reviewed command may attempt to unset the proxy or ask curl to bypass it.
# Seatbelt still permits only the broker's loopback port, so such direct egress
# must fail before an arbitrary DNS result or public socket can be used.
expect_network_denied \
  "direct network egress bypass" \
  '/usr/bin/curl --noproxy "*" -fsS --connect-timeout 2 --max-time 5 https://example.com/ >/dev/null'

# The normal proxy-aware path remains available after review. The proxy itself
# resolves and pins the public peer; the child only has a loopback socket.
expect_network_allowed \
  "pinned public network egress" \
  '/usr/bin/curl -fsS --connect-timeout 5 --max-time 10 https://example.com/ >/dev/null'

# Network review never authorizes local/private targets. This request reaches
# the loopback proxy first; it must reject its target rather than allowing a
# command to probe a local service through the reviewed network capability.
expect_network_denied \
  "private target through network proxy" \
  '/usr/bin/curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:9/ >/dev/null'

# Network review is for ordinary public unicast only. DNS or a literal URL
# must not make IANA special-purpose addresses reachable through the proxy.
# These fail at the proxy address-policy boundary before an upstream socket is
# opened, so the probes do not contact the listed destinations.
expect_network_denied \
  "IANA special-purpose IPv4 target through network proxy" \
  '/usr/bin/curl -fsS --connect-timeout 2 --max-time 5 http://192.0.0.8/ >/dev/null'

expect_network_denied \
  "deprecated relay IPv4 target through network proxy" \
  '/usr/bin/curl -fsS --connect-timeout 2 --max-time 5 http://192.88.99.2/ >/dev/null'

expect_network_denied \
  "discard-only IPv6 target through network proxy" \
  '/usr/bin/curl -g -fsS --connect-timeout 2 --max-time 5 http://[100::]/ >/dev/null'

expect_network_denied \
  "IETF special-purpose IPv6 target through network proxy" \
  '/usr/bin/curl -g -fsS --connect-timeout 2 --max-time 5 http://[2001:2::]/ >/dev/null'

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

# `/Library` is mutable machine-wide data, not an approved command root. The
# broker may allow a reviewed `/Library/Developer` tool root, but it must never
# turn that narrow runtime exception into general Library metadata access.
expect_denied \
  "unreviewed Library metadata" \
  '/usr/bin/stat /Library >/dev/null'

# The reviewed Command Line Tools root retains only the macOS-owned selector
# it needs. This protects ordinary developer verification without reopening
# general `/Library` machine data.
expect_allowed \
  "reviewed Command Line Tools lookup" \
  '/usr/bin/xcrun --show-sdk-path >/dev/null'

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
