# PHR-014 — Executable API reference

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-010, PHR-011, PHR-012, PHR-013

## Goal

Provide a self-contained documentation route that exercises the actual read-only API and stays consistent with its request/response behavior.

## Scope

- OpenAPI 3.1 spec with list/detail/provenance/meta/health, request/response schemas, 400/404/409/410/503 examples and documented ranking/cursor semantics.
- - Bundled Swagger-like interactive explorer under `/docs` and `/openapi.json` served locally without CDN.
- - Contract tests bind Rails routes and schema to docs, with no publish-time write/auth console.

## Acceptance Criteria

- [ ] From clean local Compose, `/docs` loads without third-party network and executes `GET /api/v1/postings`.
- [ ] Validator accepts OpenAPI 3.1 schema and examples; route parity/known error contract tests pass.
- [ ] Docs clearly identify synthetic versus historical and explain optional external integration not part of read API.
- [ ] No write endpoint is advertised or silently reachable.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
