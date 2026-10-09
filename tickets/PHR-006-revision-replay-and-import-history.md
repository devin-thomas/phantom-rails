# PHR-006 — Idempotent correction and replay

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-005

## Goal

Ensure stable repeated imports, preserve immutable revisions and keep corrections understandable.

## Scope

- Canonical JSON serialization + SHA-256 content revision IDs; mention identity by source-system/source-record/mention key; immutable revision rows and deterministic correction ordering.
- - No-op replay with `ImportRun` evidence but unchanged approved corpus state; changed input adds a revision without erasing old.
- - Fail-closed identity changes and DB fault recovery with accurate report status.

## Acceptance Criteria

- [ ] Identical batch imported twice creates no additional mentions/revisions/postings and no corpus-revision increase.
- [ ] Chronologically separated correction changes selected state while old observation remains retrievable and attributable.
- [ ] Conflicting revisions for same key in a single unordered batch are isolated with `ambiguous_revision_order`.
- [ ] DB fault test shows no successful completion is claimed and active transactional mutations are rolled back.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
