# Plugin package authoring

CircuitCode plugins are declarative packages. Installing a plugin copies and
validates files only; it does not execute hooks, commands, MCP servers, or
connector setup. Every update is disabled until an operator reviews it.

## Package contract

`manifest.json` uses the versioned envelope below. Every declared component is
a regular, package-relative file; absolute paths, traversal, symbolic links,
and unknown manifest fields are rejected.

```json
{
  "kind": "circuit.plugin",
  "schemaVersion": 1,
  "payload": {
    "id": "review-pack",
    "name": "Review pack",
    "version": "1.2.0",
    "description": "Review workflow definitions.",
    "components": {
      "agents": ["agents/reviewer.agent.json"],
      "skills": ["skills/review.md"],
      "connectors": [],
      "mcpServers": [],
      "commands": ["commands/review.json"],
      "artifactTemplates": ["artifacts/review.json"],
      "hooks": ["hooks/on-install.json"]
    },
    "signature": {
      "algorithm": "hmac-sha256",
      "signerId": "approved-publisher",
      "value": "publisher-generated-signature"
    }
  }
}
```

The signature covers the canonical manifest payload without its `signature`
field. CircuitCode verifies it against a locally trusted publisher key. Do not
put a publisher key, API token, password, or other secret in a package.

## Lifecycle

Install validates the signature and every declared file in a staging directory,
then atomically replaces the previous package. Updates begin disabled and the
previous package remains available for rollback. Uninstall removes the active
package and retained rollback copies. Declared hooks remain data until a future
reviewed hook runtime exists, so a package cannot start an orphan process
during install, update, rollback, or uninstall.

Unsigned legacy manifests are backed up and quarantined; reinstall them as a
signed package from a trusted publisher.
