# Phantom Rails

**A High-Integrity, Provenance-Aware Job Posting Search API and Reviewer Showcase**

[![Rails 8.1](https://img.shields.io/badge/Rails-8.1.4-CC0000.svg?logo=rubyonrails)](https://rubyonrails.org)
[![PostgreSQL 16](https://img.shields.io/badge/PostgreSQL-16--alpine-336791.svg?logo=postgresql)](https://www.postgresql.org)
[![Tests](https://img.shields.io/badge/Tests-93%20passed%20%2F%20521%20assertions-success.svg)](docs/release-evidence.md)
[![Status](https://img.shields.io/badge/Release-CORE--LOCAL%20Verified-blue.svg)](docs/release-evidence.md)
[![OpenAPI 3.1](https://img.shields.io/badge/OpenAPI-3.1.0-85EA2D.svg?logo=openapiinitiative)](public/openapi.json)

Phantom Rails is a standalone Ruby on Rails 8.1 + PostgreSQL 16 search API, interactive documentation explorer, and accessible reviewer playground. It demonstrates production-grade job posting reconciliation, data provenance, and explainable full-text search without data corruption, silent overrides, or tracking leaks.

---

## ⚡ Five-Minute Quickstart

### 1. Boot the Stack
Boot the containerized PostgreSQL 16 database and Rails 8.1 web service:
```bash
docker compose build
docker compose up -d
```

### 2. Run the Single-Command Qualification Suite
Run all verification gates (database connection, migrations, approved seeding, full 93-test suite, OpenAPI 3.1 schema, secret/canary scan, and zero-CDN audit):
```bash
docker compose exec web ruby bin/verify
```
*Expected output: All 7 gates PASS with Exit 0 against a clean baseline of 4 active approved postings.*

### 3. Reviewer Surfaces
- **Interactive Documentation**: [http://localhost:3000/docs](http://localhost:3000/docs) (Zero-CDN, self-contained interactive OpenAPI 3.1 explorer)
- **Reviewer Search Playground**: [http://localhost:3000/playground](http://localhost:3000/playground) (Accessible UI, live search, provenance inspection drawer)
- **OpenAPI 3.1 Specification**: [public/openapi.json](public/openapi.json)
- **Technical Case Study**: [docs/case-study.md](docs/case-study.md)
- **Release Evidence Ledger**: [docs/release-evidence.md](docs/release-evidence.md)

### 4. Sample API Queries
```bash
# Check service health and database connectivity
curl http://localhost:3000/api/v1/health

# Inspect active corpus version and publication revision
curl http://localhost:3000/api/v1/meta

# Ranked full-text search with compound AND filters
curl "http://localhost:3000/api/v1/postings?q=engineer&remote_type=remote"

# Inspect data provenance, field conflict resolution, and potential duplicate links
# (Queries a live posting ID dynamically from the search endpoint)
POSTING_ID=$(curl -s "http://localhost:3000/api/v1/postings?limit=1" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
curl "http://localhost:3000/api/v1/postings/$POSTING_ID/provenance"
```

For Windows PowerShell reviewers:
```powershell
$id = (Invoke-RestMethod "http://localhost:3000/api/v1/postings?limit=1").data[0].id
Invoke-RestMethod "http://localhost:3000/api/v1/postings/$id/provenance"
```

---

## 🏛️ Architecture Highlights

### Conservative 4-Tier Identity Matching (ADR-007)
Job aggregators often corrupt data by aggressively collapsing distinct job requisitions. Phantom Rails uses a strict hierarchy:
- **Tier 1 (Verified Employer Requisition ID)**: Matches sharing company and employer requisition ID merge into a single `CanonicalPosting`.
- **Tier 2 (Canonical Clean URL)**: Matches sharing normalized employer career page URL paths merge.
- **Tier 3 (Platform Source ID)**: Matches sharing verified ATS platform keys merge.
- **Tier 4 (Weak Text Similarity)**: Roles sharing company, title, and location without strong primary keys **never merge silently**. They are provisioned as separate postings and flagged bidirectionally as `potential_duplicate: true` for reviewer audit. Distinct requisitions (e.g. `REQ-101` and `REQ-102`) remain separate.

### Deterministic Field Precedence & Provenance (ADR-008, ADR-013)
When multiple sightings report conflicting compensation or titles:
- **Verified Official Override (`verified_official_override`)**: Observations originating from verified employer listings supersede observations from third-party boards, even if the third-party sighting is more recent.
- **Recency Baseline (`newest_credible`)**: For sources of equal authority, the newest observation wins.
- **Complete Audit Trail**: Every discarded alternative, timestamp, and selection reason code is preserved in `field_selections` and serialized at `/api/v1/postings/:id/provenance`.

### Revision-Safe Keyset Cursors (ADR-012)
- Zero SQL offsets (`OFFSET N`) for $O(1)$ database traversal.
- Cursors are HMAC-SHA256 signed tokens bound to the normalized query parameter digest (`qd`), the corpus revision, and a 15-minute TTL.
- Altering filters mid-traversal returns `400 cursor_query_mismatch`. Older cursors return `409 stale_cursor` or `410 cursor_expired`.
- Terminal lookahead returns `next_cursor: null` on the final page.

### Parameterized PostgreSQL Full-Text Search (ADR-011)
- GIN indexed `tsvector` column (`canonical_postings.search_vector`).
- Explainable field weights: **Title (+8)**, **Company (+5)**, **Location (+3)**, **Excerpt (+1)** per distinct query lexeme.
- Parameterized against SQL injection (`plainto_tsquery('english', ?)`).
- Null compensation and non-annualized hourly rates ($75/hr) are strictly excluded from annual USD salary filters.

### Zero-CDN Offline UI & Strict Privacy Gate (ADR-003, ADR-014, ADR-015)
- Zero external CDNs, web fonts, or analytics tracking; `/docs` and `/playground` run completely offline inside containerized environments.
- Read-only HTTP surface: Public mutations (POST, PUT, DELETE) reject with `405 Method Not Allowed`.
- Automated release gate calculates SHA-256 digests and scans for private email addresses, tracking parameters (`utm_*`, `gclid`), and canary tokens before publication.

---

## 📊 Ticket Execution & Release Status

| Phase | Tickets | Scope | Status |
|---|---|---|---|
| **Foundation & Safety** | PHR-001 – PHR-004 | Rails/PG Docker, schemas, sanitization, relational domain model | **COMPLETE** |
| **Ingestion & Provenance** | PHR-005 – PHR-009 | Partial importer, revision replay, identity resolver, field reconciler, approved release | **COMPLETE** |
| **Reviewer API** | PHR-010 – PHR-013 | Read API, weighted search, HMAC keyset cursors, provenance endpoint | **COMPLETE** |
| **Reviewer Experience** | PHR-014 – PHR-015 | OpenAPI 3.1 documentation (`/docs`), search playground (`/playground`) | **COMPLETE** |
| **Verification & Release** | PHR-016 – PHR-019 | Adversarial test suite, CI qualification, hosting qualification, case study | **COMPLETE** |
| **Optional SerpApi Integration** | PHR-020 – PHR-021 | Bounded SerpApi Google Jobs client and comparison evidence | *Deferred behind owner authorization ($0 budget preservation)* |

---

## 🛡️ Privacy & Security Commitments

1. **Zero Data Leaks**: Raw candidate records, private email accounts, and Outlook credentials from internal systems are strictly excluded. All demonstration data uses synthetic adversarial fixtures or digest-verified public records.
2. **Deterministic Budgets**: Exactly **$0.00** was spent on external services. Ephemeral databases (such as Render's 30-day auto-deleting Postgres tier) were rejected to preserve showcase durability.
3. **No Automatic Emails**: No job application follow-up emails are generated or dispatched automatically.

---

## 📄 License & Attribution

Authored by Devin Thomas. Released under the MIT License.
