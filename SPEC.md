# Phantom Rails — Implementation Specification

**Status:** Implementation-ready build contract, v1.0 planning edition (2026-10-09). **No code, real-data publication or deployment has been authorized.**  
**Authority:** Current owner direction > `PROJECT.md` scope > `GLOSSARY.md` terminology > accepted ADR rationale > this executable contract > ticket acceptance criteria. `Ideas.md` is non-binding.  
**Scope:** The core is mandatory; public-host deployment is preferred but conditionally substitutable by fully verified local Docker; SerpApi comparison is optional and sequenced *last*.

## 1. Definition of success

A code reviewer can clone the repository, boot a Ruby on Rails + PostgreSQL application in Docker, load a versioned **approved** sample corpus, use real keyword/filter/ranked/cursor API endpoints, open executable API documentation and a polished browser playground, inspect safe source evidence for a posting, and reproduce at least one conflict, potential duplicate, invalid row and correction/replay test. Every successful result is derived from persistent approved data, not UI-only mocks.

The reviewer should be able to understand *why* a result was merged, left separate, selected, ranked or rejected, without needing access to private BriefcaseOS material. A correct refusal is more valuable than a fabricated success.

**No release claim without evidence:** completed ticket means tests actually executed and captured; proposed commands or green-looking screenshots alone are insufficient.

### Release paths

- **CORE-LOCAL (required fallback):** Local Compose Rails/PG + docs/playground/API and acceptance corpus reproducibly qualify, with dated machine/toolchain evidence. Declare public availability **not verified**.
- **CORE-LIVE (preferred if feasible at $0):** Everything in CORE-LOCAL plus an approved sanitized corpus served at a live HTTPS URL, with deployment smoke and cold-start evidence; label limits honestly. The owner must separately approve deployment.
- **HISTORICAL-EVIDENCE:** Where an actual historical export exists, includes explicitly owner-approved sanitized historical examples; otherwise clearly identify the reviewed adversarial synthetic corpus and mark this gate pending. Never pass off invented examples as historical.
- **SERPAPI-STRETCH (optional):** Only after CORE-LOCAL, a manually approved API-keyed Google Jobs comparison succeeds or fails safely with recorded quota and response evidence. No public visitor endpoint can trigger it.

## 2. Stack and organization

- **Backend:** Rails 8.1.x stable, Ruby 3.4.x as a suggested supported pin; exact patch versions committed in `.ruby-version`/`Gemfile.lock` at foundation ticket. Use API-first Rails (`rails new phantom-rails --api --database=postgresql` is a *starting point*, not an executed command). Active Record for all persistence and migrations.
- **Database:** PostgreSQL 16+ with the same major version in development/test/production when available; Docker Compose for local and isolated test DB. PostgreSQL full-text search is sufficient; no Elasticsearch, document DB, vector store, Rails SQLite fallback or queue dependency for the core.
- **Core Ruby modules:** `ImportBatch`, `NormalizeMention`, `ResolvePostingIdentity`, `SelectCanonicalFields`, `SearchPostings`, `BuildProvenance`, `PublicReleaseGate` (names illustrative; do not make giant god-services). Keep deterministic domain logic away from controllers; controllers serialize validated, allowlisted read outputs.
- **Public UI:** Lightweight HTML/CSS/JS or TypeScript static bundles served under the **same origin** as Rails; accessible progressive enhancement. Swagger UI or another bundled standards-compliant explorer may use a generated OpenAPI 3.1 contract. Avoid requiring an external CDN, JS account or API key for basic browsing.
- **Operator:** Versioned `bin/rails`/Rake import, scrub/approve and release verification tasks; no anonymous and no authenticated HTTP mutation route in v1.
- **CI:** Ruby lint/static checks chosen at foundation ticket, Rails tests, PostgreSQL integration tests, UI smoke/accessibility tests, static privacy/secret scan, schema/OpenAPI validation and container build/smoke. Commit dependency lockfiles and image versions. No browser-dependent success claims unless a real automated browser run occurs.
- **Runtime:** One Rails web process is enough; no required Redis, Sidekiq, Elasticsearch, email delivery or real-time stack. No need to depend on AI inference to parse this benchmark.

### Suggested repository layout (implementation can refine internals)

