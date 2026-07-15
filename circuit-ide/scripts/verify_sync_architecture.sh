#!/usr/bin/env bash
# Guards ADR-0008's local-first boundary and runs only deterministic local
# simulations. This script never contacts a service, creates a sync account,
# uploads project data, or enables a collaboration feature flag.
set -euo pipefail

# Resolve the contract and ADR from the Flutter product root. The ADR links to
# this script with its repository-root path, while CI invokes it from here.
cd "$(dirname "$0")/.."

adr="../docs/adr/0008-local-first-sync-and-collaboration.md"
if [[ ! -f "$adr" ]]; then
  echo "Missing local-first sync ADR: $adr" >&2
  exit 2
fi

for requirement in \
  'Status: Proposed — no remote sync client, endpoint, or background uploader' \
  'Sync is opt-in per project and remains disabled by default.' \
  'No conflict resolver may apply a remote patch, reuse an approval, start a' \
  'Two-device simulations cover append ordering'; do
  if ! grep -Fq -- "$requirement" "$adr"; then
    echo "Local-first sync ADR is missing its required boundary: $requirement" >&2
    exit 1
  fi
done

contract='lib/services/local_first_sync_contract.dart'
if grep -nE -- 'dart:io|HttpClient|Socket|WebSocket|Dio|package:http' "$contract"; then
  echo 'The pre-approval local-first sync contract must not gain a transport dependency.' >&2
  exit 1
fi

encryption='lib/services/local_first_sync_encryption.dart'
if [[ ! -f "$encryption" ]]; then
  echo 'Missing local encrypted-envelope foundation.' >&2
  exit 1
fi
if grep -nE -- 'dart:io|HttpClient|Socket|WebSocket|Dio|package:http' "$encryption"; then
  echo 'The local encrypted-envelope foundation must not gain a transport dependency.' >&2
  exit 1
fi
for requirement in 'AesGcm.with256bits' 'aad:' 'FlutterSecureStorage'; do
  if ! grep -Fq -- "$requirement" "$encryption"; then
    echo "Local encrypted-envelope foundation is missing required control: $requirement" >&2
    exit 1
  fi
done

journal='lib/services/local_first_sync_encrypted_journal.dart'
if [[ ! -f "$journal" ]]; then
  echo 'Missing local encrypted sync journal.' >&2
  exit 1
fi
if grep -nE -- 'HttpClient|Socket|WebSocket|Dio|package:http' "$journal"; then
  echo 'The local encrypted sync journal must not gain a transport dependency.' >&2
  exit 1
fi
for requirement in 'LocalFirstSyncEncryptedJournal' 'LocalFirstSyncEnvelopeCipher' 'rename'; do
  if ! grep -Fq -- "$requirement" "$journal"; then
    echo "Local encrypted sync journal is missing required control: $requirement" >&2
    exit 1
  fi
done

flutter test \
  test/local_first_sync_contract_test.dart \
  test/local_first_sync_encryption_test.dart \
  test/local_first_sync_encrypted_journal_test.dart \
  --reporter expanded

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '%s\n' '### Local-first sync architecture simulations'
    printf '%s\n' 'Validated deterministic migration, excluded-data rejection, bounded canonical JSON envelopes, AES-256-GCM local envelope encryption with secure-store key versioning, atomic encrypted-only journal staging, tamper/missing-key/symlink refusal, rotation recovery and local historical-key retirement, two-device append replay, LWW metadata audit, immutable forks, owner-authorized membership mutation, stricter-policy conflicts, revocation/offline replay, duplicate delivery, and future-schema refusal. No remote transport, account, uploader, sharing UI, or feature flag is enabled.'
  } >> "$GITHUB_STEP_SUMMARY"
fi
