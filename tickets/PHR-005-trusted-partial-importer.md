# PHR-005 — CLI/Rake trusted partial importer

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-003, PHR-004

## Goal

Ingest a parseable mixed-quality approved batch with item-level atomicity and complete failure accounting, without public HTTP writes.

## Scope

- Rake/CLI `phantom:import` or equivalent; JSON/JSONL parsing; required version/readiness checks; transaction per valid item; operator-safe per-item error codes.
- - `ImportRun` complete/partial/failed state and input/inserted/updated/unchanged/invalid counts; quarantine errors without raw payload.
- - Duplicate conflicting revisions in one unordered batch rejected for that identity, independent rows processed.

## Acceptance Criteria

- [ ] A mixed sample containing 43 valid and 7 invalid records accepts precisely the independent valid rows and reports `partial` (illustrative fixture size).
- [ ] Unreadable or unsupported whole batch writes no records and reports an explicit failure.
- [ ] Public routes expose no import endpoint; POST/PUT/PATCH/DELETE cannot create data.
- [ ] All item outcomes are accounted for, and raw rejected payloads never enter logs or public tables.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
