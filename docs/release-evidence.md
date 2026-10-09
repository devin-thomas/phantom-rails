# Phantom Rails — Release Evidence Ledger

**Generated:** 2026-10-09  
**Platform:** Windows 11 host / WSL2 Docker Engine (x86_64-linux)  
**Ruby Version:** 3.4.11 (`.ruby-version`)  
**Rails Version:** 8.1.4  
**PostgreSQL Version:** 16-alpine (containerized, Active Record in all environments)  

---

## Ticket Execution Matrix

| Ticket | Name | Status | Verified Evidence |
|---|---|---|---|
| **PHR-001** | Rails/PostgreSQL foundation | **COMPLETE** | Docker Compose boots `db` (healthy) & `web` (running); `bin/rails db:prepare` succeeds; `bin/rails test` passes 2/2 tests (13 assertions); `/api/v1/health` returns 200 OK with no leaked secrets. |
| **PHR-002** | Versioned source contract & hard fixtures | **COMPLETE** | JSON Schema `batch-v1.schema.json` created; `SourceBatchParser` passes 6 tests (41 assertions); multi-company adversarial fixtures created (valid, mixed, unsupported version, unicode/escaping, tracking/canaries, JSONL). |
| **PHR-003** | Privacy release candidate workflow | **COMPLETE** | `Sanitizer`, `PrivacyScanner`, and `ReleaseGate` implemented; approved release manifest v1.0 schema created; verified digest match (`ead0619...`), rejection of tampered bytes, rejection of PII/canaries, and URL tracking parameter stripping across 5 tests (25 assertions). |
| **PHR-004** | Relational provenance model | **COMPLETE** | PostgreSQL migrations executed for all 9 domain tables (`approved_releases`, `canonical_postings`, `source_records`, `source_mentions`, `source_revisions`, `field_selections`, `potential_duplicates`, `import_runs`, `import_errors`); DB constraints tested and verified across 5 tests (19 assertions); no SQLite divergence. |
| **PHR-005** | Trusted partial importer | **COMPLETE** | `BatchImporter` and `phantom:import` Rake task created; atomic item-level subtransactions; invalid rows isolated with diagnostics; unsupported versions abort atomically with 0 rows; verified across 4 tests (35 assertions) and CLI runs. |
| **PHR-006** | Revision replay & import history | **COMPLETE** | Idempotent replay verified with zero duplicate records, zero corpus revision changes, and auditable `ImportRun`; chronological corrections retain previous revisions; `phantom:history` audit CLI verified across 3 tests (20 assertions). |
| **PHR-007** | Conservative identity resolver | **COMPLETE** | Tier 1 (verified employer req), Tier 2 (canonical job URL), and Tier 3 (platform ID) merges verified; distinct reqs remain separate; Tier 4 weak similarity flagged as `PotentialDuplicate` without merging; verified across 4 tests (14 assertions). |
| **PHR-008** | Field precedence & conflicts | **COMPLETE** | `FieldReconciler` implemented; verified official employer override (`verified_official_override`) overrides newer conflicting third-party board range; recency default (`newest_credible`); deterministic tie-breaking verified across 3 tests (9 assertions). |
| **PHR-009** | Approved release projection & revision | **COMPLETE** | `ApprovedReleaseManager` and `phantom:publish` Rake task created; atomic release activation; public queries scoped strictly to active approved release via `active_approved`; stable checksummed Corpus Revision verified across 4 tests (16 assertions). |
| **PHR-010** | Read API & explicit serialization | Not started | Pending |
| **PHR-011** | Compound filters & weighted relevance | Not started | Pending |
| **PHR-012** | Revision-safe keyset cursors | Not started | Pending |
| **PHR-013** | Public provenance explanations | Not started | Pending |
| **PHR-014** | OpenAPI contract & interactive docs | Not started | Pending |
| **PHR-015** | Polished search playground | Not started | Pending |
| **PHR-016** | Adversarial acceptance & privacy suite | Not started | Pending |
| **PHR-017** | Reproducible CI container & reviewer seed | Not started | Pending |
| **PHR-018** | Zero-cost live or local release evaluation | Not started | Pending |
| **PHR-019** | Showcase & technical case study | Not started | Pending |
| **PHR-020** | Optional SerpApi client (gated) | Not started | Pending |
| **PHR-021** | Optional SerpApi comparison evidence | Not started | Pending |

---

## Detailed Evidence

### PHR-001 — Rails/PostgreSQL Foundation
- **Commands Executed:**
  ```bash
  docker compose build
  docker compose up -d
  docker compose exec web bin/rails db:prepare
  docker compose exec web bin/rails test
  curl -i http://localhost:3000/api/v1/health
  ```
