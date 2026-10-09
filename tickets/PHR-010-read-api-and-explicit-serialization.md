# PHR-010 — API v1 details and safe errors

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-009

## Goal

Expose resource listing, detail, metadata and health without leaking unapproved or raw fields.

## Scope

- GET routes for `/api/v1/postings`, detail, meta and health; versioned response envelopes with stable public IDs and origin labels.
- - Explicit allowlisted serializers, safe 404/400/503 errors and request IDs, zero anonymous write routes.
- - Documented response syntax and request specs; all outputs sourced from the active approved projection.

## Acceptance Criteria

- [ ] Known ID returns normalized metadata, origin class and safe links; missing ID returns 404 without stack trace.
- [ ] Every public response and error passes the serializer allowlist/PII canary scan.
- [ ] Public mutation methods fail without state changes; no hidden admin API is shipped.
- [ ] DB offline returns safe unavailable response instead of fabricated or stale mock results.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
