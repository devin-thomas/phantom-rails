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
| **PHR-002** | Versioned source contract & hard fixtures | Not started | Pending |
| **PHR-003** | Privacy release candidate workflow | Not started | Pending |
| **PHR-004** | Relational provenance model | Not started | Pending |
| **PHR-005** | Trusted partial importer | Not started | Pending |
| **PHR-006** | Revision replay & import history | Not started | Pending |
| **PHR-007** | Conservative identity resolver | Not started | Pending |
| **PHR-008** | Field precedence & conflicts | Not started | Pending |
| **PHR-009** | Approved release projection & revision | Not started | Pending |
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
