# Phantom Rails: Technical Case Study & Architecture Overview

**Author:** Devin Thomas  
**Date:** October 9, 2026  
**Stack:** Ruby on Rails 8.1, PostgreSQL 16 Alpine, Docker Compose, Vanilla HTML/CSS/JS (Zero-CDN)  
**Status:** Core Release Complete (`CORE-LOCAL`) · 85 Tests / 481 Assertions · 0 Failures  

---

## 1. Executive Summary & Objective

**Phantom Rails** is a read-only, high-integrity search API and reviewer playground designed to demonstrate production-grade job posting reconciliation, data provenance, and explainable full-text search.

The project addresses a common pathology in job aggregation and data ingestion systems: **silent, irreversible corruption caused by aggressive entity matching, hidden data fabrication, and opaque field overrides**. 

In conventional aggregators:
- Reposted or syndicated listings are either naively duplicated across search results or aggressively merged based on fuzzy text matching, accidentally collapsing distinct openings (such as two different engineering roles at the same company) into a single entity.
- Conflicting salary estimates from third-party boards silently overwrite verified employer figures, or missing salary data is filled in with artificial averages without clear provenance.
- Pagination relies on slow, unstable SQL offsets (`OFFSET 1000`) that skip or repeat records when datasets change under active ingestion.
- Opaque tracking parameters (`utm_*`, `gclid`), private email headers, and applicant tokens leak into public search surfaces.

Phantom Rails was built from first principles to solve these challenges through a strict, inspectable, and conservative architecture:
1. **Conservative 4-Tier Identity Resolution**: Merges only when cryptographic or verified primary keys align; treats weak title/company similarities strictly as inspectable *potential duplicate flags* rather than destructive merges.
2. **Deterministic Provenance & Precedence**: Retains every historical revision and conflicting observation in PostgreSQL relational tables; applies verified official employer overrides (`verified_official_override`) with recorded rationale while preserving discarded alternatives for reviewer audit.
3. **Cryptographically Signed Keyset Cursors**: HMAC-SHA256 tokens bound to normalized query digests, corpus revisions, and 15-minute expiration windows for zero-offset, stable pagination.
4. **Zero-CDN Offline Reviewer Surface**: Completely self-contained interactive OpenAPI documentation (`/docs`) and accessible search playground (`/playground`) with zero external CDNs, web fonts, or telemetry scripts.
5. **Strict Release Gate & Zero Data Leaks**: Automated privacy scanning, canary token detection, and digest-verified manifests ensure private applicant materials and secret credentials never reach public API projections.

---

## 2. Core Architecture & Database Design

Phantom Rails uses **PostgreSQL 16** via Active Record across all environments (development, test, and production)—with zero SQLite divergence.

```
                     ┌────────────────────────────────┐
                     │   Raw Batch Input (batch-v1)   │
                     └───────────────┬────────────────┘
                                     │
                             [Sanitizer]
                   (Strips UTM, scripts, userinfo)
                                     │
                           [ReleaseGate]
              (SHA-256 Digest Match + PrivacyScanner)
                                     │
                     ┌───────────────▼────────────────┐
                     │         BatchImporter          │
                     │  (Atomic item subtransactions) │
                     └───────────────┬────────────────┘
                                     │
        ┌────────────────────────────┼────────────────────────────┐
        ▼                            ▼                            ▼
┌──────────────────┐       ┌──────────────────┐       ┌──────────────────────┐
│  SourceRecords   │       │  SourceMentions  │       │   SourceRevisions    │
│(Domain / Provider)│      │ (Mention Key/URL)│       │ (Values & Timestamp) │
└──────────────────┘       └─────────┬────────┘       └──────────────────────┘
                                     │
                         [IdentityResolver]
                   (Tiers 1-3 Merge / Tier 4 Flag)
                                     │
                         [FieldReconciler]
                  (Official Overrides / Recency)
                                     │
                     ┌───────────────▼────────────────┐
                     │       CanonicalPostings        │
                     │ (active_approved projection)   │
                     └───────────────┬────────────────┘
                                     │
             ┌───────────────────────┴───────────────────────┐
             ▼                                               ▼
┌─────────────────────────┐                     ┌─────────────────────────┐
│     SearchPostings      │                     │   PostingSerializer     │
│ (GIN tsvector, Weights) │                     │ (ProvenanceSerializer)  │
└────────────┬────────────┘                     └────────────┬────────────┘
             │                                               │
             └───────────────────────┬───────────────────────┘
                                     ▼
                     ┌────────────────────────────────┐
                     │     HTTP Read-Only API v1      │
                     │   (/postings, /provenance)     │
                     └────────────────────────────────┘
```