- **Service Verification:**
  - `phantom-rails-x-db-1`: `postgres:16-alpine`, Status `Up (healthy)`, Port `5432->5432`
  - `phantom-rails-x-web-1`: `phantom-rails-x-web`, Status `Up`, Port `3000->3000`
- **Test Output:**
  ```text
  2 runs, 13 assertions, 0 failures, 0 errors, 0 skips
  ```
- **HTTP Response:**
  ```json
  HTTP/1.1 200 OK
  Content-Type: application/json; charset=utf-8
  {"status":"ok","database":"connected","approved_release":false}
  ```
- **Secrets Audit:**
  - `config/master.key` and `.env` excluded by `.gitignore`
  - `.env.example` provides non-sensitive defaults only
  - Zero private credentials, environment dumps, or database URLs exposed in `/api/v1/health`

### PHR-002 — Versioned Source Contract & Hard Fixtures
- **Schema:**
  - `schemas/batch-v1.schema.json` with strict additionalProperties: false, length caps, and RFC3339 formats.
- **Fixtures:**
  - `fixtures/adversarial/valid_batch_v1.json` (5 valid items, multiple companies/tiers/timestamps)
  - `fixtures/adversarial/mixed_batch_v1.json` (2 valid, 3 invalid with diagnostics)
  - `fixtures/adversarial/invalid_envelope_v1.json` (unsupported version 2.0)
  - `fixtures/adversarial/unicode_and_escaping_v1.json` (accented strings, HTML injection payloads)
  - `fixtures/adversarial/tracking_and_canaries_v1.json` (UTM tracking params, PII tokens)
  - `fixtures/adversarial/batch_v1.jsonl` (JSONL stream format)
- **Test Output:**
  ```text
  bin/rails test test/services/source_batch_parser_test.rb
  6 runs, 41 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-003 — Privacy-Preserving Release Candidate Workflow
- **Services:**
  - `Sanitizer`: Strips tracking query params (`utm_*`, `gclid`, `fbclid`, etc.), URL fragments, userinfo, executable HTML tags, and truncates excerpts <= 220 chars without fabricating facts.
  - `PrivacyScanner`: Scans fields for email addresses, canaries (`canary_*`, `secret_*`), bearer tokens, un-sanitized tracking params, and HTML scripts.
  - `ReleaseGate`: Computes SHA-256 digest of candidate payload, validates signed manifest (`schemas/public-release-v1.schema.json`), and fails closed if digest mismatches or privacy check fails.
- **Approved Release Fixture:**
  - `fixtures/public-approved/approved-batch-v1.json`
  - `fixtures/public-approved/approved-manifest-v1.json` (Digest: `ead0619d574105222c58c4993fdd66d2cd087bc87e50273a119f4c32881230e1`, approved by `devin-thomas`)
- **Test Output:**
  ```text
  bin/rails test test/services/release_gate_test.rb
  5 runs, 25 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-004 — Relational Provenance Model
- **Migrations:**
  - `db/migrate/20261009120000_create_provenance_domain_model.rb` applied to PostgreSQL.
  - Tables created: `approved_releases`, `canonical_postings`, `source_records`, `source_mentions`, `source_revisions`, `field_selections`, `potential_duplicates`, `import_runs`, `import_errors`.
  - Enforced DB constraints: foreign keys, cascading deletes, unique indexes (`[source_system, source_record_key]`, `[source_record_id, mention_key]`, `[source_mention_id, revision_digest]`, `[canonical_posting_id, field_name]`, `[posting_a_id, posting_b_id]`).
- **PostgreSQL Full-Text Search:**
  - GIN indexed `tsvector` column on `canonical_postings.search_vector` using `english` dictionary.
- **Test Output:**
  ```text
  bin/rails test test/models/provenance_domain_model_test.rb
  5 runs, 19 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-005 — CLI/Rake Trusted Partial Importer
- **Service & CLI:**
  - `app/services/batch_importer.rb`
  - `lib/tasks/phantom.rake` (`bin/rails phantom:import[file]`)
- **Key Behaviors Verified:**
  - Ingests parseable mixed-quality batch (`mixed_batch_v1.json`) with partial status: exactly 2 valid items accepted, 3 invalid items isolated with error codes.
  - Quarantines in-batch key collisions (`ambiguous_revision_order`) when two conflicting revisions for the same mention appear in one batch.
  - Rejects unsupported schema versions (`invalid_envelope_v1.json`) atomically with 0 rows inserted and status `failed`.
  - Guarantees exact item accounting: `total_input == inserted + updated + unchanged + invalid`.
- **Test Output:**
  ```text
  bin/rails test test/services/batch_importer_test.rb
  4 runs, 35 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-006 — Idempotent Correction and Replay
