# PHR-018 — Hosting qualification and approved release gate

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-017

## Goal

Evaluate free Rails/PG hosting realistically and complete one authorized Core Release path without exceeding the spending boundary.

## Scope

- Verify candidate free web + durable enough PostgreSQL, database persistence/cold start, deployment source, release approval manifest and error/observability.
- - Consider Render or Koyeb web with appropriate independent PG; verify student Hostinger plan rather than assuming a VPS.
- - If none qualifies at $0, document blocker and complete verified Docker-only release; **do not buy, deploy or publish without owner approval**.

## Acceptance Criteria

- [ ] A hosting comparison records technical capabilities, monthly cost, uptime/cold-start assumptions and why Render free 30-day PG was rejected for durable storage.
- [ ] Owner-approved live deployment (if authorized) serves exactly the digest-approved corpus and passes HTTPS API/docs/playground smoke tests.
- [ ] If live is blocked, CORE-LOCAL certificate points to a working Docker demo and explicitly states public URL not verified.
- [ ] No provider charge, API key, credentials, or live resources are created from the build plan alone.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
