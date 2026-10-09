# PHR-007 — Strong identity matching and ambiguity flags

**Status:** Not started  
**Lane:** Core engineering / qualification  
**Dependencies:** PHR-006

## Goal

Consolidate only well-justified duplicate mentions and surface ambiguous pairs without destructive merges.

## Scope

- Implement tier 1 verified employer requisition, tier 2 normalized vetted official URL, tier 3 same platform posting ID, tier 4 weak similarity as flag only.
- - Safe URL normalization that removes known tracking but retains job-identifying path/query values.
- - Stable generation of `PotentialDuplicate` reason/evidence and strong-key conflict isolation.

## Acceptance Criteria

- [ ] Two posts with same employer, title and city but distinct requisition IDs remain separate.
- [ ] Same verified ID across sources merges to one Canonical Posting with two retained Source Mentions.
- [ ] Weak similarity produces two visible postings and a non-sensitive potential-duplicate flag.
- [ ] Contradictory strong identifiers refuse auto-merge and report safe `identity_conflict`.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
