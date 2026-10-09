# Phantom Rails — Project Brief

**Stage:** Discovery closed; five rounds, all **20/20 questions answered**. Build-pack authoring complete; implementation has not begun.  
**As of:** 2026-10-09.  
**Project identity:** `Phantom Rails` / recommended repository slug `phantom-rails` (repository not created by this pack).  
**Product objective:** A standalone, inspectable Ruby on Rails / PostgreSQL search API for challenging job-source records. It is a portfolio engineering demonstration, not the live BriefcaseOS product.

## Why this exists

Demonstrate competence relevant to SerpApi: robust ingestion, source normalization, cautious deduplication, explainable field reconciliation, rigorous data privacy, API usability, reproducible testing, real failure visibility and thoughtful delivery. The SerpApi Junior Fullstack Engineer application has **already been submitted**. This may be shared as a **post-application follow-up after it works**, but must not trigger an email, publication, hosting purchase or deployment without separate approval.

The name is a personal Final Fantasy VI inspiration; source code, API names, internal entities and UI text must use ordinary engineering terminology. `Suplex Express` is reserved separately, not a component name.

## Accepted discovery decisions (20 of 20)

| Question | Accepted rule | Rationale or qualification |
| --- | --- | --- |
| Q1 | Independent public portfolio API | No runtime dependency on BriefcaseOS |
| Q2 | Sanitized historical BriefcaseOS export is preferred | Clearly labeled, *harder* adversarial synthetic examples allowed when modeled on actual source shapes and observed failure classes; never imply they are historical |
| Q3 | Ingestion, normalization, provenance, failures **and** search | More rigorous than CRUD |
| Q4 | **Both** public read API with interactive documentation and browser search playground | Complementary rather than alternative experiences; no visitor accounts |
| Q5 | One Canonical Posting can have many Source Mentions | Never lose independent observations |
| Q6 | Versioned operator CLI/Rake ingestion only | Anonymous public interface is read-only |
| Q7 | Item-level partial acceptance with invalid-item diagnostics | Complete success must never be claimed for mixed batches |
| Q8 | Safe public excerpts, source references and issue summaries | No private messages or hidden identifiers published |
| Q9 | Tiered deterministic matching; ambiguous pairs remain separate and flagged | Prefer false non-merge to destructive false merge |
| Q10 | Newest credible field observation by default; meaningful authority/quality exception | Verified employer-origin evidence may beat newer third-party text; preserve alternatives and selection reason |
| Q11 | Allowlist + automatic privacy checks + explicit human release sign-off | Importing is not permission to publish |
| Q12 | Keyword search, compound filters, stable sort, cursor pagination and provenance | B-plus, not a general search engine |
| Q13 | Field-weighted deterministic relevance | Explainable ranking instead of fuzzy/semantic black boxes |
| Q14 | Incremental idempotent imports; retain revisions and run history | Replaying identical source cannot create duplicate searchable state |
| Q15 | PostgreSQL via Rails Active Record in **all** environments | No local SQLite / production PostgreSQL divergence |
| Q16 | Target $0 monthly; consider up to $5/month only upon **separate explicit approval** | No current spend authorization; test Hostinger student entitlement, don't assume VPS |
| Q17 | Repeatable difficult-corpus, privacy, replay and API-contract acceptance suite | QA evidence over self-reported success |
| Q18 | Prefer public live API; verified local Docker demonstration is an acceptable release fallback | Inability to secure $0 hosting must not turn valid engineering into an endless project |
| Q19 | Last-stage, optional, quota-bounded SerpApi query and historical-corpus comparison | Core must stand without external calls; secret never exposed |
| Q20 | Polished playground, interactive docs, reproducible showcase and evidence-led write-up | Valuable to a reviewer who spends only a few minutes |

## Audiences and responsibilities

- **Visitor / reviewer:** An anonymous read-only user of the public API, Swagger-like executable reference, and browser playground. Must be able to inspect an example and understand data provenance without obtaining the source corpus.
- **Operator / maintainer:** Runs trusted imports, approves sanitized release candidates, observes failures, runs qualification suites and (with separate authorization) publishes a release.
- **External provider (optional):** SerpApi's Google Jobs search response, accessed only by a manual operator-triggered integration in the last ticket sequence.

## Canonical system model (prose/table; no persistent drawn diagram)

