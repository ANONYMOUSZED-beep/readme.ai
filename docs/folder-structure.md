# Folder Structure

Every top-level folder and its responsibility.

## Monorepo root

| Path | Responsibility |
| --- | --- |
| `apps/` | Deployable applications a user or operator runs directly |
| `apps/mobile/` | The Flutter client application |
| `apps/api/` | The FastAPI backend — synchronous orchestration & policy boundary |
| `services/` | Long-running, non-user-facing services |
| `services/workers/` | Asynchronous background processing (ingestion, analysis) — scaffolded, implemented in later sprints |
| `packages/` | Shared, cross-application contracts and assets (no business logic) |
| `packages/api-contracts/` | Single source of truth for request/response shapes shared by frontend and backend, preventing drift |
| `packages/prompts/` | Versioned LLM prompt templates treated as reviewed assets (later sprints) |
| `infra/` | Infrastructure: Dockerfiles, compose, and (later) IaC |
| `infra/docker/` | The development `docker-compose.yml` orchestrating the stack. Each app's own `Dockerfile` co-locates with the app (e.g. `apps/api/Dockerfile`) so its build context is self-contained |
| `docs/` | Architecture, ADRs, standards, and runbooks |
| `docs/adr/` | Architecture Decision Records — one file per significant decision |
| `tooling/` | Shared developer scripts and configuration not owned by a single app |

## `apps/mobile/lib` (Flutter — feature-first)

| Path | Responsibility |
| --- | --- |
| `core/` | Cross-cutting concerns: config, routing, theming, DI, error model, networking, logging. Depends on nothing in `features/` |
| `shared/` | Reusable widgets, formatters, and extensions used by 2+ features |
| `features/<feature>/` | A single feature, internally layered into `presentation/`, `domain/`, `data/` |
| `app.dart` / `main.dart` | Composition root — wires routing, theme, and providers |

A rule that prevents rot: anything used by two or more features moves up to
`shared/` or `core/`; features never import each other directly.

## `apps/api/app` (FastAPI — modular)

| Path | Responsibility |
| --- | --- |
| `core/` | Config, logging, error model, lifespan, and shared dependencies; no module-specific logic |
| `api/` | HTTP routing layer (versioned). Foundation sprint exposes only health & version |
| `modules/` | One folder per bounded capability (auth, books, reader, ...) — added in later sprints |
| `db/` | Database session/engine wiring (SQLAlchemy 2.x) and Alembic migration env |
| `main.py` | Application factory and composition root |
