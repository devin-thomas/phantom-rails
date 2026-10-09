# PHR-004 — Relational provenance model

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-001, PHR-002

## Goal

Implement source, revision, canonical posting, conflict, approval and import history persistence using Active Record and PostgreSQL constraints.

## Scope

- Tables/associations/indexes from SPEC §5.1; immutable source revisions, unique natural mention key, approved release, import run/error and potential duplicate records.
- - Deterministic public opaque ID generation and isolation between private staging and approved public corpus.
- - Migration rollback/development/test reproducibility and consistent PG text search configuration.

## Acceptance Criteria

- [ ] Unique constraints and foreign keys prevent duplicate source revision identity and orphaned evidence under concurrent imports.
- [ ] Migrations run from an empty PG database and can be replayed from clean checkout using the documented DB preparation path.
- [ ] Public IDs do not reveal private source IDs or candidate/account details.
- [ ] No SQLite-mode test path exists.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