```text
phantom-rails/
  README.md                         # startup and reviewer quick start
  PROJECT.md GLOSSARY.md ADR.md Ideas.md SPEC.md
  tickets/PHR-001-*.md ...
  app/controllers/api/v1/          # read-only HTTP
  app/models/                      # Active Record-backed domain
  app/services/                    # deterministic ingestion, matching, ranking
  db/migrate/                      # portable PG migrations
  lib/tasks/                       # trusted operator task entry points
  schemas/batch-v1.schema.json     # sanitized import contract
  schemas/public-release-v1.schema.json
  fixtures/public-approved/        # only explicitly approved sanitized data
  fixtures/adversarial/            # clearly synthetic, hard benchmark
  test/ or spec/                   # unit, model, request, contract and adversarial
  public/docs/ public/playground/  # accessible same-origin reviewer surfaces
  docs/case-study.md docs/release-evidence.md
  compose.yaml Dockerfile .env.example
  private/                         # NEVER committed; ignored by Git
```

The root Markdown files supplied in this ZIP are planning artifacts to copy into the future repository; they are not evidence the application already exists.

## 3. Data trust boundary and publication

### 3.1 Input classes

Accepted classes in a public release, each labeled in dataset metadata:

- `sanitized_historical`: an owner-reviewed record derived from an actual BriefcaseOS historical export. Its provenance claim requires an available inspected source and approval evidence.
- `adversarial_synthetic`: explicit synthetic variations modeled on a verified input shape or observed class of extraction failure, deliberately harder than the ordinary corpus.

A template or example created without a checked historical source MUST be labeled synthetic, not historical. The importer must not read a live mailbox, access private candidate profiles or make live provider calls to create core fixtures.

### 3.2 Private-to-public release sequence (non-skippable)

1. **Private staging:** Keep raw history outside Git and outside any deployable folder (`private/` ignored; secure owner-selected location). Local processing must not send data to AI/third-party services.
2. **Strict export allowlist:** Create a sanitized JSON/JSONL release candidate containing only the fields in section 4. Drop personal names/emails, candidate/application status, mail headers, account IDs, credentials, and raw email bodies *before* writing the candidate.
3. **Source URL and excerpt scrub:** Remove tracking parameters, fragments, userinfo, personal tokens and unsupported external URLs. Human-readable source excerpts are short (`<= 220` characters after sanitization), plain text and must exclude private statements; reject rather than substitute if uncertain.
4. **Automated privacy gate:** Scan all candidate fields, URLs, example output, logs, static assets and optional imported report for secrets, emails, contact details, mailbox tokens, session IDs, tracked click URLs, employer-confidential content and known test canaries. Regex alone is not sufficient; use structural allowlists, deny-by-default validators and negative tests.
5. **Manual sign-off:** Generate stable SHA-256 of canonical release-candidate bytes and a manifest describing input class counts, restrictions, corpus version and automated checks. Operator approves **exact digest** only. Modification invalidates approval; empty/incomplete approval fails closed. Record approval without including raw private data or credentials.
6. **Publication path:** Only approved immutable candidate bytes can enter the public corpus, repository release assets, test showcase or deployed Postgres. Reviewer-visible provenance is serialized from a *second* explicit public-output allowlist, never by dumping an Active Record object wholesale.

No private source identifiers in public URLs, JSON, HTML, console output or response errors. Public IDs are independent generated identifiers; public source references must not be direct Outlook message IDs, personal filenames, redirect tokens, secret-laden URLs or HMACs whose key is embedded client-side.

**Release failure:** Privacy scan failure, missing approval, digest mismatch or ambiguous provenance blocks public publish and reports an actionable operator-only error. Never retry by loosening the sanitizer. A local unapproved import remains private and is not visible on public endpoints.

## 4. Versioned sanitized source contract

`batch_schema_version: "1.0"`; JSON or JSONL, UTF-8. Batch envelope (JSON form):

```json
{
  "batch_schema_version": "1.0",
  "batch_id": "reviewed-corpus-v1",
  "origin_class": "adversarial_synthetic",
  "items": [
    {
      "source_record_key": "fixture-digest-007",
      "source_system": "reviewed_export",
      "observed_at": "2026-09-25T14:30:00Z",
      "mention_key": "item-1",
      "source_kind": "third_party_board",
      "source_domain": "jobs.example.org",
      "job_id": "EXAMPLE-901",
      "title": "Technical Support Engineer",
      "company": "Example Systems",
      "location": "Austin, TX",
      "remote_type": "hybrid",
      "employment_type": "full_time",
      "salary": { "min": 85000, "max": 105000, "currency": "USD", "period": "year" },
      "summary_excerpt": "Investigate customer API failures and document reproducible steps.",
      "job_url": "https://jobs.example.org/posting/EXAMPLE-901"
    }
  ]
}
```

