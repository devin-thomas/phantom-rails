# PHR-003 — Privacy-preserving release candidate workflow

**Status:** Complete  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-002

## Goal

Implement a private staging and publication-approval boundary that cannot turn imported personal mail history into public data accidentally.

## Scope

- Allowlist field projection, URL tracking/token stripping, content/excerpt truncation, HTML escaping, secret/PII canaries and safe origin labels.
- - Canonical digest of immutable sanitized candidate, automated static/structural privacy checks, human-reviewed manifest with approval of exact hash.
- - Non-public operator paths and release CLI; private/ excluded from Git, images, logs and documentation.

## Acceptance Criteria

- [x] A candidate containing sensitive emails, redirect tokens, credentials or malicious HTML fails the release gate.
- [x] An exact approved digest is necessary for public release; changed bytes, missing signature/approval or unapproved historical corpus fail closed.
- [x] Negative tests confirm no raw private fields appear in committed fixtures, API projections, CLI errors or UI assets.
- [x] Sanitizer never invents facts or silently replaces sensitive data with plausible-but-false facts.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