### Relational Domain Model (9 Entities)

The data model preserves complete auditability from raw observation to public projection:

1. **`approved_releases`**: Stores immutable manifest digests (`ead0619...`), publication timestamps, and approved posting counts.
2. **`canonical_postings`**: Public entity projection with unique `public_id` (`post_...`), GIN-indexed `search_vector`, sanitized title, company, location, salary range, and `potential_duplicate` flag.
3. **`source_records`**: Top-level batch records containing origin classes (`approved_public`, `adversarial_synthetic`).
4. **`source_mentions`**: Individual sightings of a job posting across provider domains (`job_board`, `direct_employer`, `aggregator`).
5. **`source_revisions`**: Immutable revision snapshots capturing what was observed at an exact timestamp (`observed_at`), along with a cryptographic SHA-256 digest of its payload.
6. **`field_selections`**: Relational provenance records linking each canonical field to the exact winning `source_revision`, recording the selection reason code (`verified_official_override`, `newest_credible`, `tie_breaker_authority`).
7. **`potential_duplicates`**: Bidirectional pairing records between distinct canonical postings flagged for reviewer audit under Tier 4 similarity rules.
8. **`import_runs`**: Chronological audit trail of CLI/Rake batch imports recording input totals, inserted, updated, unchanged, and quarantined row counts.
9. **`import_errors`**: Detailed diagnostic records isolating invalid items without failing the entire batch.

---

## 3. Key Design Decisions & Technical Trade-Offs

### A. Conservative Identity Matching (ADR-007)
A critical failure mode of job boards is merging distinct job requisitions that happen to share a title and company. For instance, an employer may have two separate openings for "Software Engineer" on different teams with requisition IDs `REQ-101` and `REQ-102`.

Phantom Rails enforces a **4-tier deterministic resolution hierarchy**:
- **Tier 1 (Verified Employer Requisition)**: Merges if `company` and `employer_requisition_id` match exactly.
- **Tier 2 (Canonical Clean URL)**: Merges if the normalized, query-stripped employer job URL path matches.
- **Tier 3 (Platform Source ID)**: Merges if a verified ATS platform ID (`greenhouse/12345`) matches.
- **Tier 4 (Weak Text Similarity)**: If title, company, and location match but lack strong keys, **merging is strictly prohibited**. Instead, the system provisions separate `CanonicalPosting` records and links them bidirectionally in `potential_duplicates`. Reviewers can inspect the ambiguity in the UI without risking collapsed openings.

### B. Field Precedence & Official Overrides (ADR-008)
When multiple sightings report conflicting field values (e.g., conflicting salary ranges or job titles), Phantom Rails does not naively pick the newest date or take a statistical average.

- **Verified Official Override (`verified_official_override`)**: Observations originating directly from verified employer sources (`direct_employer` / `official_website`) supersede observations from third-party job aggregators, even if the third-party sighting is newer. For example, if an employer lists $175,000–$215,000 on Sept 20 and an aggregator posts $160,000–$195,000 on Sept 23, the employer range is selected.
- **Recency Baseline (`newest_credible`)**: For sources of equal authority, the newest observation wins.
- **Deterministic Tie-Breaking**: Simultaneous observations break ties using authority rank, followed by lexical sort of the revision digest.
- **Conflict Retention**: All alternative values, timestamps, and sources are preserved in `field_selections` and serialized in `/api/v1/postings/:id/provenance`.

