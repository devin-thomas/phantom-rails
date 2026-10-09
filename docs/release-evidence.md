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
| **PHR-010** | Read API & explicit serialization | **COMPLETE** | Read-only HTTP surface (`GET /api/v1/postings`, `/postings/:id`, `/meta`, `/health`), 405 on public mutations, allowlisted serializers, safe error envelopes across 11 tests (78 assertions). |
| **PHR-011** | Compound filters & weighted relevance | **COMPLETE** | Parameterized PostgreSQL full-text search (`SearchPostings`), GIN-indexed `search_vector`, explainable weights (+8 Title, +5 Company, +3 Location, +1 Excerpt), compound AND filters, SQL injection defense across 7 tests (62 assertions). |
| **PHR-012** | Revision-safe keyset cursors | **COMPLETE** | HMAC-SHA256 keyset cursors (`CursorToken`), query digest binding, 15-min TTL, deterministic errors (400, 409, 410), lookahead terminal page across 10 tests (34 assertions). |
| **PHR-013** | Public provenance explanations | **COMPLETE** | Provenance explanations (`GET /api/v1/postings/:id/provenance`), contributing sources, reconciliation decisions (`verified_official_override`, `newest_credible`), discarded alternatives, duplicate audit across 2 tests (22 assertions). |
| **PHR-014** | OpenAPI contract & interactive docs | **COMPLETE** | OpenAPI 3.1 specification at `public/openapi.json`, self-contained interactive explorer at `public/docs.html` / `GET /docs`, zero CDNs/fonts across 2 tests (27 assertions). |
| **PHR-015** | Polished search playground | **COMPLETE** | Accessible search playground at `public/playground.html` / `GET /playground`, live API client, provenance modal, WCAG contrast, 320px responsive, zero external CDNs (13 assertions). |
| **PHR-016** | Adversarial acceptance & privacy suite | **COMPLETE** | Contractual benchmark integration suite testing all 16 SPEC §10.1 scenarios across 16 runs (55 assertions, 0 failures, 0 errors). |
| **PHR-017** | Reproducible CI container & reviewer seed | **COMPLETE** | Single-command release qualification `bin/verify`, seed task `phantom:seed`, GitHub Actions CI workflow, full automated suite (85 tests, 481 assertions, 0 failures) and qualification gates passing. |
| **PHR-018** | Zero-cost live or local release evaluation | **COMPLETE** | Hosting comparison matrix documented ($0 budget boundary preserved; Render 30-day ephemeral PG rejected); CORE-LOCAL release verified with live container HTTP responses across `/health`, `/meta`, `/postings`, `/provenance`, `/docs`, `/playground`. |
| **PHR-019** | Showcase & technical case study | **COMPLETE** | Technical case study authored at `docs/case-study.md`, quickstart `README.md` updated, reader path verified, status table documented, zero automated emails sent. |
| **PHR-020** | Optional SerpApi client (gated) | Not started | Deferred behind owner authorization ($0 budget preservation) |
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

### PHR-015 — Reviewer Search Playground and Provenance Inspector
- **Frontend & Controller:**
  - `public/playground.html`
  - `app/controllers/playground_controller.rb` (`GET /playground`)
- **Verified Behaviors:**
  - Real API Client: Consumes live same-origin `/api/v1/postings`, `/api/v1/meta`, `/api/v1/health`, and `/api/v1/postings/:id/provenance` endpoints; zero mock fallbacks or client-side storage.
  - Transparent Reconciliation Inspection: Modal allows reviewer to inspect why mentions merged, why potential duplicates stayed separate, and why specific fields won precedence.
  - Keyset Cursor Continuity: Preserves active compound filters (`q`, `company`, `location`, `remote_type`, `min_salary_usd`, `sort`) across next-page keyset token transitions.
  - Accessibility & Viewport Adaptation: Responsive down to 320px viewport; WCAG contrast; high-visibility focus indicators; `prefers-reduced-motion` CSS rules; polite `aria-live` screen reader announcements.
  - Honest Error Reporting: 400 parameter errors, 503 database degradation, and 0-result outcomes clearly distinguish between unavailable states and empty search results.
  - Zero Third-Party Dependencies: Bundled self-contained assets with zero external CDNs, fonts, or tracking scripts.
