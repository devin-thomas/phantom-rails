# PHR-017 — Clean-checkout qualification and CI

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-016, PHR-001

## Goal

Make the validated stack genuinely portable for a hiring engineer who has no history of the developer machine.

## Scope

- CI with PG service, tests/linters/schema validation/browser checks/security scan; Docker Compose smoke, database setup and approved fixture seed.
- - `bin/verify` or equivalent single local qualification command with a failure exit code, Windows PowerShell notes and safe non-destructive cleanup.
- - Reproducible examples in README, pinned dependencies, release-evidence template.

## Acceptance Criteria

- [ ] Clean checkout container boot, import, test, API query, docs and playground all succeed with approved fixtures.
- [ ] A new developer can run tests without Outlook, SerpApi key, personal files or paid resources.
- [ ] All CI status gates fail properly when core test, privacy scan or OpenAPI contract is deliberately broken.
- [ ] Evidence file records exact code SHA, versions, commands, fixture revision, pass/fail and known limitations.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
