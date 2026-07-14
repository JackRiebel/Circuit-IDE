# Provider protocol

CircuitCode provider adapters must convert external model responses into typed
Studio lifecycle data rather than using display text as control flow.

## Version negotiation

Protocol version 1 is the current and minimum compatible CircuitCode provider
contract. Each request sends both `X-Circuit-Protocol-Version: 1` and a
`circuit_protocol` request object with `version` and `minimumCompatible`.

An endpoint may acknowledge the negotiated version with
`x-circuit-protocol-version`. Only a missing acknowledgement is treated as the
version-1 legacy form so existing provider deployments keep working. Once an
endpoint sends the acknowledgement, an empty, non-numeric, or unsupported
version is a hard failure: Studio records a redacted, actionable compatibility
message and does not read the response stream. Administrators must update
either the provider or CircuitCode before retrying.

The connected lifecycle event explicitly records whether that version was an
`explicit acknowledgement` or `legacy v1 compatibility`, without retaining a
response header or provider body. This lets release evidence distinguish a
modern endpoint from the supported legacy form.

Provider protocol changes must be additive and gated by a newer version. They
must not reuse an existing field with a changed meaning.

## Protected staging acceptance probe

`scripts/verify_provider_staging.sh` runs the actual Circuit adapter against a
protected Circuit environment. It requires these secret-capable job variables:

- `CIRCUIT_STAGING_APP_KEY` — the CIRCUIT AppKey, injected by the protected
  environment and never passed on the command line.
- Recommended OAuth mode: `CIRCUIT_STAGING_CLIENT_ID` and
  `CIRCUIT_STAGING_CLIENT_SECRET`. The adapter obtains its own one-hour access
  token from Cisco OAuth and refreshes it if needed during the bounded run.
- Legacy token mode: `CIRCUIT_STAGING_ACCESS_TOKEN`. Set this *instead of* the
  OAuth client pair when a protected runner cannot hold the permanent client
  credentials. The scripts reject ambiguous configurations containing both.
- Optional `CIRCUIT_STAGING_CHAT_BASE_URL` — HTTPS base URL only, with no
  credentials, query, or fragment. It defaults to the documented
  `https://chat-ai.cisco.com/openai/deployments` endpoint.
- Optional `CIRCUIT_STAGING_MODEL` — model identifier; defaults to
  `gpt-5-nano` for the text probe. Set a vision-capable model before running
  the vision probe.

The probe sends one tiny text-only request with no workspace context, tools,
images, or user data. It accepts only a lifecycle that includes request sent,
protocol connection, first byte before first text, textual output, completion,
and a terminal done signal. It emits one redacted JSON line containing the
protocol version, explicit-versus-legacy acknowledgement type, lifecycle kind
names, response character count, and elapsed milliseconds. It never prints
the endpoint path, prompt, response text, headers, token, app key, or provider
diagnostic. An optional `CIRCUIT_STAGING_TIMEOUT_SECONDS` may be set between
10 and 240 seconds.

For a configured model that advertises image input, the same protected
credential variables can run `scripts/verify_vision_staging.sh`. It sends one generated,
two-color PNG through the real adapter, asks for the color occupying its left
half, and refuses a response that does not identify that pixel-only detail.
The retained JSON evidence records only the fixture SHA-256, dimensions,
boolean result, and redacted provider lifecycle; it never includes the model
response, fixture pixels, prompt, endpoint, headers, or credentials.

## Version 1 typed envelopes

Requests carry the selected model, messages, optional system prompt, allowed
tool definitions, temperature, output limit, and the protocol object. Secrets
remain transport credentials and are never part of the persisted request.

## Model capability catalog

Every discovered model records its context window, tool calling, image input,
JSON-schema output, reasoning-control support, and token-accounting semantics.
The connector advertises transport-level image MIME/byte/dimension limits;
Studio intersects those limits with the selected model before constructing a
request. A text-only model therefore cannot receive image pixels or a
tool-enabled task, and a model without reasoning support cannot enable the
Thinking control. The adapter carries the enabled reasoning request as a typed
field; the Circuit OpenAI-compatible adapter serializes it as
`reasoning_effort: "medium"` only for an advertised capable model.

Model catalog fields use the persisted `ConnectorModelInfo` shape so discovery
survives restart. Valid token semantics are `aggregateOnly`, `inputAndOutput`,
and `inputCachedOutputReasoningTool`; UI accounting must never invent detail a
model has not advertised.

### Image inputs

Image pixels cross the adapter boundary only as typed, request-local image
content parts. Before send, Studio validates the selected provider's declared
MIME, byte, and dimension limits; it decodes malformed data, downscales images
that exceed a declared limit, estimates the resulting vision input, and refuses
unsupported models clearly. A provider adapter must keep base64 payloads out of
Studio history, titles, persistent diagnostics, and support exports. The
adapter's payload contract is covered by fixture tests; a deployment still must
be exercised against its configured vision-capable staging model before the
model is presented as vision-enabled in a production release.

Responses are normalized into typed `ChatChunk` and `ProviderStreamEvent`
values for text deltas, tool-call deltas, separate prompt/completion usage,
finish reason, lifecycle events, and errors. An error carries retryability,
status code, request/model identifiers, and only a redacted
diagnostic snippet. A terminal response has one explicit stop/failure reason;
display prose cannot close a Studio turn.

## Request expectations

A request identifies the current task/turn, selected model, user-visible
prompt, scoped context, supported attachments, and only those tools permitted
by the active turn policy. Provider-specific credentials never belong in the
request transcript or task title.

## Streaming expectations

Adapters report incremental text, tool calls, structured usage, errors, and a
terminal reason. Token accounting keeps request input and output separate. A
completion-only usage update must not erase earlier prompt usage. A Circuit
adapter may reconnect exactly once after an HTTP 401 by refreshing its token
before any response stream exists; it emits a typed `reconnecting` lifecycle
event and repeats the request. A second rejected response fails with
`authFailed` rather than retrying indefinitely. It never reconnects after text
or tool bytes, so a reconnect cannot duplicate streamed content or tool
execution.

## Tool expectations

Provider tool calls are parsed into `ToolCallInfo` and evaluated by the local
policy before execution. A provider cannot grant itself write, Git, network,
or connector authority. Unknown MCP capabilities and mutation-shaped connector
calls fail closed until their scoped product path is enabled.

## Compatibility rule

New provider features must add a typed capability and a fixture-backed
contract test before Studio exposes a control for them. Unsupported modalities
or tools must be declined clearly rather than represented as available.