This is **synthetic illustrative JSON** and must not be claimed as historic or deployed without the release procedure. `source_record_key`, `mention_key`, `source_system`, `observed_at`, `source_kind`, `title`, `company`, and `location` are required; all other fields optional with explicit `null` if absent. `origin_class` is required and must be `sanitized_historical` or `adversarial_synthetic`; `source_kind` must be `official_employer`, `third_party_board`, `email_digest`, or `other_reviewed`, and `remote_type`/`employment_type` use the enums in §8.1. A flattened JSONL item can repeat required batch metadata; a validator normalizes both to one canonical in-memory representation. One source item represents one mention; multi-posting emails are split in private staging with stable per-mention keys.

Rules:

- Enforce length limits (e.g. 200 for title/company/location, 220 for excerpts, 512 for canonical vetted URL, 128 for IDs), enum sets, UTF-8, object-only shapes and RFC3339 timezone-aware UTC-normalized times. Reject unknown input keys instead of serializing surprises.
- `source_domain` and `source_kind` are **untrusted origin assertions** from the candidate, never sufficient to assert official employer authority. Authority comes from an operator-reviewed, versioned `source-authority` manifest bound to the release candidate. Anonymous visitors cannot register trust.
- Preserve whether date is a **source observation**, reported job publication date, or import timestamp; never treat the import clock as job posting date. Unknown fields stay `null`, never invent compensation or posted dates.
- Salary is preserved in stated currency and period. For annual-USD filtering, include only verified USD/year observations; do not silently annualize hourly figures with invented paid hours.
- Display externally linkable job URLs only when their canonical destination was explicitly approved. Reject file/javascript/data schemes, private IP/userinfo hosts, tracking tokens and malformed URLs. No background fetching of imported URLs.
- Version checks occur before writes: unsupported schema version or unreadable batch container fails atomically (0 accepted). Parseable mixed-quality batch uses item-level isolation per section 5.

## 5. Persistence, imports, corrections and failures

### 5.1 Minimum relational model

| Table/entity | Key fields | Constraint / purpose |
| --- | --- | --- |
| `source_records` | opaque ID, `(source_system, source_record_key)`, origin_class, approved_release_id | Stable input grouping, sanitized/public-safe only |
| `source_mentions` | opaque ID, source_record_id, mention_key, canonical_posting_id | One occurrence; unique `(source_record_id, mention_key)` |
| `source_revisions` | source_mention_id, revision_digest, observed_at, safe selected fields, source_kind | Immutable revision history; unique `(source_mention_id, revision_digest)` |
| `canonical_postings` | opaque public ID, chosen title/company/location, normalized search fields, corpus revision | Current derived projection, not a replacement for mentions |
| `field_selections` | posting ID, field name, chosen source revision ID, selection reason | Explainable per-field projection, alternatives reconstructed from revisions |
| `potential_duplicates` | posting A, posting B, reason code, evaluation digest | Canonical ordered pair unique; weak similarity never mutates identity |
| `import_runs` | batch ID/digest, outcome, inserted/updated/unchanged/invalid counts, UTC time | Every attempted batch, including zero-change replays, has report history |
| `import_errors` | import run ID, item index and safe error code/message | Sanitized errors only, never raw rejected payloads |
| `approved_releases` | manifest digest, approval digest, timestamp, active marker | Only the active approved release is eligible for public serialization |

Associations, foreign keys and indexes must be enforced at the DB level where practical. Public IDs must not expose sequential private source or candidate identities. Derived search index/projections may be recalculated. Use one selected Active Record association strategy; do not create ambiguous duplicate sources of truth.

### 5.2 Deterministic import transaction semantics

- Validate batch structure, schema version, approval context and file safety before any row writes. A completely unreadable or unsupported batch fails all-or-nothing with a safe report.
- For a parseable batch, validate each item independently. A valid item is inserted/updated transactionally, invalid item rejected with indexed error code, safe message and no partial record. One invalid item doesn't roll back unrelated valid items.
- If two conflicting revisions for the same `(source_system, source_record_key, mention_key)` appear **within one unordered batch**, quarantine all conflicting entries for that key as invalid (`ambiguous_revision_order`). Require distinct, chronologically ordered batches for corrections; do not choose arbitrarily by file order or hash sort.
- A source mention's revision digest is SHA-256 over canonicalized allowlisted observation fields and the stable source identity, with stable key order and timezone formatting. Identical replay adds no duplicate mention/revision/posting; import attempt may add a no-op `import_runs` record, and **does not bump the Corpus Revision**.
- A changed source item creates immutable `source_revisions` history, changes the canonical projection when allowed, retains earlier values and records an import run. It cannot silently move an existing source identity to a conflicting posting ID; mark `identity_conflict` and reject/flag rather than erasing its prior association.
- Process valid unrelated records even when one item has an identity conflict. For a fatal DB outage, roll back active transaction(s), mark import failed, preserve the pre-run canonical state where transactions protect it, and do not report successful completion.
- Successful parseable imports return `complete` (no invalid), `partial` (some invalid) or `failed` (nothing accepted because errors); reports disclose counts `input`, `inserted`, `updated`, `unchanged`, `invalid` and safe errors. Totals must account for every input item; `unchanged` is a real result distinct from a new import.
- Store immutable import and revision evidence only for sanitized sources. Raw invalid item bytes remain outside public database/logs; optional operator-only quarantine files are ignored from Git and excluded from deployment images.

