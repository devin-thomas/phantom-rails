# PHR-015 — Reviewer search playground

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-014

## Goal

Build a polished but bounded frontend consuming the live API rather than fixtures or a second data layer.

## Scope

- Search and compound filters, sort, load/empty/errors, result cards, origin badges, pagination and detail/provenance inspector.
- - Same-origin GET requests; HTML escaping, mobile width 320px, keyboard focus and reduced motion; direct link to docs.
- - Empty/error states must be honest; no user sign-in, data writes, external provider calls or fake success.

## Acceptance Criteria

- [ ] Playground exercises real API on local/hosted server and preserves query/filter state across cursors.
- [ ] A reviewer can inspect why two mentions merged, why another pair did not, and why a field was overridden.
- [ ] Accessibility tests cover keyboard, focus, contrast, reduced motion and 320/390px viewports.
- [ ] API 503/400 and zero matches display distinct, accurate messages without fallback mock results.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