### C. Keyset Cursor Pagination vs Offset Pagination (ADR-012)
Offset pagination (`OFFSET 500 LIMIT 20`) is notoriously fragile under active ingestion and exhibits $O(N)$ scanning performance in PostgreSQL.

Phantom Rails implements **HMAC-SHA256 signed keyset cursors**:
- **Query Digest Binding**: Cursors include a SHA-256 digest of the active query parameters (`qd`). Modifying filters while reusing a cursor returns `400 cursor_query_mismatch`.
- **Corpus Revision Binding**: Cursors are bound to the active `corpus_revision`. When a new approved release is published, older cursors return `409 stale_cursor`.
- **Cryptographic Signing & TTL**: Tokens are tamper-evident and expire after 15 minutes (`410 cursor_expired`).
- **Lookahead Terminal Page**: The service queries `limit + 1` rows to detect whether additional pages exist; the final page returns `next_cursor: null`.

### D. Parameterized PostgreSQL Full-Text Search (ADR-011)
Search is powered by native PostgreSQL full-text search:
- **GIN Index**: `canonical_postings.search_vector` indexed with GIN.
- **Field Weights**: Dynamically computed and explainable relevance scores:
  - Title match: **+8**
  - Company match: **+5**
  - Location match: **+3**
  - Excerpt match: **+1**
- **Compound Filters**: Combined seamlessly with SQL AND conditions for `company`, `location`, `remote_type`, and `min_salary_usd`.
- **Compensation Safety**: Hourly rates (e.g., $75/hr) and null salaries are strictly excluded from annual USD filters to prevent false matches.

### E. Zero-CDN Architecture (ADR-014, ADR-015)
To ensure complete portability, offline testing in local Docker containers, and zero third-party telemetry:
- Both `/docs` (interactive OpenAPI explorer) and `/playground` (reviewer search UI) are authored in vanilla HTML, modern CSS, and lightweight vanilla JavaScript.
- Zero dependencies on Google Fonts, unpkg, cdnjs, or jsdelivr.
- Fully accessible (WCAG compliant contrast, keyboard navigation, responsive down to 320px).

---

## 4. Contractual Acceptance & Benchmark Verification

The implementation was validated against the 16 contractual adversarial scenarios defined in **SPEC §10.1** via an automated integration benchmark suite (`test/integration/spec_benchmark_suite_test.rb`).

| # | Contractual Scenario | Verification & Behavior | Status |
|---|---|---|---|
| **01** | Reposted employer listing with different tracking URLs | Merges to single canonical posting; strips UTM params from destination URL. | **PASS** |
| **02** | Different requisitions (`REQ-101` vs `REQ-102`) | Remain separate canonical postings despite identical title and company. | **PASS** |
| **03** | Conflicting salary ranges | Resolves to verified official employer range; preserves both observations for audit. | **PASS** |
| **04** | Newer third-party observation vs older authoritative listing | Verifies `verified_official_override` exception; employer listing retained. | **PASS** |
| **05** | Ambiguous similarity without strong ID | Provisions separate postings and links bidirectional `potential_duplicate`. | **PASS** |
| **06** | Corrected source revision | Updates canonical projection while retaining older revision in history. | **PASS** |
| **07** | Identical batch replay | No-op idempotent replay; `unchanged: N`, `inserted: 0`, corpus revision stable. | **PASS** |
| **08** | Mixed valid/invalid batch records | Ingests valid rows, quarantines invalid rows with diagnostics, marks run `partial`. | **PASS** |
| **09** | Conflicting in-batch revisions | Quarantines conflicting mention revisions as `ambiguous_revision_order`; independent rows succeed. | **PASS** |
| **10** | Unsupported batch schema version | Aborts atomically with zero rows inserted; status `failed`. | **PASS** |
| **11** | Unicode accents and HTML injection | Preserves UTF-8 characters; strips script tags and executable attributes. | **PASS** |
| **12** | Unknown salaries and invalid dates | Retains `null` safely; never fabricates artificial averages or timestamps. | **PASS** |
| **13** | Canary tokens and secrets in raw input | Blocks publication at the release gate (`ReleaseGate` fails closed). | **PASS** |
| **14** | Keyset cursor tampering and expiration | Returns deterministic `400 invalid_cursor`, `400 cursor_query_mismatch`, `410 cursor_expired`. | **PASS** |
| **15** | SQL injection and syntax fuzzing | Parameterized queries safely return 0 results or 400 parameter errors; zero SQL injection. | **PASS** |
| **16** | Public HTTP mutation attempts | POST, PUT, DELETE return `405 Method Not Allowed` with zero database changes. | **PASS** |