## 6. Identity: canonical versus uncertain

Identity rules apply in deterministic, strongest-to-weakest tiers, normalized consistently across imports:

1. **Tier 1 (strong):** Same verified employer identity and employer-issued requisition/job ID, with both identity and employer mapping operator-approved.
2. **Tier 2 (strong):** Same canonicalized approved employer-host job URL with exact relevant path/identifier, after removal of *known* tracking parameters and fragments. Do not discard ID-bearing query parameters or collapse different URLs based on titles.
3. **Tier 3 (strong, source-scoped):** Same stable platform posting ID **on the same vetted platform**; do not assume two different boards share job IDs.
4. **Tier 4 (uncertain only):** Matching normalized company/title/location, or similar titles/locations without a strong key. Preserve distinct Canonical Postings and attach `potential_duplicate` metadata; no fuzzy/LLM auto-merge.

If two strong signals conflict (e.g., same URL but different vetted employer ID), fail closed for that item as `identity_conflict` and flag affected records for operator review; never quietly prefer the weaker signal. Stable per-source mention keys guard replay even when no match tier exists. Never merge two openings merely because their titles and employers match (multiple locations or requisitions exist). No manual-review dashboard required; inspect import reports and public approved ambiguity explanations.

## 7. Field-level reconciliation and provenance

For each field (`title`, `company`, `location`, `remote_type`, `employment_type`, `salary`, `summary_excerpt`, `job_url`, optionally reported `posted_at`), keep validated observation candidates with `observed_at`, stable source revision, authority evidence and origin class.

- **Baseline:** The newest credible observation with a valid field value wins, comparing actual source `observed_at`; do not substitute ingestion clock.
- **Significant exception:** For authoritative facts such as official job title, location, requisition, pay range, work type, employer-specific application URL, an explicitly operator-verified employer listing may override a conflicting, later third-party observation. Record reason code `verified_official_override`, source of verification, chosen timestamp, alternatives and their timestamps. Never infer verification from the input domain alone.
- **Quality exceptions:** Reject invalid/out-of-range salary, malformed URLs, contradictory or unverifiable dates, empty placeholders and unsupported values before comparing timestamps; record `invalid_observation` without silently replacing with plausible defaults.
- **Tie-breakers:** Within equally credible sources, choose latest observed_at; then explicit vetted authority rank if equal; then stable `source_mention_id` and revision digest lexicographically. Sorting must not depend on DB row iteration.
- **Conflicts:** Preserve disagreeing observations, never erase a conflict when resolving the current field. Public projection exposes safe chosen value, safe alternate summaries and reason; sensitive raw text stays private.
- **Derived values:** Canonical fields and relevance/search fields are projections. Rebuild from immutable current tip of each source revision chain; no stale derived copy should silently override retained evidence.

**Example:** A third-party board reports "$90k–$120k" yesterday; a verified current employer listing says "$80k–$110k" three days earlier. Preserve both, choose the employer range with `verified_official_override`, and show a public-safe conflict summary. If the supposed employer URL isn't vetted, latest credible third-party value may win instead.

## 8. Public API v1 (GET/HEAD only)

All public routes use `/api/v1`; JSON responses use `application/json; charset=utf-8`, UTC RFC3339 timestamps, snake_case keys. Do not add public mutation routes. Routes:

| Method and path | Purpose |
| --- | --- |
| `GET /api/v1/postings` | Search/filter/sort/cursor page of Canonical Postings in active approved corpus |
| `GET /api/v1/postings/:id` | One safe result + source/conflict/ambiguity summaries |
| `GET /api/v1/postings/:id/provenance` | Vetted Source Mentions, selected field decisions, safe alternate values and issue summaries |
| `GET /api/v1/meta` | Corpus revision, data origin counts, enabled filters/sorts, source-safety disclaimer |
| `GET /api/v1/health` | Non-sensitive readiness (`ok`, DB connectivity, approved release availability) |
| `GET /openapi.json` | Versioned machine-readable OpenAPI 3.1 contract |
| `GET /docs` | Bundled interactive API explorer using the actual OpenAPI contract |
| `GET /playground` | Public browser interface consuming those same live HTTP GET endpoints |

