# PHR-008 — Newest-first field selections with authority exceptions

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-007

## Goal

Project canonical fields deterministically from retained observations while explaining significant disagreements.

## Scope

- Validation of title/company/location/pay/type/dates/URLs, stable observed_at comparison, official-host authority from approved manifest only.
- - Newest credible by default; explicit verified official override for conflicting authoritative fields; transparent tie rules and conflict summaries.
- - Recompute selection after corrections without mutating old observations.

## Acceptance Criteria

- [ ] Latest credible non-official evidence wins when no documented quality/authority exception exists.
- [ ] Verified official employer range can override newer third-party range with reason and both values preserved.
- [ ] Unverified spoofed official-looking URL never receives privileged weight.
- [ ] Ties yield identical selection after shuffled insertion order/replayed fixtures.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
