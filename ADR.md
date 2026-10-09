# Phantom Rails — Architecture Decision Record

## ADR-001 — Independent Ruby on Rails portfolio demonstration

**Status:** Accepted

**Decision:** Build Phantom Rails as a standalone Rails search API with an accessible public demonstration; it is not coupled to the running BriefcaseOS product.

**Rationale:** Demonstrate backend fluency and resilient search/data-engineering habits for a software-engineering audience after an already-submitted application.

**Consequences:** Self-contained setup and tests; no dependency on an Outlook account or live BriefcaseOS service.

## ADR-002 — Reality-grounded, safely publishable fixtures

**Status:** Accepted

**Decision:** Use a sanitized historical BriefcaseOS export as the primary shape/evidence basis. Allow clearly labeled adversarial synthetic data to extend real observed failure classes beyond the tidy source cases, without pretending it is historical.

**Rationale:** Authentic data problems are more convincing than a convenient toy dataset, while private inputs must not be published.

**Consequences:** A nontrivial sanitation/release gate is required; missing local historic exports must not be silently invented. Exact public provenance boundaries will be resolved in Round 2.

## ADR-003 — Demonstrate normalization, provenance and visible failures

**Status:** Accepted

**Decision:** The first technical scope includes fixture ingestion, normalization, searchable results, provenance and explicit error handling, rather than a thin CRUD-only search API.

**Rationale:** These behaviors mirror difficult, real API-consumption workflows and make the demo worthwhile to a SerpApi engineer.

**Consequences:** Acceptance tests must include messy cases and failure evidence. Exact identity and recovery rules remain open.

## ADR-004 — Public developer experience without visitor accounts

**Status:** Accepted

**Decision:** Offer a public API, executable API documentation, and a small search playground without requiring visitor registration.

**Rationale:** The reviewer must be able to try the work quickly. Documentation and visual exploration serve different audiences and both are useful.

**Consequences:** Whether imports are available through a separate protected write interface or exclusively offline remains undecided; 'no accounts' does not imply anonymous public data mutation.

## ADR-005 — Optional SerpApi integration at the end

**Status:** Accepted

**Decision:** After the independent core is complete, include clearly marked optional SerpApi integration work as the last stretch of the ticket plan, using the advertised free plan when appropriate.

**Rationale:** Demonstrates ability to integrate with SerpApi itself, without forcing external quota spending during local development or basic portfolio review.

**Consequences:** Key handling, caching, rate and credit caps, and the precise provider workflow require later discovery. Live SerpApi calls are not a core acceptance requirement.

## ADR-006 — Canonical posting with retained source mentions

**Status:** Accepted

**Decision:** Represent one identified real-world job opening as one Canonical Posting, retaining links to all associated Source Mentions rather than collapsing and discarding duplicate evidence.

**Rationale:** Reviewers need a useful non-duplicated search result without losing the independent observations that explain and potentially contradict it.

**Consequences:** Preserve mention-level traceability. Matching heuristics, ambiguous candidates, and conflicting field precedence must be decided separately in Round 3.

## ADR-007 — Trusted versioned CLI/Rake ingestion, read-only public API

**Status:** Accepted

**Decision:** Import source batches using a trusted local CLI or Rails Rake task, with explicit batch versions. Expose only public read operations to visitors; the API and playground have no visitor account or public data-ingestion surface.

**Rationale:** Keeps an inspectable portfolio demonstration independent of an operational ingestion service, avoiding unnecessary write security and spam costs.

**Consequences:** Document a repeatable operator import path and ensure there is no public write route. Future protected administrative import would require a separate scoped decision.

## ADR-008 — Partial-success import with explicit invalid-item reporting

**Status:** Accepted

**Decision:** Accept valid items from a parseable mixed-quality batch while isolating invalid items into an explicit report. Never label partial acceptance as complete batch success.

**Rationale:** Real imported datasets contain imperfect records; one bad item need not block good data, but the errors must be diagnosable and recoverable.

**Consequences:** Batch reports must disclose accepted/invalid counts and reasons, and tests must cover mixed outcomes. Reprocessing, report persistence, and unreadable-batch semantics remain open.

## ADR-009 — Public-safe excerpts, source references and issue summaries

**Status:** Accepted

**Decision:** Publish deliberately sanitized source excerpts, safe references and issue summaries as the inspectable provenance layer. Never publish confidential source emails, personal job-search activity, hidden internal identifiers or credentials.

**Rationale:** The point of a provenance demonstration is explainability without exposing private BriefcaseOS history.

**Consequences:** Introduce a release/sanitization gate to be determined in Round 3. Public API responses must not simply serialize private source records.

## ADR-010 — Deterministic, conservative record reconciliation

**Status:** Accepted

**Decision:** Use tiered deterministic evidence to associate Source Mentions with a Canonical Posting. Keep uncertain potential duplicates as separate records with an explicit flag, rather than automatically merging on weak similarity.

**Rationale:** A false merge can destroy important provenance and make legitimate distinct vacancies disappear; false non-merges remain visible and explainable.

**Consequences:** Store/reveal candidate-match uncertainty safely, test both false-positive and false-negative scenarios, and specify the exact evidence tiers before implementation. This resolves the matching-policy question left open in ADR-006.

## ADR-011 — Newest credible evidence by default, with authoritative exceptions

**Status:** Accepted

**Decision:** Select canonical field values from the newest credible observation by default. Significant source-authority or source-quality evidence can override recency—for example, a verified official employer posting disagreeing with a third-party job board. Retain all conflicting observations and record the selection rationale instead of silently overwriting them.

**Rationale:** Freshness is usually informative but not an adequate substitute for reliable source authority or demonstrably correct data.

