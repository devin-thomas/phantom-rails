# PHR-002 — Versioned source contract and hard fixtures

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-001

## Goal

Define a strict, independently parsable sanitized source format and representative fixture corpus based on the known BriefcaseOS input *shapes*, not fake claims of historical source.

## Scope

- JSON Schema `batch-v1` for envelope and JSONL equivalents; stable source record/mention keys, explicit origin class, observed_at versus claimed posting date, enums/length caps and safe URI fields.
- - Deterministic fixture loader and synthetic adversarial suite covering tracking links, disagreement, missing fields, Unicode, malformed versions, separate requisitions, corrected revisions and PII canaries.
- - Real BriefcaseOS export, when provided, remains private and is never copied into tracked fixtures before sign-off.

## Acceptance Criteria

- [ ] Fixture suite includes multiple companies, sources, locations and revisions and is explicitly labeled synthetic where appropriate.
- [ ] Malformed unsupported versions fail as **batch errors**; malformed individual objects are identifiable as per-item errors after parse.
- [ ] Schema rejects unknown input keys, invalid time zones, enum values and malformed payloads with stable error codes.
- [ ] Tests demonstrate an external observed timestamp differs from the import timestamp.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