- **Test Output:**
  ```text
  bin/rails test test/controllers/playground_controller_test.rb
  1 runs, 13 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-016 — Full Adversarial Acceptance and Contractual Benchmark Suite
- **Integration Benchmark Suite:**
  - `test/integration/spec_benchmark_suite_test.rb` (16 named contractual scenarios from SPEC §10.1)
- **Verified Benchmark Scenarios:**
  - Case 1: Identical reposted employer ID with different tracking URL params merges to single posting with cleaned destination URL.
  - Case 2: Different employer requisitions with same title/company/location remain separate postings.
  - Case 3: Conflicting salary resolves to verified employer value and preserves both observations for audit.
  - Case 4: Newer third-party observation vs older authoritative listing creates documented `verified_official_override` exception.
  - Case 5: Ambiguous similarity with no strong ID flags bidirectional `potential_duplicate`.
  - Case 6: Corrected source revision updates canonical projection while retaining prior observation.
  - Case 7: Identical batch replay is a no-op with unchanged corpus and `unchanged: N` accounting.
  - Case 8: Mixed valid/invalid records accepts valid items, isolates invalid items, and marks `partial` status.
  - Case 9: Multiple conflicting revisions in same batch are quarantined with `ambiguous_revision_order` while independent items succeed.
  - Case 10: Unsupported batch schema version causes atomic rejection and unchanged corpus.
  - Case 11: Unicode punctuation/accents and HTML payloads are sanitized without losing characters.
  - Case 12: Unknown salaries and invalid dates stay null and are never fabricated.
  - Case 13: Canary tokens and credentials in raw input block publication at the release gate.
  - Case 14: Cursor tampering (400), query mismatch (400), and expiration (410) behave deterministically.
  - Case 15: Parameterized query injection causes safe deterministic 0-match results or 400 parameter errors without SQL injection.
  - Case 16: Public mutation attempts (POST, PUT, DELETE) fail with 405 Method Not Allowed and cause zero state changes.
- **Test Output:**
  ```text
  bin/rails test test/integration/spec_benchmark_suite_test.rb
  16 runs, 55 assertions, 0 failures, 0 errors, 0 skips
  ```

### PHR-017 — Clean-Checkout Qualification and CI
- **Scripts, Tasks & CI Workflow:**
  - `bin/verify`: Single-command release qualification script verifying DB connection, migrations, seeding, test suite, OpenAPI schema, privacy scanning, and zero external CDNs. Exits 0 on success, non-zero on failure.
  - `lib/tasks/phantom.rake` (`phantom:seed` task): Reads approved release fixtures and activates corpus.
  - `db/seeds.rb`: Invokes `phantom:seed` for standard Rails `bin/rails db:seed` workflows.
  - `.github/workflows/ci.yml`: GitHub Actions pipeline with PostgreSQL 16 service container, Brakeman security scan, and `ruby bin/verify`.
- **Verified Behaviors:**
  - Clean container qualification: `docker compose exec web ruby bin/verify` passes all 7 qualification gates with Exit 0.
  - Full automated suite: 85 runs, 481 assertions, 0 failures, 0 errors, 0 skips across both development and test database environments.
  - Fail-closed status gates: Tampering with OpenAPI schema, privacy scanner violation, or CDN links immediately aborts `bin/verify` with non-zero exit code.
  - Zero paid dependencies: No SerpApi key, personal Outlook accounts, or external services required.
- **Qualification Run Output:**
  ```text
  ======================================================================
    PHANTOM RAILS: CORE RELEASE QUALIFICATION SUITE
  ======================================================================
  [*] Verifying database connectivity... PASS
  [*] Verifying pending migrations... PASS
  [*] Seeding approved public release fixtures... PASS
  [*] Running complete automated test suite... Running 85 tests in parallel using 20 processes
  85 runs, 481 assertions, 0 failures, 0 errors, 0 skips
  PASS
  [*] Validating OpenAPI 3.1 specification schema... PASS
  [*] Scanning active corpus for secret/PII leaks... PASS
  [*] Checking self-contained static assets (no external CDNs)... PASS

  ======================================================================
    ALL QUALIFICATION GATES PASSED SUCCESSFULLY (EXIT 0)
  ======================================================================
  ```

### PHR-018 — Hosting Qualification and Approved Release Gate
- **Hosting Evaluation Matrix:**

  | Platform | Web Service | Database Service | Monthly Cost | Uptime / Cold Start | Verdict |
  |---|---|---|---|---|---|
  | **Render** | Free tier (512MB RAM) | Free PostgreSQL | **$0** (first 30 days), then **$7/mo** | 50s cold start after 15m idle; **PostgreSQL instance and all data automatically destroyed after 30 days** | **REJECTED**: Expiring ephemeral database violates durable showcase requirement; paid upgrade violates $0 budget constraint without owner authorization. |
  | **Koyeb** | Free nano instance (512MB RAM) | None | **$0** | Fast start; no native managed PostgreSQL | **BLOCKED**: Requires separate external managed database service. |
  | **Neon** | N/A (DB only) | Free serverless PG (0.5 GiB) | **$0** | Autosuspends; connection spin-up latency; project archives on inactivity | **REJECTED**: External dependency with suspension risks and connection pool limits. |
  | **Fly.io** | Pay-as-you-go | None free | **Paid** | Requires credit card; charges per resource | **REJECTED**: Zero-cost policy prohibits credit card attachment without prior owner sign-off. |
  | **Hostinger Student** | Shared Web | MySQL only | Entitled | Shared cPanel PHP runtime; **no root, no Docker, no Rails 8.1 / PG16 support** | **REJECTED**: Technical mismatch for containerized Rails 8.1 stack. |
  | **CORE-LOCAL (Docker Compose)** | Containerized Puma (`web`) | Containerized PostgreSQL 16 Alpine (`db`) | **$0.00** | **Instant (local); zero cold starts; 100% data persistence; deterministic across Linux/macOS/Windows** | **ACCEPTED (CORE-LOCAL)**: Fully reproducible, verified, and adheres to strict $0 spending boundary per ADR-018. |

- **CORE-LOCAL Release Certificate:**
  - **Release Status:** `CORE-LOCAL (Docker Compose Verified)`
  - **Public URL Status:** `Not verified / Live public spending boundary preserved`
  - **Environment:** Docker Compose (`web`: Rails 8.1, Puma 7.2; `db`: PostgreSQL 16 Alpine)
  - **Local Endpoints Verified:**
    - `GET http://localhost:3000/api/v1/health` -> `200 OK` (Latency: ~58ms, DB: connected, approved_release: true)
    - `GET http://localhost:3000/api/v1/meta` -> `200 OK` (Corpus revision: active, 4 canonical postings from 5 approved source items)
    - `GET http://localhost:3000/api/v1/postings?q=engineer` -> `200 OK` (Full-text search, explainable scores, duplicate flags active)
    - `GET http://localhost:3000/api/v1/postings/:id/provenance` -> `200 OK` (Full audit trail, candidate alternatives, zero PII leaks)
    - `GET http://localhost:3000/docs` -> `200 OK` (Self-contained interactive OpenAPI documentation)
    - `GET http://localhost:3000/playground` -> `200 OK` (Accessible reviewer search playground)
    - `GET http://localhost:3000/openapi.json` -> `200 OK` (OpenAPI 3.1 contract)
  - **Spending Audit:** Exactly **$0.00** spent; zero API keys created, zero cloud accounts provisioned without authorization.