HEAD semantics may be handled by Rails; `POST`/`PATCH`/`PUT`/`DELETE` on these paths must return 404/405 without mutation and without revealing admin endpoints. Bound read pressure through parameter caps, query timeouts, a documented modest IP-based rate limit where the runtime supports it, and safe 429 `rate_limited` responses; in-process rate limits that reset on cold start are best-effort, not a durable anti-abuse guarantee. Never expose a public route that incurs SerpApi credits. `/health` must not expose credentials, environment variables, hostnames, private source keys or stack traces.

### 8.1 Filters, sort and validation

- `q`: optional UTF-8 keyword query, trimmed, <=120 characters and max 8 meaningful lexemes; use parameterized PostgreSQL `plainto_tsquery('english', q)` and safe `to_tsvector`/indexed equivalents. Disallow raw SQL, arbitrary full-text operator language, uncontrolled wildcards and opaque LLM search. Blank/only-stopword query is treated as absent or rejected consistently and documented.
- Compound filters: `company` (case-insensitive exact normalized company), `location` (normalized city/state text), `remote_type` (`onsite|hybrid|remote|unknown`), `employment_type` (`full_time|part_time|contract|internship|temporary|unknown`), `min_salary_usd` (integer annual-USD minimum; exclude unknown/non-annualized salary instead of fabricating hours). All filters combine with logical AND and may coexist with `q`.
- `sort`: `relevance` (allowed only with `q`; default when query present), `newest` (default without `q`, by `last_observed_at DESC` computed from the latest credible source `observed_at` timestamp, **not** an invented original posting date), `company`, `title`. All sort orders have stable public ID final tie-breaker; null sorting documented and tested.
- `limit`: integer 1–50, default 20. `cursor`: opaque, signed server token. No offset/page-number pagination in v1.
- `q`, filter fields and sort key must be documented in OpenAPI; unsupported values, oversized strings, duplicate conflicting filters and invalid integers return 400 with safe `invalid_parameter` details, never a 500 or reflected raw payload.
- Search includes only approved Canonical Postings, even if local staging contains additional data. Display a concise `data_origin` badge/label for historical vs synthetic examples in the playground and API output.

### 8.2 Bounded field-weighted deterministic ranking

For a nonempty query, use an indexed combined PostgreSQL search vector for candidate filtering, then an explainable integer score over normalized lexemes:

- Each matching query lexeme in `title`: **+8**
- In `company`: **+5**
- In `location`: **+3**
- In `summary_excerpt`: **+1**

Each (field, query lexeme) contributes at most once (duplicates in a text field cannot spam the score). Require **all meaningful query lexemes** to be present across the combined indexed fields; if not, no match. Language stemming/stopword normalization follows the pinned PostgreSQL `english` text-search config and is tested; do not imply substring, spelling correction or semantic match. Relevance score and optional match-reason counts are **derived** at request time, not a persisted canonical truth. Sort `score DESC, stable_public_id ASC` unless the client requests another sort; ties must be deterministic. All score terms and query inputs must be parameterized/escaped. Reproduce ranking exactly in local, CI and deployed PG version.

This is the specific Q12 B-plus enhancement selected in Q13; fuzzy edit distance, vectors and external search engines are out of scope.

### 8.3 Cursor and publication revision

Opaque cursor is base64url-encoded JSON containing version, active `corpus_revision`, normalized filter/sort/query digest, last page's sort tuple and expiry, signed with a server-only HMAC key. Clients never construct cursors. Increment Corpus Revision only when active approved searchable state changes, not for read traffic or identical replay. New/reapproved data invalidates old cursors rather than silently mixing two corpora.

- Valid cursor + unchanged revision: return next page with no duplicates or gaps for stable corpus.
- Reused cursor with different filters/sort: **400** `cursor_query_mismatch`.
- Tampered/unknown cursor: **400** `invalid_cursor`.
- Expired cursor: **410** `cursor_expired`.
- Approved corpus revision changed since cursor: **409** `stale_cursor`, with non-sensitive restart instruction.
- Exact final page: `next_cursor: null`; `limit+1` internal lookahead may determine `has_more` without offset pagination.

Suggested cursor TTL is 15 minutes; rotate signing key deliberately, invalidating old cursors safely. The cursor payload is not an authorization credential and must never expose source history or secrets.

### 8.4 Representative response and errors

