# PHR-001 — Rails/PostgreSQL foundation

**Status:** Complete  
**Lane:** Core engineering / qualification  
**Dependencies:** None

## Goal

Create an API-first Rails repository with locked Ruby/Rails versions, containerized PostgreSQL, a clean local startup path, healthy development/test isolation and no live external accounts.

## Scope

- Rails 8.1.x, Ruby 3.4.x (validate and pin supported patches), PostgreSQL 16+ and Active Record everywhere; Dockerfile + compose.yaml, health checks and separate test database.
- - `.env.example`, ignored actual secrets, GitHub Actions skeleton, baseline code quality/test commands and README quick start.
- - No default SQLite database, Redis/Sidekiq, external API dependency or paid provisioner.

## Acceptance Criteria

- [x] Clean checkout boots Rails and PostgreSQL using the documented Compose commands.
- [x] `bin/rails db:prepare` and a baseline test succeed against PostgreSQL, including in CI.
- [x] Config/secrets inspection shows no personal credentials or private source records committed.
- [x] Static HTTP health path has no credentials and fails honestly if PG unavailable.

## Test / Evidence

- Record the executed commands, environment, actual results, and meaningful failure paths in `docs/release-evidence.md` (or ticket-local evidence linked from it).
- Do not mark complete solely because code or documentation exists; verify each applicable criterion against actual artifacts and the accepted `SPEC.md` contract.
- Every sample/fixture remains labeled by its true origin; historical release claims require the approved source and digest.

## Out of scope / safety

No undocumented product expansion, paid deployment, unapproved private historical data or public mutation endpoint. Stop and synchronize PROJECT/ADR/SPEC if a material conflict emerges.
