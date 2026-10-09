# PHR-013 — Source evidence and reconciliation inspection

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-008, PHR-010

## Goal

Make merge decisions, field conflicts and potential duplicates inspectable safely through real public GET routes.

## Scope

- `/api/v1/postings/:id/provenance` with safe source refs/excerpts, origin labels, selected fields and reason codes.
- - Approved alternative values and dates, merge evidence tier, ambiguity explanation, no direct private message links.
- - Deterministic order and truncated plain-text descriptions.

## Acceptance Criteria

- [ ] Conflict test shows chosen value, alternative, source quality/timestamp and selection reason without raw private body.
- [ ] Strong-match job detail links all contributing public source mentions; potential duplicates stay separate.
- [ ] Private source ID, original Outlook link, tracker URL and canary never serialize.
- [ ] Unknown reference yields safe 404 and no information about unapproved rows.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
