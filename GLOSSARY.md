# Phantom Rails Glossary

Canonical terminology only. This file is not the project brief, decision history, or specification. Exact behavior lives in `SPEC.md`.

## Source Record
A versioned input item from a sanitized historical BriefcaseOS export or an explicitly labeled adversarial fixture. It is evidence to process, not proof of a unique job opening.

## Source Mention
One appearance of a possible job opening within an input, retaining its own evidence. Deterministic matching can associate multiple Source Mentions with one Canonical Posting; uncertain identity is not silently resolved.

## Canonical Posting
The single normalized, searchable representation of one identified real-world job opening, linked to its contributing Source Mentions. Do not treat every mention as a separate posting or silently drop the mentions during consolidation.

## Import Batch
A versioned set of source inputs supplied by a trusted operator to the local CLI or Rails Rake import workflow. Visitors to the public API cannot submit batches.

## Import Report
A record of an import attempt's accepted and invalid items, with explicit counts and understandable error reasons. It distinguishes complete success, partial success, and failure rather than hiding invalid records.

## Invalid Item
A source input that cannot be accepted under the current import rules. It is isolated and explained in the Import Report rather than silently skipped or exposed as a valid Canonical Posting.

## Provenance
Evidence about source mentions and transformations behind a canonical posting, including alternate values, time, source identity, ambiguities and the reason a chosen field value prevailed. Public provenance contains only human-approved safe evidence.

## Public Evidence
A reviewer-safe excerpt, source reference, or issue summary exposed alongside searchable results. It never implies that private messages, real account details, or raw unsanitized sources are public.

## Fixture
A versioned, reproducible input sample used to verify ingestion, normalization, search and failure behavior. Every fixture is clearly labeled either sanitized historical or adversarial synthetic derived from observed source shapes and failure classes.

## Potential Duplicate
A pair of Source Mentions or Canonical Postings with insufficient deterministic evidence to justify consolidation. Such records stay separate and carry a visible uncertainty marker.

## Field Conflict
A disagreement between Source Mentions over the value of a Canonical Posting field. Each retained observation remains traceable even when one value is selected for search/display.

## Release Candidate
An allowlisted, sanitized group of records and public evidence prepared for automated privacy checks and human approval. It is not public merely because an import succeeded.

## Search Cursor
An opaque continuation token associated with a deterministically ordered read-only search result. Its exact stability, expiration and invalid-input behavior are part of the pending API contract.

## Relevance Score
A deterministic query-dependent ranking value computed from documented matches in weighted posting fields. It is derived at search time rather than an independent source of truth, and ordering ties are resolved predictably.

## Import Revision
A discernible version of an imported input's content. Reprocessing an identical revision is idempotent; later revisions may change canonical selections while preserving historical observations and prior import outcomes.

## Import History
Retained evidence of import runs and accepted/corrected input revisions, sufficient to explain which versions contributed to the current searchable corpus without producing duplicate postings on rerun.

## Observation
A field value asserted by one Source Mention at a recorded `observed_at` time, accompanied by an origin class and credibility metadata. An Observation is evidence, not necessarily the selected canonical value.

## Field Selection
The derived choice of a Canonical Posting field from retained credible Observations, together with its explanation and any Field Conflicts. Recency is the default unless independently verified authority or quality justifies an override.

## Identity Tier
A fixed order of evidence strength used to associate a Source Mention with a Canonical Posting. Strong tiers may merge automatically; lower-confidence similarity only flags Potential Duplicates.

## Publication Approval
The operator's explicit approval of the exact digest of a sanitized Release Candidate following automated checks. Approval is tied to those exact bytes; changed content invalidates it.

## Corpus Revision
An opaque digest of the currently approved searchable corpus state, used to identify the dataset against which results and Search Cursors were calculated. No-op imports do not change it.

## Search Result
A Canonical Posting serialized for an anonymous reader with selected safe fields, optional computed Relevance Score, a stable identifier, and approved provenance links.

## Adversarial Fixture
A clearly labeled synthetic test case intentionally modeled on actual data shapes and failure classes, made more difficult to expose correctness or privacy defects. It is never represented as an actual historical job posting.

## Provider Comparison
A manually triggered, quota-bounded comparison of a SerpApi Google Jobs result set with an approved local corpus. It produces a separate report and never automatically modifies or publishes Canonical Postings.

## Core Release
The required verified Rails/PostgreSQL API, trusted importer, privacy gates, reproducible benchmark, interactive documentation, playground and case study. May qualify through an entirely verified local Docker demonstration when live free hosting is unavailable.
