# PHR-011 — PostgreSQL keyword search and filters

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-010

## Goal

Build B-plus search with explainable field weights and compound AND filtering using parameterized PostgreSQL queries.

## Scope

- Query tokenizer, `plainto_tsquery` / GIN search vector, `q`, company/location/remote/employment/salary filters.
- - Fixed weights title 8, company 5, location 3, excerpt 1 per meaningful lexeme, stable score/tie logic, explicit sorts including newest/company/title.
- - Query complexity caps (120 chars/8 lexemes), null-safe salary handling, stable empty-result semantics.

## Acceptance Criteria

- [ ] Multiple lexemes can match across different fields and rank by stated weights.
- [ ] Equivalent data inserted in different order produces identical scored/tied result IDs.
- [ ] Unknown salaries and non-annualized hourly pay cannot satisfy an annual-USD minimum filter.
- [ ] Unsupported filter and malicious SQL-looking input cause safe deterministic errors; no SQL injection.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
