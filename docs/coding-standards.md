# Coding Standards

Conventions that keep a six-month, multi-engineer build coherent. CI and
pre-commit enforce the mechanical parts; this document covers intent.

## Universal principles

- **SOLID** and clean code. One class/module, one responsibility.
- **Dependency injection** everywhere — modules receive collaborators, they do
  not construct their own infrastructure.
- **Depend on contracts, not implementations.** This is what makes the AI layer
  and storage swappable.
- **No duplicated code, no temporary hacks, no unnecessary dependencies.**

## Naming

| Subject | Convention | Example |
| --- | --- | --- |
| Folders | lowercase, descriptive, feature-oriented | `reading_plan` |
| Dart files | `snake_case.dart` | `app_router.dart` |
| Dart classes | `PascalCase`, role-suffixed where useful | `AppRouter`, `AppException` |
| Python modules | `snake_case.py` | `config.py` |
| Python classes | `PascalCase` | `Settings`, `AppError` |
| Python functions/vars | `snake_case` | `get_settings` |
| Constants | `UPPER_SNAKE_CASE` | `DEFAULT_TIMEOUT` |
| Env variables | `UPPER_SNAKE_CASE`, prefixed by domain | `POSTGRES_HOST` |

## API naming

- Resource-oriented, named after domain concepts (`/books`, `/progress`), not
  implementations.
- Versioned under `/api/v1` once business endpoints exist. Foundation-only
  operational endpoints (`/health`, `/version`) are unversioned and stable.
- Request/response shapes live in `packages/api-contracts` as the single source
  of truth.

## Python specifics

- Target **Python 3.12**, **Pydantic v2**, **SQLAlchemy 2.x** (typed, `Mapped[]`).
- Formatted by **Black**, imports by **isort** (black profile), linted by **Ruff**,
  type-checked by **mypy** (strict-ish). Line length **88**.
- Public functions are fully type-annotated. No bare `except`.

## Dart / Flutter specifics

- Formatted by `dart format`; analyzed against `analysis_options.yaml`
  (flutter_lints + project rules).
- Feature-first; layered `presentation` / `domain` / `data` within a feature.
- Immutable models via **Freezed**; (de)serialization via **json_serializable**.
- State via **Riverpod**; navigation via **GoRouter**; HTTP via **Dio**.

## Error handling

- A single typed error taxonomy per side (`AppException` / `AppError`).
- Domain logic returns explicit results; exceptions are reserved for
  infrastructure/exceptional conditions.
- The client never shows stack traces and never loses reading position on error.

## Tests

- Pragmatic pyramid: heavy unit, focused integration on boundaries, thin E2E on
  the critical reading flow.
- The AI Service is faked in most tests so logic is deterministic.
- No merge without the relevant tests passing in CI.
