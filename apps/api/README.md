# ReadMe.ai — Backend (API)

FastAPI service that is the synchronous orchestration and policy boundary for
ReadMe.ai: authentication, the user's library, book processing (PDF, EPUB,
Markdown, plain text), the reader, and contextual explanations.

## Endpoints

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | none | Liveness — process is up (no dependency checks) |
| GET | `/health/ready` | none | Readiness — verifies dependencies (503 if degraded) |
| GET | `/version` | none | Service name, version, and environment |
| GET | `/api/v1/auth/me` | bearer | Current user (provisions on first use) |
| POST | `/api/v1/auth/logout` | bearer | Stateless logout acknowledgement |
| POST | `/api/v1/books` | bearer | Upload a book (multipart) → triggers processing |
| GET | `/api/v1/books` | bearer | List the user's books |
| GET | `/api/v1/books/{id}` | bearer | Get one owned book |
| DELETE | `/api/v1/books/{id}` | bearer | Delete an owned book + its file |
| GET | `/api/v1/books/{id}/content` | bearer | Readable content (from structured doc) |
| GET/PUT | `/api/v1/books/{id}/progress` | bearer | Get / save reading position |
| GET/POST | `/api/v1/books/{id}/bookmarks` | bearer | List / create bookmarks |
| DELETE | `/api/v1/books/{id}/bookmarks/{bid}` | bearer | Delete a bookmark |
| GET/POST | `/api/v1/books/{id}/processing` | bearer | Get status / re-run processing |
| POST | `/api/v1/books/{id}/explain` | bearer | Explain a word / sentence / passage |

Request and response schemas are browsable in the interactive docs at `/docs`
(OpenAPI at `/openapi.json`; both disabled in production).

## Supported book formats

| Format | Detected by | Notes |
| --- | --- | --- |
| PDF | `application/pdf` or `.pdf` | Text-based PDFs; lines are re-flowed into paragraphs. Scanned (image-only) and password-protected PDFs fail with a clear reason. |
| EPUB 2/3 | `application/epub+zip` or `.epub` | Spine reading order; headings become chapters/sections. DRM-protected books are rejected. |
| Markdown / text | `text/*` or `.txt`, `.md`, `.markdown`, `.text` | `#` starts a chapter, `##`–`######` a section. UTF-8/UTF-16 (BOM) and Windows-1252 are decoded. |

Uploads are processed immediately. The book's `status` becomes `READY` or
`FAILED` (see `GET .../processing` for `error_code` / `error_message`);
processing can be retried with `POST .../processing`. When a client sends no
content type (or `application/octet-stream`), it is inferred from the file
extension.

## Errors

Every error uses one envelope, and the `request_id` matches both the
`X-Request-ID` response header and the server's log lines:

```json
{"error": {"code": "not_found", "message": "Book not found.", "details": {}, "request_id": "…"}}
```

| Code | HTTP | Typical cause |
| --- | --- | --- |
| `validation_error` | 422 | Malformed request, empty upload, invalid selection anchors |
| `unauthorized` | 401 | Missing or invalid bearer token |
| `forbidden` | 403 | — |
| `not_found` | 404 | Unknown route, or a book that is not the caller's |
| `conflict` | 409 | Email already registered to a different identity |
| `payload_too_large` | 413 | Upload larger than `MAX_UPLOAD_SIZE_BYTES` (`details.max_bytes`) |
| `dependency_unavailable` | 503 | The explanation model is unreachable, slow, or returned nothing usable |
| `internal_error` | 500 | Unexpected failure (details are logged, never returned) |

## Layout

```
app/
├── main.py            # application factory + composition root
├── core/              # config, logging, errors, middleware, lifespan
│   └── storage/       # StorageService protocol + LocalStorageService + provider
├── api/               # routing layer (routes/ + router aggregation)
├── db/                # SQLAlchemy 2.x async engine/session + declarative base
├── modules/           # bounded business modules
│   ├── auth/          # identity: verifier, repository, service, routes
│   ├── library/       # books: models, repository, service, routes
│   ├── reader/        # content (from processing), progress, bookmarks
│   ├── processing/    # PDF/EPUB/text processors, document builder, persistence
│   ├── explanation/   # selection classifier, strategies, Ollama provider
│   └── learning/      # Learning Intelligence Engine + capabilities
├── prompts/           # versioned LLM prompt templates
└── schemas/           # shared Pydantic models
migrations/            # Alembic environment + versions
tests/                 # pytest suite
```

## Local commands

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[dev]"

alembic upgrade head                                # create/upgrade the schema
uvicorn app.main:app --reload --port 8000           # run

ruff check . && black --check . && isort --check-only . && mypy app && pytest
```

Configuration is environment-driven; see the root `.env.example`. Setting
`DEV_AUTH=true` accepts the fixed bearer token `development-token` as a mock
user for local work; the service refuses to start with it (or without
`FIREBASE_PROJECT_ID`) when `APP_ENV=production`.

## Database migrations

Schema changes are Alembic migrations in `migrations/versions/`. CI applies
them to PostgreSQL, runs `alembic check` (models and migrations must agree),
and verifies a full downgrade/upgrade cycle.

The Docker image runs `alembic upgrade head` before starting when
`RUN_MIGRATIONS=true` (the compose stack sets it). For deployments with more
than one replica, leave it unset and run migrations as a release step.