### PHR-019 — Showcase and Technical Case Study
- **Artifacts Created & Updated:**
  - `docs/case-study.md`: Deep technical case study detailing project problem statement, architecture diagram, 9-table domain model, 4-tier identity matching, field reconciliation precedence rules, keyset pagination algorithms, adversarial testing results, hosting trade-offs, and disclosures.
  - `README.md`: Updated with 5-minute quickstart, live curl commands, interactive UI links, architecture highlights, and truthful status matrix.
  - `tickets/PHR-019-honest-showcase-and-technical-case-study.md`: Marked complete with verified criteria.
- **Reviewer Path Verified:**
  - 5-minute quickstart reproduces deterministically with `docker compose up -d` and `docker compose exec web ruby bin/verify`.
  - Live query examples for health, meta, search, and provenance verified against running local container.
  - Interactive documentation at `http://localhost:3000/docs` and search playground at `http://localhost:3000/playground` confirmed functional with zero external CDN dependencies.
- **Honesty Disclosures & Communication Boundaries:**
  - Acknowledged $0 hosting constraints (why ephemeral 30-day Render Postgres was rejected).
  - Explicitly stated that real candidate materials and private Outlook credentials were never copied into the repository.
  - Confirmed optional SerpApi tickets (PHR-020, PHR-021) are deferred behind owner authorization to prevent accidental third-party credit card charges.
  - Strictly verified that **no automated email has been sent**.

