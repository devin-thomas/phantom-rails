# PHR-009 — Active approved corpus and publication revision

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-003, PHR-008

## Goal

Separate operator staging from public visibility, activate only approved release bytes and compute stable revision used by search.

## Scope

- Bind sanitized immutable candidate digest and human approval manifest to `ApprovedRelease`; only active release eligible for public queries.
- - Reprojection of canonical state, safe excerpt constraints and checksummed Corpus Revision; no-op import does not change revision.
- - Atomic activation/rollback of previous approved release when candidate import/qualification fails.

## Acceptance Criteria

- [ ] Unapproved staging items cannot be retrieved from public endpoints, even when they exist in local DB.
- [ ] Tampered approval hash or partial activation prevents publication and retains previous active release.
- [ ] Approved content change updates the revision; replay with no canonical change does not.
- [ ] Public PII-canary regression tests pass against activated and rejected candidates.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
