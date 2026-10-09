# Phantom Rails — Implementation-Ready Build Pack

**Assembled:** October 9, 2026 · **Discovery:** 20/20 questions accepted · **Implementation:** Not started.

A standalone Ruby on Rails + PostgreSQL search API and reviewer-grade portfolio demonstration, inspired by but deliberately separate from the private BriefcaseOS system. This is a **plan**, not a running app or proof of deployment.

## What's in this ZIP

| File | Purpose |
| --- | --- |
| `PROJECT.md` | Accepted product boundaries, 20 discovery decisions, operational gates and non-diagram living model |
| `GLOSSARY.md` | Canonical domain terminology only; Matt Pocock skills v1.3-compatible |
| `ADR.md` | Append-only decisions ADR-001 through ADR-021, including Round 5 |
| `Ideas.md` | Explicitly excluded/deferred ideas and reserved naming |
| `SPEC.md` | Implementation-ready, inspectable behavior contract: data, APIs, privacy, algorithms, examples, errors, tests, hosting and optional provider comparison |
| `tickets/PHR-001` … `PHR-021` | Ordered vertical work units with observable acceptance and dependency boundaries |

**Keep these documents synchronized:** explicit owner instructions > `PROJECT.md` current boundaries + `GLOSSARY.md` vocabulary > ADR rationale > `SPEC.md` behavior > ticket acceptance. Do not implement `Ideas.md` by accident. Legacy mixed `Context.md` is not part of this new pack.

## Start here

1. Read `PROJECT.md`, `GLOSSARY.md`, `ADR.md`, then `SPEC.md` before selecting any ticket.
2. Create or choose a **new** `phantom-rails` repository only if the owner authorizes it. Do not assume a GitHub repository or database has been created.
3. Begin `tickets/PHR-001-foundation-rails-postgresql-docker.md` and work through the dependencies. Do not jump directly to a public demo before provenance and privacy gates.
4. Complete **PHR-001–PHR-019** to qualify the Core Release (live public preferred; documented Docker-only acceptance allowed). `PHR-020` and `PHR-021` are entirely optional, last-stage SerpApi features.
5. Generate and truthfully fill `docs/release-evidence.md` during implementation. If a check is blocked/unrun, write **not verified**, not "pass".

## Workstreams

| Phase | Tickets | Required result |
| --- | --- | --- |
| Foundation & safety | PHR-001–PHR-004 | Rails/PG Compose, source contract, sanitization/approval, relational model |
| Ingestion & reconciliation | PHR-005–PHR-009 | Partial import, replay history, matching tiers, field provenance, approved projection |
| Reviewer API | PHR-010–PHR-013 | Safe read responses, ranked compound search, signed cursors, provenance |
| Experience | PHR-014–PHR-015 | Executable OpenAPI + polished working playground |
| Verification & release | PHR-016–PHR-019 | Difficult corpus tests, clean-checkout CI, approved live or Docker release, case study |
| Optional integration | PHR-020–PHR-021 | Bounded SerpApi Google Jobs client and comparison report |

## Contract highlights

- **No visitor accounts, no public POST endpoints, no mailbox read requirement.** Trusted operator imports only.
- **Historical exports are private by default.** Automated safety + human approval on the exact candidate digest before publication. Synthetic fixtures explicitly labeled and intentionally hard.
- **Deterministic identity.** Strong employer ID/URL/platform ID merges; similarity without strong evidence is **flag-only**.
- **Explainable data.** Latest credible observation usually wins; verified official employer evidence can override with retained conflict and reason.
- **Search:** Compound AND filters, relevance weights (title 8 / company 5 / location 3 / excerpt 1), stable tie-breakers, signed version-bound cursors, explicit errors.
- **Host:** $0 preferred; <=$5/month **only upon separate owner approval**. Local Docker demonstration is accepted if live hosting fails. Never quietly use expiring free Postgres as durable storage.
- **Optional SerpApi:** Free-plan compatibility investigated; live key use and provider queries require separate approval and a hard local budget. No visitor-triggered external calls.
- **Career use:** SerpApi application already submitted; do not email any future result automatically.

## Known execution inputs, not blockers to writing the pack

Historical BriefcaseOS export isn't present in this ZIP and **must not** be copied here raw. Actual student Hostinger entitlement and any Neon/Render/Koyeb project are unverified. No SerpApi key, account access or live API credits are assumed. These are explicit acceptance/publication gates in SPEC §14, not license to invent data or provision services.

## Handy execution handoff

> Implement one Phantom Rails ticket at a time. First read `PROJECT.md`, `GLOSSARY.md`, `ADR.md`, `SPEC.md`, and the ordered ticket files. Preserve the 20 accepted decisions and strict privacy/publication gates. Begin at the first incomplete `PHR-###` ticket whose dependencies are satisfied. Run and record actual PostgreSQL/CI/HTTP/browser/privacy tests; never mark unexecuted checks as passed. Do not deploy, spend, publish private data, make SerpApi live calls or email a hiring team without separate explicit authorization. Update PROJECT, ADR, SPEC and affected tickets only when a material implementation discovery changes their meaning.

The separate diagram source is intentionally absent. Structured tables/prose in `PROJECT.md` are the portable model; intelligent UI in the chat may visualize it without becoming authoritative.