The full automated suite executes **85 test cases with 481 assertions** in 7.0 seconds with **0 failures, 0 errors, and 0 skips**.

---

## 5. Hosting Qualification & Release Certification

During **PHR-018**, candidate hosting providers were evaluated against the strict **$0 budget boundary** and durability requirements:

- **Render**: Free web tier exists, but Render's free PostgreSQL tier **automatically expires and destroys the database and all data after 30 days**. Using ephemeral storage for a durable showcase violates project principles, and upgrading to durable Postgres ($7/month) requires explicit owner authorization.
- **Hostinger Student**: Examined per specification; provides shared cPanel web hosting without Docker, root access, or support for Rails 8.1 container stacks.
- **Koyeb / Neon**: Nano instance web with external serverless Postgres has connection spin-up latencies, cold starts, and suspension risks.
- **Outcome**: The Core Release is officially certified as **`CORE-LOCAL (Docker Compose Verified)`**. It provides zero cold starts, zero monthly costs, 100% data persistence, and identical execution across Linux, macOS, and Windows.

---

## 6. Reviewer Five-Minute Quickstart

### Prerequisites
- Docker Engine & Docker Compose installed and running.

### 1. Boot the Stack
```bash
docker compose build
docker compose up -d
```

### 2. Run the Single-Command Qualification Suite
```bash
docker compose exec web ruby bin/verify
```
*Validates database connectivity, pending migrations, approved fixture seeding, full 85-test suite, OpenAPI 3.1 schema, secret/canary scanner, and zero external CDN assets.*

### 3. Inspect Live Endpoints
- **System Health:**  
  `curl http://localhost:3000/api/v1/health`
- **Corpus Metadata & Revision:**  
  `curl http://localhost:3000/api/v1/meta`
- **Full-Text Compound Search:**  
  `curl "http://localhost:3000/api/v1/postings?q=engineer&remote_type=remote"`
- **Inspect Provenance & Duplicate Flags:**  
  `curl http://localhost:3000/api/v1/postings/post_576597ae5b396d9e/provenance`

### 4. Interactive Reviewer Surfaces
- **Interactive Documentation:** Open [http://localhost:3000/docs](http://localhost:3000/docs) in your browser.
- **Search Playground:** Open [http://localhost:3000/playground](http://localhost:3000/playground) to test queries, inspect score breakdowns, and open the Provenance Drawer.

---

## 7. Reflections & Honesty Disclosures

- **Ruby on Rails 8.1 Modern Patterns**: Building Phantom Rails on Rails 8.1 allowed using native solid patterns, modern Active Record features, strict parameter isolation, and parallelized Minitest runners.
- **Data Privacy Boundaries**: Private applicant emails, Outlook credentials, and real candidate materials from the internal BriefcaseOS project were strictly excluded. All demonstration fixtures are synthetic or digest-approved public records.
- **Optional SerpApi Feature (PHR-020 / PHR-021)**: The core release is self-contained. The optional SerpApi integration was deliberately deferred behind explicit owner authorization to ensure zero third-party credit card charges or external API consumption during the core qualification.
- **Communication Guardrail**: In compliance with the project boundary, **no automated follow-up email has been generated or sent**.