| Boundary | Input | Output / invariant |
| --- | --- | --- |
| Private source | Historical BriefcaseOS export never committed to public repo | Non-public staging and transformation only |
| Sanitizer and review | Raw private records; observed adversity classes | Strictly allowlisted, privacy-scanned, versioned Release Candidate, explicitly approved by owner |
| Source import | Approved versioned JSON / JSONL and adversarial labeled fixtures | Import Report; valid rows accepted idempotently, invalid isolated without leaking content |
| Provenance storage | Immutable Source Mention revisions, Source Record identity | No destructive overwrites, evidence preserved |
| Canonicalizer | High-confidence identity tiers and field decisions | One Canonical Posting for sufficiently proven identity; uncertain separate, flagged |
| PostgreSQL | Rails Active Record tables and constraints | Reliable, reproducible transitions and searchable approved state |
| API and docs | GET search/filter/rank/cursor/detail/provenance | Versioned public contract and clear error codes; no write routes |
| Browser playground | The very same public API | Accessible browse/search/inspect; no mock-only behavior presented as live |
| Optional SerpApi | Operator request through budgeted adapter | Normalized comparison report; does not auto-publish, mutate canonical state or spend without authorization |

## Release layers (do not conflate)

1. **Required core engineering gate:** Docker Compose Rails + PostgreSQL boots; importer and search behavior pass acceptance suite; fixture corpus and public provenance are safe; executable docs, playground and case study work. A verified local browser/API demo suffices if $0 live hosting is unavailable (Q18).
2. **Historical authenticity gate:** Real BriefcaseOS records may be included **only** when an actual available export is safely sanitized, checked, manually approved and accurately provenance-labeled. If unavailable, do not fabricate a historical corpus. Clearly labeled, harder adversarial examples can support a truthful demonstration in the meantime.
3. **Optional live deployment gate:** Investigate a $0 web runtime plus PostgreSQL that has acceptable persistence; verify actual quotas, cold-start behavior, schema migrations, connectivity and cost controls. No deployment is authorized by this plan. Avoid Render Free PostgreSQL as durable storage because its free DB expires after 30 days.
4. **Optional SerpApi comparison gate:** Only after core acceptance and when the owner supplies a key and explicitly authorizes a bounded live run. Failure or unavailable quota must not fail the required core.
5. **Communication gate:** Never send a follow-up to SerpApi automatically. Evidence-based note may be drafted after verification; owner explicitly approves any send.

## Approved workflow preferences

- **Live Grill presentation:** Compact, functional intelligent in-chat UI when supported. It can visualize decisions and models, but is not a source of truth.
- **Persistent living-model format:** **No separate diagram, Mermaid, DOT, canvas or generated image file.** Retain semantics in tables and structured prose in `PROJECT.md`.
- **Artifact contract:** Matt Pocock v1.3-compatible exact-case `GLOSSARY.md` (terms only), `PROJECT.md` (brief/decisions/current model), `ADR.md` (append-only decision history), `Ideas.md` (nonbinding), `SPEC.md` after discovery, ordered `tickets/PHR-###-*.md`.

## Assumptions and implementation-delegated choices

The spec pins deterministic **implementation defaults** for corpus schemas, matching evidence tiers, publication artifacts, field ranking, error contracts, cursors, and tests. These are implementation details consistent with the 20 accepted product decisions, not new user-approved features. Agents may optimize implementation internals without weakening observable requirements, and must record material design deviations in ADR before changing a release contract.

- **Source availability:** We have inspected the private BriefcaseOS importer contract, but have not independently verified a personal historical export ready for public release. Keep private material outside public source control; gate historical claims until actual export and owner review.
- **Provider accounts and hosting:** No confirmed owner-specific Hostinger VPS, Rails deployment service, Neon project, or SerpApi API key. Integrations are gated; no service purchase or deployment authorized.
- **Ruby experience:** This project is for learning Rails professionally. Don't claim existing paid Rails experience, benchmark performance, or production traffic in the case study.

## Authority and next step

Current explicit owner instruction supersedes `PROJECT.md` where materially different; `GLOSSARY.md` controls vocabulary, ADR records decisions, SPEC controls implementation behavior, and tickets govern incremental acceptance. `Ideas.md` is outside scope. The next authorized work in this turn is **the build pack only**. Implementation and deployment require separate instruction.
