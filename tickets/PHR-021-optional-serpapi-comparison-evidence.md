# PHR-021 — Optional live-versus-historical comparison

**Status:** Not started  
**Lane:** Optional end-stage SerpApi stretch — never a Core Release blocker  
**Dependencies:** PHR-020

## Goal

Compare a bounded live SerpApi result set to approved local postings using explainable logic and retain a safe, opt-in report without publishing provider raw records.

## Scope

- Map Google Jobs fields to temporary normalized observations; compare matched, uncertain, unmatched and conflicting values with provenance labels.
- - Manual one-off comparison command with provider credits explicitly authorized; produce a sanitizable report separate from Canonical Posting import.
- - Report quota impact and external schema/availability limitations; no scheduled ingestion.

## Acceptance Criteria

- [ ] Mocked comparison produces deterministic matched/uncertain/unmatched counts and field difference reason codes.
- [ ] Running comparison does not add or alter source revisions, canonical postings or Corpus Revision.
- [ ] Live run requires user-supplied key and separately authorized quota; absent that, ticket is safely marked `optional-unverified` without blocking core release.
- [ ] Provider errors never turn into false claims that a matching job does not exist.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No live API call, paid service or account use unless separately authorized. This optional ticket cannot block PHR-019 or the required core.