---

## Post-Audit QA Remediation & Hardening (October 9, 2026)

Following independent QA code audits, the following guarantees and protections were sequentially hardened with dedicated regression tests in `test/integration/qa_audit_remediation_test.rb`:

### Round 1 Audit Remediations
1. **GitHub Actions CI Permissions (P0):** Tracked `bin/*` scripts with executable bit `100755` in the Git tree; CI workflow invokes scripts via Ruby.
2. **Public Data Isolation (P0):** Blocked unapproved staging imports for an existing mention from mutating active approved canonical postings or field selections.
3. **Provenance Privacy Filter (P0):** `ProvenanceSerializer` filters potential duplicates and source mentions to active approved records.
4. **Composite Key Matching (P1):** `ApprovedReleaseManager` scopes records via composite `[source_system, source_record_key]`.
5. **Conservative Identity Resolver Hardening (P1):** Enforces employer identity normalization and rejects conflicting requisition IDs (`REQ-101` vs `REQ-102`).
6. **Release Gate Invariants (P1):** Candidate batches must be 100% valid; in-batch duplicate accounting verified.

### Round 2 Audit Remediations
1. **Explicit Approved Revision Memberships (`ApprovedReleaseRevision` join table):**
   - Created `approved_release_revisions` to capture snapshot source domain, job ID, and origin class at publication time.
   - Proved byte-invariance and zero canary leaks on approved public posting and provenance endpoints after subsequent staging imports against the same source key.
2. **Domain/Record Allowlist for Official Authority:** Explicit allowlist configuration and verification ensuring unverified domains cannot claim official employer status.
3. **Generic Job URL Merge Denylist:** Generic path denylist prevents merging unrelated roles sharing root careers URLs.

### Round 3 Audit Remediations
1. **QA3-01: Legacy Active Release Safe Fallback & Fail-Closed Protection (P0/P1):**
   - Migration `HardenApprovedReleasesAndRevisions` deactivates legacy releases without `approved_release_revisions` entries.
   - Runtime fallback: `CanonicalPosting#approved_revisions` and `ProvenanceSerializer#render_mentions` fall back safely to revisions created/observed at or before approval time (`approved_at`), completely isolating unapproved staging additions and guaranteeing zero canary or private identifier leaks.
2. **QA3-02: Identity and Origin Metadata Bound to Revision Digest (P1):**
   - `SourceRevision.compute_digest` includes `source_system`, `source_record_key`, `mention_key`, `origin_class`, `source_kind`, `source_domain`, and `job_id`.
   - `BatchImporter` quarantines conflicting mention metadata (changed `job_id` or `source_domain`) as `identity_conflict` rather than silently mutating existing mentions.
3. **QA3-03: Cross-Origin Source Identity Reuse Rejection (P1):**
   - `BatchImporter` rejects cross-origin reuse with an `origin_class_conflict` error when an incoming item's `origin_class` differs from existing `SourceRecord#origin_class`, preventing synthetic data from assuming historical identity.
4. **QA3-04: Same-Employer, Same-Title Multi-Opening Protection (P1):**
   - Tier 2 strong matching (`tier2_strong_match?`) requires matching normalized locations and rejects unvetted department/category landing pages (`vetted_job_url_pattern?`).
   - Distinct openings sharing general URLs record `shared_url_differing_locations` and `shared_url_ambiguous_role_page` potential duplicates without collapsing.