```json
{
  "data": [{
    "id": "post_example_a1",
    "title": "Technical Support Engineer",
    "company": "Example Systems",
    "location": "Austin, TX",
    "remote_type": "hybrid",
    "employment_type": "full_time",
    "salary": {"min": 85000, "max": 105000, "currency": "USD", "period": "year"},
    "relevance_score": 16,
    "origin_class": "adversarial_synthetic",
    "potential_duplicate": false,
    "provenance_url": "/api/v1/postings/post_example_a1/provenance"
  }],
  "page": {"limit": 20, "next_cursor": null, "corpus_revision": "example-revision-digest"},
  "meta": {"sort": "relevance", "query": "technical support"}
}
```

Illustrative **synthetic response**; `technical` and `support` each match the title (+8 each = 16), assuming no other matching field. This is a contract example, not an assertion that code is implemented. All read serializers are explicit allowlists. The detail and provenance endpoints may expand safe conflict/ranking explanations without exposing raw input snapshots or unpublished fields.

Consistent error envelope:

```json
{"error": {"code": "invalid_parameter", "message": "limit must be from 1 to 50", "request_id": "opaque-public-id"}}
```

Errors must not reflect private values, SQL, stack traces, secrets or raw source records. Return 404 for missing IDs and fail closed when release not approved. For database outage return 503 with safe error plus retry hint; frontend must display honest unavailable state, not synthetic search hits.

## 9. Search playground and executable documentation

The playground is **a real client** of `/api/v1` on the same origin. Responsive mobile-first and useful at 320px; keyboard focus, accessible names, screen-reader status for pending/result/empty/error, reduced motion, contrast, and loading states. No account, analytics trackers, autoplay, marketing panels, unnecessary UI library or backend credentials.

User journey:

1. Open `/playground` → see data-origin disclaimer, example queries and the latest approved corpus summary.
2. Enter keywords and several filters; submit request; show live loading/empty/error/result states with reproducible query URL (safe GET only).
3. Compare normalized posting cards; distinguish historical versus adversarial data; follow `next_cursor` without losing current filters.
4. Open detail/provenance for a posting; inspect why multiple mentions merged, why a suspected duplicate stayed separate and why one conflicting field was chosen.
5. Open `/docs`, execute the exact same read-only request and inspect response schemas and error types. `openapi.json` must be generated from or contract-checked against actual routes; never advertise endpoints that do not exist.

Only safe approved excerpts appear, max 220 characters; never render unsafe HTML from imported records (escape text rather than `innerHTML`). Cache control and CORS must avoid cross-origin private exposure; no credentials on client. Direct requests from curl must behave the same as UI requests.

## 10. Benchmark, tests and acceptance

### 10.1 Minimum adversarial fixture suite

Use actual observed source shapes as a design reference and deliberately construct tests that include at least these cases:

1. Identical reposted employer ID with different tracking URL params → one Canonical Posting, multiple mentions.
2. Two different employer requisitions with same company/title/location → separate postings.
3. Same posting appearing on employer website and third-party board with conflicting salary → employer value selected only if official origin independently verified; both observations retained.
4. Newer third-party update versus older authoritative employer listing → documented exception with timestamps.
5. Ambiguous company/title/location similarity with no strong ID → distinct postings and `potential_duplicate`.
6. A corrected source revision → previous observation retained, new canonical projection computed.
7. Identical batch replay → no duplicate revisions/postings, corpus revision unchanged, import run marked no-op.
8. Mixed valid/invalid records → all valid independent items accepted, invalid isolated with safe diagnostics and explicit `partial` status.
9. Multiple conflicting revisions for one source key in an unordered batch → those entries rejected as ambiguous, independent items processed.
10. Invalid/unsupported batch version or malformed entire JSON → all-or-nothing failure and unchanged corpus.
11. Unicode punctuation/accents/CRLF/HTML-like payloads → canonical escaping/normalization without executable HTML or lost identifiers.
12. Unknown pay/currency/unit and nonsensical dates → null or rejected, never invented annual salary or posting time.
13. Known credential/email/URL-token canaries in private raw input → no public artifact or response contains them; release blocked.
14. Cursor tampering, filter mismatch, expiry, corpus mutation and tie pagination → precisely defined 400/409/410 behaviors, no duplicate results.
15. Query injection, long query, unsupported filters, missing posting and database outage → safe deterministic HTTP errors.
16. Public POST/PUT/PATCH/DELETE attempts → no writes or hidden route access.

