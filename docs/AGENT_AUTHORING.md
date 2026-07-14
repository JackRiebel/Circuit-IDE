# Agent and connector authoring

Custom agents are declarative local packages. They run only through the Studio
turn runtime, inherit its permission engine, and cannot auto-approve an action.
An agent package is a versioned JSON document placed in CircuitCode's local
agent directory; it never requires a source-code change.

## Create a scoped agent package

1. Start from [the reviewed code-reviewer sample](examples/code-reviewer.agent.json).
2. Give the package a unique lowercase `id`, then set a clear `name`,
   `description`, and bounded `system_prompt`.
3. Declare only the intents, context policy, output contracts, tools, and
   limits needed for the one line of work. An empty tool list means no tools.
4. Keep `auto_approve` false. Never put credentials, connector tokens, or
   customer data in the file.
5. Save the document as `<id>.json` in `~/.config/circuit-ide/agents/`, then
   open **Agents** in CircuitCode to select it for a Studio request.

The app validates the whole document before loading it. Invalid packages remain
unavailable rather than receiving a degraded or inferred capability set.

## Manifest contract

The outer envelope is always:

```json
{
  "kind": "circuit.agent-definition",
  "schemaVersion": 4,
  "payload": { "...": "agent fields" }
}
```

`payload.manifest` is the security contract. It includes:

| Field | Purpose |
| --- | --- |
| `version` and `id` | Stable, versioned identity. Version 1 is the current manifest. |
| `purpose` and `instructions` | Scope and request-local operating guidance. |
| `allowedIntents` | Only `ask`, `review`, `plan`, and `code` work the runtime may route to the agent. |
| `contextPolicy` | `projectOnly`, `selectedFiles`, or `userProvidedOnly`; selected/user-provided context never enables automatic repository retrieval. |
| `allowedTools` | Exact supported tool names. `chat` agents may not declare tools. |
| `outputContracts` | `summary`, `evidence`, `plan`, and/or `patchProposal`. Plan and Code must declare their corresponding reviewable contract and `propose_patch`. |
| `requiredModel` | The selected supported model. Unsupported model capabilities are rejected before send. |
| `limits` | `maxTurns` (1–12), `maxToolCalls` (0–48), and `maxWallTimeSeconds` (10 seconds–30 minutes). |
| `author` | Author and revision for traceability. |

`payload.enabled` is deliberately outside the manifest. Imported and cloned
packages are disabled until an operator reviews their requested tools,
connectors, and risk summary in the Agent Library. This activation state is
local to the installation, not a capability that an imported package can set.

`payload.evaluation_suite` carries package-local task fixtures and a
`minimumPassRate`. Each fixture declares its prompt, allowed Studio intent,
expected output contracts, tool-call ceiling, and whether a citation is
required. CircuitCode evaluates this contract and the operator's permission
review before the Agent Library permits enablement.

Allowed tools are currently `read_file`, `list_files`, `search_files`,
`git_status`, `git_diff`, `git_log`, `propose_patch`, `run_command`, and
`delegate_subagent`.
Declaring a tool does not grant it: every call still passes Studio policy and
the normal review flow. A plan or code package may create only a reviewable
patch proposal; it cannot apply files directly.

`delegate_subagent` is approval-gated. Its call must include one bounded task,
the exact minimal context excerpt to share, and a child tool grant. A child has
no parent transcript or implicit tools. It may receive only workspace reads;
an explicit `allow_reviewed_patch_proposal` plus `propose_patch` grant permits
a reviewable proposal, never a direct file change. The parent receives one
structured summary with tool evidence, artifacts, and unresolved issues rather
than the child's streaming chatter.

## Context, permissions, and outputs

Use `selectedFiles` for reviewers and `userProvidedOnly` for narrowly scoped
assistants. Do not use `projectOnly` merely to let an agent scan more files;
the runtime remains responsible for retrieval and budget decisions.

Network, Git mutation, command execution, patch application, artifacts, and
MCP calls remain separate reviewed capabilities. Custom agents cannot declare
connectors today; a non-empty `allowedConnectors` field is rejected until a
connector has a scoped consent path. This prevents an imported package from
silently gaining a third-party integration.

Output must match the manifest: reviewers should return `summary` and/or
`evidence`; planners must return a `plan`; code agents must return a
`patchProposal`. Return uncertainty and missing evidence explicitly rather
than widening tool access.

## Test and version a package

Before distributing a package:

1. Import it into a clean local agent directory and confirm it appears in the
   Agent Library as **Disabled**. Inspect its requested tools, connectors, and
   risk summary, then enable it explicitly.
2. Use **Test in Studio** to run one allowed request and one disallowed
   request. The latter must be rejected before a provider call or tool
   execution; every test keeps the normal Studio approval flow.
3. Attempt to add an unsupported tool, connector, or auto-approval. Import
   must fail closed.
4. Keep at least one `evaluation_suite` fixture for every supported task type;
   include citation requirements and tool ceilings where the agent needs them.
   An agent whose fixture gate fails cannot be enabled.
5. Exercise tool, turn, and wall-time limits with a fake provider or small
   fixture project.
6. Increase `author.revision` for every behavior change. Use a new `id` for a
   materially different purpose so old task records remain interpretable.

The repository test [agent_manifest_test.dart](../circuit-ide/test/agent_manifest_test.dart)
imports the sample directly and is the reference packaging check.

## Connector and plugin review

MCP server configuration is separate from an agent package. See
[PLUGIN_AUTHORING.md](PLUGIN_AUTHORING.md) for the signed, staged plugin
package format. A connector needs
an explicit user approval, Keychain-backed tokens, a minimal child-process
environment, bounded connection checks, validated tool metadata, and per-call
Studio review. Unknown, mutation-shaped, browser, URL, and network MCP tools
fail closed. Do not distribute a package that asks users to bypass these rules,
paste a token into JSON, or turn on auto-approval.