- **Verified Behaviors:**
  - Idempotent Replay: Importing identical payload records `unchanged: N, inserted: 0`, leaving existing records and counts unchanged.
  - Historical Retention: Subsequent corrected payload adds a new `SourceRevision` with updated attributes while retaining older revisions with their exact timestamps and values.
  - History Task: `bin/rails phantom:history` displays formatted run audit log with timestamps, statuses, and counts.
- **Test Output:**
  ```text
  bin/rails test test/services/revision_replay_test.rb
  3 runs, 20 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-007 — Strong Identity Matching and Ambiguity Flags
- **Service:**
  - `app/services/identity_resolver.rb`
- **Verified Behaviors:**
  - Tier 1: Merges mentions sharing company and employer requisition ID into single Canonical Posting with multiple Source Mentions.
  - Tier 2: Merges mentions sharing cleaned employer job URL path.
  - Separate Openings: Requisitions `REQ-101` and `REQ-102` at the same employer remain separate postings.
  - Tier 4: Uncertain similarity (identical title and company without strong ID) creates separate postings and automatically creates bidirectional `PotentialDuplicate` links.
- **Test Output:**
  ```text
  bin/rails test test/services/identity_resolver_test.rb
  4 runs, 14 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-008 — Newest-First Field Selections with Authority Exceptions
- **Service:**
  - `app/services/field_reconciler.rb`
- **Verified Behaviors:**
  - Verified Official Override: Official employer posting on Sept 20 ($175k-$215k) overrides newer Sept 23 third-party board observation ($160k-$195k) with reason `verified_official_override`, while retaining both conflicting observations for audit.
  - Recency Baseline: Equal-authority third-party sources resolve to latest observation with reason `newest_credible`.
  - Deterministic Tie-Breaking: Simultaneous timestamps broken by authority rank, then revision digest lexicographical sorting.
- **Test Output:**
  ```text
  bin/rails test test/services/field_reconciler_test.rb
  3 runs, 9 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-009 — Active Approved Corpus and Publication Revision
- **Services & CLI:**
  - `app/services/approved_release_manager.rb`
  - `lib/tasks/phantom.rake` (`bin/rails phantom:publish[batch,manifest]`)
- **Verified Behaviors:**
  - Strict Isolation: Postings in staging (unapproved or unassigned) are excluded from `active_approved` scope and invisible to readers.
  - Fail-Closed Gate: Tampered bytes or invalid manifests reject publication atomically and retain prior active release.
  - Checksummed Revision: Stable SHA-256 Corpus Revision token computed from manifest digest, version, and active postings count; unchanged on replay.
- **Test Output:**
  ```text
  bin/rails test test/services/approved_release_manager_test.rb
  4 runs, 16 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-010 — API v1 Read Surface and Safe Error Handling
- **Controllers & Serializers:**
  - `app/controllers/application_controller.rb`
  - `app/controllers/api/v1/postings_controller.rb`
  - `app/controllers/api/v1/meta_controller.rb`
  - `app/controllers/api/v1/health_controller.rb`
  - `app/serializers/posting_serializer.rb`
- **Verified Behaviors:**
  - Read-Only Enforcement: Public mutation methods (POST, PUT, PATCH, DELETE) fail with 405 Method Not Allowed (`code: "method_not_allowed"`) and cause zero state mutation.
  - Active Approved Projection: Unapproved staging postings return 404 and are excluded from search listings; only active approved postings are exposed.
  - Serializer Allowlist: Zero internal database integer IDs, search vectors, or raw fields leak. All responses pass PrivacyScanner checks.
  - Safe Error Envelopes: Consistent `{"error": {"code": "...", "message": "...", "request_id": "..."}}` envelopes for 400 (`invalid_parameter`), 404 (`not_found`), 405 (`method_not_allowed`), and 503 (`service_unavailable`).
