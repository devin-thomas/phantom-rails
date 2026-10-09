# PHR-016 — Contractual benchmark and attack cases

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-015, PHR-003, PHR-012

## Goal

Qualify the entire import/search/public safety path against the hard cases in SPEC §10 rather than merely asserting unit coverage.

## Scope

- At least 16 named edge-class scenarios, with multiple strong/weak identity cases, corrections, mixed failures, privacy canaries, cursor mutation and provider disabled state.
- - Integration test suite running against actual PostgreSQL; executable HTTP contract examples; generated expected output snapshots that are checked, not hand edited to hide issues.
- - Regression assertions that unapproved imports cannot become public.

## Acceptance Criteria

- [ ] All 16 enumerated SPEC acceptance cases have named tests and real assertions for success and refusal paths.
- [ ] Intentional private canary in a staging input never reaches public API, logs, assets or files.
- [ ] Replay/correction and import partial counts match observed database state, including after shuffled input ordering.
- [ ] Proof includes versioned commands, test outputs and corpus origin labels; failed tests prevent completion.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