**Consequences:** Use field-level, explainable precedence; preserve source timestamps and conflict summaries; determine precise verification, tie-break and override thresholds during specification or remaining discovery. Do not hard-code a universal 'latest always wins' rule.

## ADR-012 — Explicit approval before public data release

**Status:** Accepted

**Decision:** Prepare source exports with a strict field allowlist and sanitization, run automated privacy checks, and require human approval before releasing any historical or derived public dataset. Importing records is not equivalent to approving their publication.

**Rationale:** The original BriefcaseOS corpus contains private context and potentially identifying information that must never become visible through the portfolio API, static files or logs without clearance.

**Consequences:** Establish a separated sanitization/release gate and negative privacy tests. Public provenance from ADR-009 is eligible only after passing this gate. No automatic 'publish on import' pipeline.

## ADR-013 — B-plus public search, without a full search-engine scope

**Status:** Accepted

**Decision:** Provide keyword search, compound filtering, deterministic sort orders, cursor pagination and provenance lookups, plus a bounded, demonstrable advanced-search capability between basic search and unrestricted fuzzy ranking. The specific enhancement is selected in Round 4.

**Rationale:** Demonstrate credible developer-facing Rails API design while preserving a finite, testable portfolio scope.

**Consequences:** Design a stable search contract and observable boundary tests; defer broad natural-language semantics, arbitrary query operators, search infrastructure at scale and learned relevance ranking unless subsequently promoted.

## ADR-014 — Deterministic field-weighted relevance ranking

**Status:** Accepted

**Decision:** The bounded search enhancement beyond compound filters and cursors is field-weighted deterministic relevance; match priority and ties must be documented, explainable and reproducibly tested.

**Rationale:** Strengthens the publicly inspectable search contract without introducing fuzzy or opaque ranking infrastructure.

**Consequences:** Search results need stable relevance/tie ordering and ranking tests; avoid broad typo tolerance, vectors and learned relevance in first release.

## ADR-015 — Idempotent incremental ingestion with preserved history

**Status:** Accepted

**Decision:** Trusted CLI/Rake imports are incremental and idempotent, preserving prior source revisions, conflicting observations and run reports across corrections.

**Rationale:** Replayed feeds and corrected historical data should not duplicate search results or erase the evidence used to reconcile them.

**Consequences:** Distinguish source identity, content revision, import attempt and derived canonical state; test duplicate replay, corrected update, and partial-failure replay.

## ADR-016 — One PostgreSQL database contract across environments

**Status:** Accepted

**Decision:** Use PostgreSQL through Rails Active Record for development, test and production, rather than changing database engines by environment.

**Rationale:** Eliminates subtle differences in migrations, indexing and ranking between local verification and public hosting.

**Consequences:** Provision a local PostgreSQL development/test service and locate a compatible deployment. Shared hosting with only MariaDB does not satisfy this requirement.

## ADR-017 — Free-first hosting with separately authorized conditional spending

**Status:** Accepted

**Decision:** Target $0 recurring deployment. Consider up to $5/month only with explicit separate approval; cold-start tolerance and publication gates remain to be settled. Evaluate the owner's free Hostinger student entitlement, but require actual Rails process and PostgreSQL capabilities before selecting it.

**Rationale:** Avoid needless project operating cost without making the public demonstration dependent on an unverified hosting promise.

**Consequences:** Compare runtime/database compatibility and free-tier persistence. Do not spend, subscribe or deploy based on this ADR alone; keep a tested local path if live hosting is unavailable.

## ADR-018 — Evidence-based acceptance suite

**Status:** Accepted

**Decision:** Core qualification requires a reproducible difficult-corpus suite covering adversarial data, privacy and publication, idempotent replay and corrections, deterministic reconciliation, cursors and public API contracts; mere functional demos are insufficient.

**Rationale:** The project's value as an engineering sample comes from precise observable guarantees, not a large but vague test count.

**Consequences:** Qualification evidence must identify the exact source revision, command, environment, fixtures, result, failures and boundaries. No claimed validation without real execution.

## ADR-019 — Free live hosting preferred; verified Docker release fallback

**Status:** Accepted

**Decision:** Seek a public live Rails/PostgreSQL demonstration at $0 recurring cost, but a fully verified local Docker-based API/playground/docs demonstration is an acceptable completed Core Release if durable free hosting is blocked. Spending up to $5/month still requires separate approval under ADR-017.

**Rationale:** Valid learning and reviewed engineering work must not depend on an unstable or paid hosting offer.

**Consequences:** Packaging, local setup, seeded approved corpus and repeatable smoke tests must be reviewer-friendly. Public deployment gets its own evidence gate and status in the case study; do not claim a local demo is live.

## ADR-020 — Opt-in, bounded SerpApi comparison after core release

**Status:** Accepted

**Decision:** After core acceptance, provide optional server/CLI-side integration of a bounded SerpApi query with an explainable comparison to approved stored historical records. Provider output must remain attributed, key-protected and separated from automatic canonical publication.

**Rationale:** Tests the same data reliability boundaries against a real external service without making quota use essential to the portfolio.

**Consequences:** Final optional tickets implement a stubbed/testable adapter, hard caps, safe error handling and the opt-in comparison. No recurring ingestion or visitor-controlled billable routes.

## ADR-021 — Reviewer-grade playground, API docs and case study

**Status:** Accepted

**Decision:** Provide polished, accessible browser search/playground, executable interactive API documentation, reproducible examples, and a concise technical case study explaining methodology, decisions, measured tests and limitations.

**Rationale:** A hiring team should understand and exercise the actual API quickly without learning the operator import workflow.

**Consequences:** Docs must be generated or contract-checked against routes, playground must call real API responses, and the case study must separate self-directed work from paid experience and verified facts from aspirations.
