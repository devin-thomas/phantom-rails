# PHR-012 — Signed deterministic cursor pagination

**Status:** Complete  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-011, PHR-009

## Goal

Support stateless keyset pages without duplicates, query drift or mixed publication revisions.

## Scope

- Token with sort tuple, normalized query digest, corpus revision, TTL, signature; keyset SQL for all sorts and nullable values.
- Limit default 20/max 50; stable final ID tie; 400 invalid/mismatch, 409 stale, 410 expired.
- More than one page of fixtures for tied ranking/sort values.

## Acceptance Criteria

- [x] Page boundary tests return every qualifying ID exactly once for stable corpus and stable order.
- [x] Changing filter, tampering cursor or replaying signed token with new query produces 400.
- [x] Expiring a cursor produces 410; activating a changed corpus produces 409.
- [x] No cursor contains secret source data or identifiers; page end has `next_cursor: null`.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