5. **QA3-05: Versioned Release-Bound Source Authority (P2):**
   - Committed `config/source_authority.yml` with version `1.0.0` and operator verification rules.
   - Calculated `SourceAuthority.authority_fingerprint` (SHA-256) and bound it to `ApprovedRelease#authority_fingerprint`, `ApprovedReleaseManager.current_revision`, and `ProvenanceSerializer` merge evidence.
6. **QA3-06: Digest Semantics & Evidence Documentation (P2):**
   - `ReleaseGate` supports exact-byte SHA-256 (`sha256-exact`, default) and normalized text SHA (`sha256-normalized-text`).
   - Qualified test suite: **103 tests, 615 assertions, 0 failures, 0 errors, 0 skips**. All verification gates pass in `bin/verify`.

### Round 4 Audit Remediations
1. **QA4-01: Cross-Signal Identity Conflict Detection & Propagation (P1):**
   - `IdentityResolver` retains strong claims across Tier 1 (requisition ID), Tier 2 (job URL), and Tier 3 (platform ID) and detects contradictions before candidate filtering.
   - Contradictory cross-signal claims (e.g. matching requisition ID on Posting A while matching URL on Posting B, or conflicting requisition IDs on a shared URL) return `status: :identity_conflict`.
   - `BatchImporter` inspects `ResolveResult.status` and propagates `identity_conflict` as an item-level invalid error, ensuring contradictory inputs are quarantined rather than silently merged or created.
2. **QA4-02: Verified Employer Authority Required for Tier 1 Requisition Merging (P1):**
   - Restricted Tier 1 requisition matching in `IdentityResolver#find_tier1_candidates` to verified official employer sources (`SourceAuthority.verified_official?` on at least one side).
   - Independent unverified third-party job boards sharing generic IDs (e.g., `job_id="123"`) with differing titles or locations remain separate postings and are flagged with uncertainty (`PotentialDuplicate` with `unverified_shared_job_id`).
3. **QA4-03: Composite System and Record Key Binding for Official Grants (P1):**
   - `SourceAuthority.verified_official?` and `config/source_authority.yml` require composite `[source_system, source_record_key]` matching and verify company binding.
   - Forbids blank domains on untrusted sources, preventing third-party boards from impersonating reviewed employer record keys without authorization.
4. **QA4-04: Forward-Only Release Activation & Unsupported Rollback Defense (P1):**
   - `ApprovedRelease#activate!` declares release activation forward-only and raises `ApprovedRelease::UnsupportedRollbackError` when attempting to reactivate superseded releases, preventing mutable posting corruption.
5. **QA4-05: Injective Canonical JSON Revision Digest (v2) Eliminating Delimiter Collisions (P1):**
   - `SourceRevision.compute_digest` upgraded to sorted canonical JSON serialization (`v2`), eliminating non-injective pipe delimiter boundary collisions (e.g., `"Senior Engineer"` / `"A|B"` vs `"Senior Engineer|A"` / `"B"`).
6. **QA4-06: Database Migration & Idempotent Replay for Digest Contract Upgrade (P2):**
   - Migration `20261009150000_upgrade_revision_digests_to_v2.rb` added `digest_version` (`string`, default: `"v2"`) and upgraded existing revisions safely.
   - `BatchImporter` checks `[v2_digest, v1_digest]` and upgrades legacy records in-place without creating duplicate revisions or mutating active corpus projections.
7. **QA4-07: Legacy Timestamp Fallback Removal & Strict Membership Fail-Closed Protection (P2):**
   - Removed timestamp inference heuristic (`created_at <= approved_at + 1.second`); replaced with strict `approved_release_revisions` membership across `CanonicalPosting#approved_revisions`, `CanonicalPosting.active_approved`, and `ProvenanceSerializer#render_mentions`.
   - Releases lacking memberships fail closed (HTTP 404 `:not_found` for public queries) and refuse activation (`activate!`).