- **Test Output:**
  ```text
  bin/rails test test/controllers/api/v1/postings_controller_test.rb
  11 runs, 78 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-011 — PostgreSQL Keyword Search, Explainable Field Weights, and Compound Filters
- **Service & Controller Integration:**
  - `app/services/search_postings.rb`
  - `app/controllers/api/v1/postings_controller.rb`
  - `app/models/canonical_posting.rb` (dynamic tsvector synchronization)
- **Verified Behaviors:**
  - Full-Text Query Filtering: Parameterized `plainto_tsquery('english', q)` against GIN-indexed `search_vector`, requiring all meaningful query lexemes across combined fields.
  - Explainable Field Weights: Title (+8), Company (+5), Location (+3), Excerpt (+1) per distinct query lexeme, with single-field deduplication.
  - Compound AND Filters: Exact case-insensitive normalized `company` and `location`, validated `remote_type` (`onsite|hybrid|remote|unknown`), validated `employment_type`, and annual-USD compensation filter `min_salary_usd`.
  - Null/Hourly Salary Safety: Unknown salaries and non-annualized hourly pay ($75/hr) cannot satisfy `min_salary_usd`.
  - SQL Injection Defense: Parameterized inputs safely isolate quotes, SQL injection attempts (`' OR 1=1 --`), and semicolon chained queries.
  - Complexity Caps: Rejects strings > 120 chars and queries with > 8 lexemes with safe 400 `invalid_parameter` errors.
  - Deterministic Ordering: Tie-breakers enforced via stable `public_id ASC`.
- **Test Output:**
  ```text
  bin/rails test test/services/search_postings_test.rb
  7 runs, 62 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-012 — Revision-Safe Keyset Cursor Pagination
- **Services & Controller Integration:**
  - `app/services/cursor_token.rb`
  - `app/services/search_postings.rb`
  - `app/controllers/api/v1/postings_controller.rb`
- **Verified Behaviors:**
  - Keyset Boundary Completeness: Multi-page traversal with lookahead yields every qualifying posting ID exactly once across page transitions without duplicates, skipped rows, or offset queries.
  - Query Fingerprinting: Cursors encode normalized query parameters digest (`qd`). Reusing a cursor with modified search filters returns 400 `cursor_query_mismatch`.
  - Cryptographic Verification: Tokens are HMAC-SHA256 signed. Bit-flip tampering or truncated tokens return 400 `invalid_cursor`.
  - Temporal Expiry: Cursors exceeding 15-minute TTL return 410 `cursor_expired`.
  - Revision Invalidation: Cursors tied to an older corpus revision return 409 `stale_cursor` when a new approved release is published.
  - Zero Sensitive Data Leakage: Cursors contain only version, corpus revision, query digest, sort tuple, and expiry.
  - Exact Terminal Semantics: Final page returns `next_cursor: null`.
- **Test Output:**
  ```text
  bin/rails test test/services/cursor_token_test.rb test/controllers/api/v1/cursor_pagination_test.rb
  10 runs, 34 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-013 — Public Provenance Explanations and Merge Auditing
- **Serializers & Controllers:**
  - `app/serializers/provenance_serializer.rb`
  - `app/serializers/posting_serializer.rb`
  - `app/controllers/api/v1/postings_controller.rb` (`GET /api/v1/postings/:id/provenance`)
- **Verified Behaviors:**
  - Conflict Resolution Inspection: Explains chosen field values, alternatives from other observations, observation timestamps, source kinds, and exact reconciliation reason codes (`verified_official_override`, `newest_credible`, `tie_breaker_authority`).
  - Merge Evidence Audit: Lists all contributing Source Mentions with domain, source kind, and origin class, without exposing private internal primary keys or unapproved staging rows.
  - Ambiguity Separation: Inspects bidirectional potential duplicate links while keeping separate postings isolated.
  - Privacy Boundary: Outlook URLs, tracking parameters, email addresses, and canary tokens never serialize; passes `PrivacyScanner` string verification.
  - Fail-Closed Missing References: Unknown IDs or unapproved records yield safe 404 responses with zero database traces.
- **Test Output:**
  ```text
  bin/rails test test/serializers/provenance_serializer_test.rb
  2 runs, 22 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-014 — OpenAPI 3.1 Specification and Self-Contained Interactive Documentation
- **Specification & Controller:**
  - `public/openapi.json` (OpenAPI 3.1)
  - `public/docs.html` (bundled accessible interactive explorer)
  - `app/controllers/docs_controller.rb`
- **Verified Behaviors:**
  - Contract Parity: 100% of routes declared in `openapi.json` correspond to verified Rails routes with full parameter and response schemas.
  - Zero External Dependencies: `/docs` runs with zero CDN scripts, external fonts, or analytics tracking; completely self-contained.
  - Interactive Live Execution: Interactive runner submits parameterized requests directly to local `/api/v1` routes and displays formatted live responses.
  - Pure Read-Only Surface: OpenAPI specification advertises zero write or mutation methods; no write routes exist or are reachable.
  - Live Connectivity: `GET /docs` and `GET /openapi.json` verified with HTTP 200 via curl and automated test suite.
- **Test Output:**
  ```text
  bin/rails test test/controllers/docs_controller_test.rb
  2 runs, 27 assertions, 0 failures, 0 errors, 0 skips
  ```
