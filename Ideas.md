# Phantom Rails — Ideas (non-binding)

These do not expand the agreed first-release scope and must not quietly become implementation requirements.

- Optional future provider adapters beyond the specifically requested, last-stage SerpApi integration.
- Direct, live mailbox synchronization or continuous job-board crawling; the agreed baseline is controlled fixture import from sanitized historic material.
- Multi-user job-search accounts, application tracking, or replacement of the full BriefcaseOS application.
- Broad public ingestion by arbitrary visitors, unless a later product decision explicitly justifies and secures it.
- **Name reserved elsewhere:** "Suplex Express" is a separate future branding idea, not an internal Phantom Rails class, endpoint, pipeline, or UI reference.
- Protected administrative ingestion endpoint, if a future release has an operational need beyond trusted versioned CLI/Rake imports; it is **not** part of the public first release.
- Human-in-the-loop review dashboard for uncertain posting matches or field conflicts; this may be unnecessary if the initial corpus can resolve ambiguity transparently through data contracts and import reports.
- Automated continuous feed ingestion and scheduled corpus refreshes; defer until the controlled, reproducible historical benchmark is demonstrably useful.
- Automatic merging of uncertain duplicates, including high-recall semantic or LLM-based similarity detection. Defer until there is a defensible evaluation set and explicit approval; the baseline is deterministic and conservative.
- General-purpose free-form query language, broad fuzzy matching, vector search and learned relevance ranking. The first release instead uses B-plus search with deterministic field-weighted relevance.
- Automatic publication from private historical imports without a separate human review gate. This is excluded from the approved baseline, not a planned convenience feature.

- Optional typo-tolerant search and more sophisticated matching/ranking after deterministic field-weighted relevance has a useful evaluation baseline.
- More elaborate event-sourced or fully append-only architecture, if the retained incremental-import history proves insufficient; not necessary for the first portfolio build.
- Paid VPS hosting or higher-tier availability and observability beyond the approved conditional $5/month planning boundary. Any expenditure still requires fresh authorization.
- Hostinger as a future eligible deployment only if the actual student plan includes a VPS or suitable Ruby/PostgreSQL capability; do not treat a standard shared hosting plan as compatible.

- Open-ended public SerpApi proxying or unauthenticated external-call triggers. Not part of the accepted manual comparison stretch.
- Ongoing periodic provider synchronization and freshness alerts. Separate later product decision, not a reason to delay the core.
- Performance benchmarking/load testing beyond the reproducible acceptance matrix; first release may record limited smoke metrics but should not claim sustained throughput.
- User accounts, paid tiers, subscriptions, collaborative corrections, or ownership/admin dashboards.
- Public promotional campaign or automatic follow-up emails to employers. Sharing any finished case study is a separately approved action.
- Production-grade search infrastructure (Elasticsearch, vectors, semantic reranking, fuzzy-typo engine) beyond explainable field-weighted deterministic Rails/PostgreSQL search.
- Hostinger student shared-host static mirror for docs/playground if later useful; does **not** replace the required Rails/PostgreSQL runtime and must be validated independently.