8. **Round 4 Final Qualification Totals:**
   - Automated test suite: **110 tests, 648 assertions, 0 failures, 0 errors, 0 skips**.
   - Brakeman security scan: **0 active warnings, 3 ignored SQL warnings**.
   - Single-command qualification `bin/verify`: **ALL 7 GATES PASS (EXIT 0)** against a clean baseline of 4 active approved postings.

### Round 5 Audit Remediations

1. **QA5-01: Correlated Active Release Membership & Public Scope Isolation (P0):**
   - Corrected `CanonicalPosting.active_approved` and `CanonicalPosting.unapproved_staging` scopes to require a correlated SQL `EXISTS` subquery verifying that at least one `ApprovedReleaseRevision` belongs to that specific posting's `SourceRevision`s through `SourceMention`s within the active release.
   - Initialized all newly created `CanonicalPosting` instances with `approved_release_id: nil`, preventing new unapproved postings from inheriting prior publication approval when an existing `SourceRecord` is reused.
   - Scoped `ApprovedReleaseManager.current_revision` corpus counting strictly to `CanonicalPosting.active_approved.count`, ensuring unapproved staging imports never mutate `corpus_revision` or leak staging canaries/excerpts.
2. **QA5-02: Transaction-Safe BatchImporter Counters & Invariant Preservation (P1):**
   - Refactored `BatchImporter#import_batch` to track outcome in an item-local variable (`item_outcome`) evaluated within the database subtransaction. Aggregate counters (`inserted`, `updated`, `unchanged`) are only applied upon successful commit.
   - Rolled back items (e.g. `identity_conflict`, `origin_class_conflict`) immediately abort the subtransaction with zero orphan records and are accounted for strictly as exactly one `invalid` entry.
   - Enforced the required total accounting invariant: `total_input == inserted + updated + unchanged + invalid` across all success, partial, and failed import runs.
3. **QA5-03: Tier 3 Platform Key Verification & Tenant Divergence Guard (P1):**
   - Hardened `IdentityResolver#raw_tier3_candidates` and `IdentityResolver#find_tier3_candidates` to require a vetted platform key (`vetted_platform_key?`) from a recognized ATS domain (e.g., `greenhouse.io`, `lever.co`, `workday.com`), an operator-reviewed domain, or a trusted ingestion system.
   - Added `tier3_incompatible?` check: identical employer and unvetted platform IDs with differing titles or non-overlapping locations are withheld from merging and recorded with uncertainty (`PotentialDuplicate` with reason `unverified_shared_job_id`).
   - Merges verified ATS platform keys positively when job roles and locations match.
4. **QA5-04: Operator-Reviewed Provenance Grants for Official Source Authority (P1):**
   - Hardened `SourceAuthority.verified_official?` so that claiming an employer domain alone does not confer official authority. Domain matching is strictly an eligibility condition.
   - Official authority requires an explicit operator-reviewed composite record grant (`[source_system, source_record_key]`) in `config/source_authority.yml` or active release-scoped revision membership.
   - Prevents unverified third-party scrapers or malicious payloads from spoofing official authority by asserting claimed employer domains.
5. **QA5-05: Non-Mutating Production Verification & Explicit Publish Manifests (P1):**
   - Updated `bin/verify` to separate read-only qualification from fixture seeding. Added `--seed-demo` CLI flag and `DEMO_SEED_ALLOW` environment opt-in.
   - Prohibited fixture seeding and test execution in `Rails.env.production?` (exits non-zero if `--seed-demo` is passed in production), ensuring zero mutation of production databases.
   - Updated `bin/rails phantom:publish` to require explicit existing candidate batch and signed manifest file paths (`bin/rails phantom:publish[path/to/batch.json,path/to/manifest.json]`), rejecting implicit demo fixture defaults.
6. **QA5-06: Historical Safe-Fields Integrity for Revision Digest Upgrades (P2):**
   - Updated migration `UpgradeRevisionDigestsToV2` to reconstruct v2 digests using immutable historical `raw_safe_fields` rather than mutable current `SourceMention` and `SourceRecord` metadata.
   - Deterministically reconciles mention/record discrepancies against the historical record, logs audit trails, and safely collapses duplicate v2 rows.
   - Verified that replaying original source batches after migration registers as `unchanged: 1, inserted: 0`.