Provide at least one positive and one negative assertion for each contract-sensitive behavior, plus a nontrivial fixture corpus with multiple employers, locations, boards, reappearing job IDs and separate revisions. Counts alone do not prove coverage. Each adversarial file clearly labeled `adversarial_synthetic`; historical label needs actual source clearance.

### 10.2 Required evidence

Every release qualification includes a dated `docs/release-evidence.md` noting: git SHA, Ruby/Rails/PG version, full shell commands, test counts and pass/fail outputs, container startup, API curl responses, browser Playwright (or equivalent) evidence, privacy scan results, data-origin composition and manual sign-off digest where applicable. Record blocked/missing checks as **not verified**, not as passing.

Required test families:

- Model/DB migrations, constraints, transaction behavior and query indices; compare plans/index use on benchmark queries where relevant.
- Sanitizer/negative-leak tests including traversal, embedded URL tokens, encoded tracking fields, case variants and sample client error responses.
- Import versions, mixed acceptance, corrections, replay, audit history, provenance reconstructability and deterministic identical-output checks.
- Tiered match false merges, false splits/potential duplicate, source verified authority overrides and field tie-breaks.
- Search filter combinations, relevance weights, ties, cursors and public serializer field allowlists.
- OpenAPI contract validation (route, params, examples, error codes) and actual HTTP request integration tests.
- Browser responsive/keyboard/focus/empty/loading/error states; no UI-only mocked final results.
- CI fail-on-test-failure, clean-checkout Docker build and commands; verify no private export/secrets/private fixtures tracked.

### 10.3 Release commands (expected user-facing contract, not executed yet)

```bash
cp .env.example .env
# Do not put actual secrets into version control.
docker compose up --build -d
# Wait for Postgres readiness, then:
docker compose exec web bin/rails db:prepare
docker compose exec web bin/rails phantom:import[fixtures/public-approved/approved-batch-v1.json]
docker compose exec web bin/rails test
# Open http://localhost:3000/docs and /playground
curl --fail 'http://localhost:3000/api/v1/postings?q=engineer&limit=10'
```

Actual Rake task and file names must match the final implementation; these are the proposed external-facing commands, not claims that they currently work. Provide Windows PowerShell equivalents or a `bin/verify` script to avoid shell quoting pitfalls. `docker compose down -v` is destructive and must not be the default cleanup path. Test schema isolation must not delete production volumes.

## 11. Hosting, cost and fallback

Deploy only after the owner gives explicit authorization and the **exact** approved corpus is verified. Do not provision paid resources from this build plan. Keep source and test PostgreSQL consistent.

| Candidate | Fit | Gate / caveat |
| --- | --- | --- |
| Render Free Web + independent durable-enough free PostgreSQL (e.g. Neon Free) | Rails web runtime + PG technically plausible | Render sleeps after ~15 minutes idle and next cold start can be ~1 minute; Render **Free PostgreSQL itself expires after 30 days**, unsuitable for a durable hosted showcase. External PG egress and cold-start behavior need live tests. |
| Koyeb Free Web + verified free PostgreSQL | Also supports Rails containers | Free instance ~512MB RAM / 0.1 vCPU, scales to zero after inactivity. Prove Rails boot/memory and database connections before choosing. |
| Existing Hostinger student Web/Cloud plan | Possibly useful for static docs only | Official Hostinger material says PostgreSQL needs VPS; do not assume student benefit includes VPS or a Ruby-capable runtime. |
| Local Docker Compose (fallback) | Fully acceptable Q18 Core Release | Must be fast to clone/boot/seed/test; cannot be described as live public hosting. |

An external free PG provider's current quotas, signup/payment requirements, auto-suspension and outbound network costs must be rechecked on deployment day. Keep public demo corpus reproducibly seedable from approved versioned sources rather than relying on a host's ephemeral filesystem. No monetized services, background pings to keep instances alive, or hidden charges.

If viable `$0` live host exists and has acceptable cold starts, preferred release is CORE-LIVE. If not, use CORE-LOCAL and document why, not a fake hosted facade. Any choice to spend <=$5/month is a **proposal pending owner approval**, never automatic.

## 12. Last-stage optional SerpApi provider comparison

**Must be implemented only after all mandatory core tickets qualify.** SerpApi advertises a $0 tier with 250 successful searches/month and 50/hour as checked 2026-10-09; provider pricing and availability can change. Use the official `engine=google_jobs` API with a **manual operator** query and location, not a visitor-triggered GET endpoint. Do not confuse the separate `google_jobs_listing` engine with the main job search result API.

