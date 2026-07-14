# ADR-0005: Artifact lifecycle

- Status: Accepted
- Date: 2026-07-10

## Context

Generated documents, spreadsheets, slides, and reports are customer-facing
outputs. Chat prose alone cannot make them inspectable or reproducible.

## Decision

Artifacts are typed, structured records with a generated output path and
source composition. The artifact registry selects a renderer; the generated
artifact writer is the only output-routing boundary. Artifact activity is
attached to the originating Studio turn without exposing model-only prompt
text.

## Consequences

New artifact types require registry registration, validation, output tests,
and a reproducible source representation before UI exposure.

## Verification

Artifact writer and workspace-smoke tests verify routing and generated output.
