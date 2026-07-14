#!/usr/bin/env bash
set -euo pipefail

guide="docs/USER_GUIDE.md"
authoring="docs/AGENT_AUTHORING.md"
sample="docs/examples/code-reviewer.agent.json"
plugin_authoring="docs/PLUGIN_AUTHORING.md"
test -f "$guide"
test -f "$authoring"
test -f "$sample"
test -f "$plugin_authoring"

for heading in \
  "Start and organize work" \
  "Choose a task mode" \
  "Review patches and commands" \
  "Add context, images, and artifacts" \
  "Agents and connectors" \
  "Recover from interruption or failure" \
  "Data, diagnostics, and privacy" \
  "Control and failure coverage"; do
  rg -Fq "$heading" "$guide"
done

for heading in \
  "Create a scoped agent package" \
  "Manifest contract" \
  "Context, permissions, and outputs" \
  "Test and version a package" \
  "Connector and plugin review"; do
  rg -Fq "$heading" "$authoring"
done

rg -Fq '"kind": "circuit.agent-definition"' "$sample"
rg -Fq '"schemaVersion": 4' "$sample"
rg -Fq '"kind": "circuit.plugin"' "$plugin_authoring"
rg -Fq 'hmac-sha256' "$plugin_authoring"

echo "CircuitCode user and agent-authoring documentation coverage verified."