- Read `SERPAPI_API_KEY` only from a runtime secret/env file not tracked in Git; never send it to a browser, paste it into logs, include it in diagnostic JSON or embed it in URLs persisted publicly.
- Hard-limit optional trial to at most **2 provider searches per invocation and 20 per month** locally (well below advertised quota); persist a monthly consumption ledger in PostgreSQL so process restarts cannot reset the cap, and cross-check quota through the Account API where available. Never log Account API key-bearing responses. No periodic scheduler, retry loop or automatically triggered public call; user authorizes the live invocation itself.
- Use a bounded HTTP client, strict TLS verification, fixed SerpApi host, allowed API parameters, max 30s read timeout and payload size cap. Treat HTTP failures, provider `search_metadata.status != Success`, provider `error`, missing `jobs_results`, exhausted quota, unusual schema and no matches as distinct observable outcomes; never claim no jobs when provider failed.
- Convert supported SerpApi job `title`, `company_name`, `location`, `job_id`, `description`, `detected_extensions`, `via` and vetted `apply_options` into a temporary **separately attributed** comparison projection. Missing data is unknown; never treat provider result fields as an official employer source without independent verification.
- Compare to approved local postings using the same deterministic strong-key rules when possible. Record matched, uncertain, unmatched and conflicting field summaries with safe source references; never publish raw provider JSON, spend credits on tests, or automatically append to the approved Canonical Postings.
- Stub/provider-fixture tests must pass with **zero network calls**. Failure/unconfigured-key/quota cases must degrade to a clear "optional comparison unavailable" without breaking the core.
- The provider has documented degraded/fixed Google Jobs episodes in 2026; availability and response schema should be treated as external and fallible, not guaranteed.

## 13. Case study, handoff and honest claims

Publish `docs/case-study.md` with concise problem → engineering choices → data boundaries → tricky failures → tests actually run → links to implementation → known limitations. A short "for SerpApi engineers" reading path should recommend README, public `/docs`, a reproducible example query, the potential-duplicate case, field-override case and relevant tests. Explain independently learned Ruby/Rails rather than suggesting employer-paid Ruby experience. Do not quote or publish private job-search records, internal employer material or sensitive source emails.

The repository should make it possible to verify the work without trusting promotional adjectives. Include a `STATUS` / `Verification` table that differentiates **implemented / locally verified / publicly deployed / optional planned / blocked**. If public deployment occurs, include live HTTPS links, safe cache/persistence behavior, published source SHA and release-corpus digest. Sending a follow-up to SerpApi is separately authorized and not an automation.

## 14. Open preflight gates — not new discovery rounds

These are execution evidence gates rather than unresolved product scope:

1. **Actual historical export:** Owner supplies an available historical file outside source control for the sanitization lane; if unavailable, public examples remain explicitly adversarial synthetic and historical authenticity gate stays pending.
2. **Release approval:** Operator must review exact sanitized manifest and SHA-256 before publish. No approval can be simulated by a flag in unattended CI.
3. **Host compatibility:** Identify actual `Hostinger` student plan; verify a $0 Rails + PG combination (or use accepted Docker fallback). No implied payment method/automatic upgrade.
4. **External provider:** SerpApi key and bounded live-call authorization are absent; integration remains optional and offline-testable.

No new business/product decisions are necessary to write tickets. Any implementation discovering a materially different requirement must update `PROJECT.md`/ADR/SPEC and affected tickets instead of silently choosing an incompatible direction.

## 15. Primary technical references (verified October 9, 2026)

- Rails 8.1 official guide (Rails version baseline): https://guides.rubyonrails.org/index.html
- Rails API-only applications: https://guides.rubyonrails.org/api_app.html
- Active Record with PostgreSQL and full-text search: https://guides.rubyonrails.org/active_record_postgresql.html
- SerpApi Free pricing: https://serpapi.com/pricing
- SerpApi Google Jobs API and failures: https://serpapi.com/google-jobs-api
- SerpApi Account API: https://serpapi.com/account-api
- SerpApi Google Jobs release notes: https://serpapi.com/google-jobs-api/release-notes
- Render free-service constraints: https://render.com/docs/free
- Koyeb free instance limits: https://www.koyeb.com/docs/reference/instances
- Hostinger PostgreSQL restrictions: https://support.hostinger.com/en/articles/1583659-is-postgresql-supported-at-hostinger
- Neon free plan candidate (quota must be reverified at deployment): https://neon.com/pricing
- Prior BriefcaseOS private importer inspected by owner-authorized GitHub connector: `devin-thomas/briefcase-os-internal` (`importer_correction_chain.py`). This is a reference for data shapes, **not** a commitment to reuse its all-or-nothing batch semantics: Q7 explicitly requires independent item-level partial acceptance.
