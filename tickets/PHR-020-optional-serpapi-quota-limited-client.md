# PHR-020 — Optional SerpApi Google Jobs client

**Status:** Not started  
**Lane:** Optional end-stage SerpApi stretch — never a Core Release blocker  
**Dependencies:** PHR-019

## Goal

Implement an entirely opt-in, secret-protected integration for limited provider queries after the core release passes.

## Scope

- `engine=google_jobs`, manual operator invocation, fixed host, response schema validation and safe HTTP failures.
- - Read API key only server-side, hard max 2 searches/run and 20/month with restart-resistant PostgreSQL ledger, no unattended retries, account quota read where safe with secret-bearing response fields never logged.
- - Mock provider transport and 2026 degraded/missing-field cases; no public visitor route and no corpus mutation.

## Acceptance Criteria

- [ ] Zero external requests are made by all default tests, seed commands, anonymous public visits and CI.
- [ ] Missing key, exhausted local budget, provider error, timeout, malformed schema and empty success have distinct results.
- [ ] Key never appears in logs, responses, public site, saved reports or checked-in fixtures.
- [ ] Optional integration does not change any mandated core acceptance or require paid SerpApi tier.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No live API call, paid service or account use unless separately authorized. This optional ticket cannot block PHR-019 or the required core.
