# ReadMe.ai — Complete Project Record

> **Authoritative engineering record.** This document reflects the current,
> actually-implemented state of the ReadMe.ai codebase. It is written for future
> engineers joining the project. Where a feature is designed but not built, it is
> marked as planned rather than implemented.
>
> **Legend:** ✅ Implemented · 🚧 Partial / Scaffolded · 📅 Planned (not built)
>
> **Document version:** generated at Sprint 5.0 + Development Authentication Mode.

---

## 1. Executive Summary

**Project vision.** ReadMe.ai is an AI reading companion whose purpose is to help
people *understand* books rather than merely read or summarize them. It removes
confusion at the exact moment it appears — unfamiliar vocabulary, difficult
sentences, dense concepts, missing prerequisites — without ever replacing the act
of reading.

**Problem statement.** Conventional reading tools either leave the reader alone
with difficult material or replace reading with summaries. Neither builds genuine
understanding. Summaries skip the material; unaided reading stalls on confusion.
ReadMe.ai targets the middle ground: keep the reader reading, and resolve
confusion in place.

**Current MVP status.** The application runs end-to-end in Development Mode:
a reader authenticates, uploads a text book, the book is parsed into a structured
internal document, and the reader can request word, sentence, and paragraph
explanations backed by a local LLM (Ollama). A Learning Intelligence Engine layer
adds learner-aware prerequisites. The backend is a modular FastAPI service with a
PostgreSQL system of record; the client is a Flutter application.

**What is not yet built.** There is no PDF/EPUB/DOCX/OCR parsing (only plain-text
and Markdown), no vector database usage or retrieval-augmented generation, no
cloud model, no cloud object storage, and no asynchronous worker tier. These are
designed extension points, not working features.

**Overall completion (estimate).** The engineering foundation and the core
reading + explanation loop are complete and demonstrable. Against the full product
vision (rich formats, retrieval, adaptive learning, scale), the project is
approximately **60% of MVP scope** and a smaller fraction of the long-term
research vision. Section 22 breaks this down.

---

## 2. Project Philosophy

These principles are enforced by the architecture and the code review process, not
just stated aspirationally.

1. **Reading comes first.** The reading experience is the product. Every other
   feature is subordinate to preserving reading flow.
2. **AI should never interrupt.** The architecture separates a fast synchronous
   reader path from slower AI/processing work so that the reader is not blocked
   waiting on a model. The reader never calls a model directly.
3. **Understanding over summarization.** Explanations are contextual and scoped to
   a selection; the product resolves confusion rather than replacing the text.
4. **The reader remains in control.** The backend classifies a selection and
   chooses the explanation strategy; the reader is never forced into a chat or a
   mode they did not ask for. Position and annotations belong to the reader.
5. **Structured documents, never raw files.** Every book becomes a structured
   internal document (Chapter → Section → Paragraph → Sentence) addressed by
   stable anchors. No feature operates on raw PDFs or page numbers.
6. **Learn about the learner, then help.** The Learning Intelligence Engine is a
   dedicated place for learner-aware decisions, kept separate from explanation
   generation so educational intelligence can grow without bloating other modules.
7. **Quarantine volatile dependencies behind stable contracts.** Model access,
   storage, token verification, and processors each sit behind an interface, so
   the concrete implementation (Ollama → cloud, local disk → R2, plain-text →
   PDF) can change as configuration, not rewrites.
8. **All derived data is rebuildable** from the source file plus versioned logic.

---

## 3. Architecture Overview

ReadMe.ai is a monorepo split into a Flutter client and a FastAPI backend, with a
PostgreSQL system of record and a local LLM for explanations.

### Component responsibilities

| Component | Status | Responsibility |
| --- | --- | --- |
| Frontend (Flutter) | ✅ | Reading client; feature-first, thin on logic; never blocks reading on the network |
| Backend (FastAPI) | ✅ | Synchronous orchestration, authorization boundary, input validation |
| Database (PostgreSQL) | ✅ | System of record; users, books, reading state, structured documents |
| Storage | ✅ Local · 📅 Cloud | Uploaded book files behind a `StorageService` contract (local filesystem today) |
| Book Processing Engine | ✅ Text only | Converts uploads into a structured internal document with stable anchors |
| Explanation Engine | ✅ | Classifies a selection and generates a scoped explanation via a strategy + provider |
| Learning Intelligence Engine | ✅ Foundation | Learner-aware layer above explanations; runs pluggable capabilities |
| AI Layer (Ollama) | ✅ Local | Inference behind a provider contract; local `llama3.2` today |
| Authentication | ✅ | Firebase identity, stateless JWT verification; internal user keyed by UID |
| Vector DB (Qdrant) | 🚧 Provisioned | Present in the dev compose file; no code uses it yet |
| Workers | 📅 Scaffolded | `services/workers` exists as a folder; no worker is implemented |

### High-level diagram

```
┌────────────────────────────────────────────────────────────────┐
│                     Flutter Client (apps/mobile)                 │
│  Splash → Auth → Library → Reader → Explanation Sheet            │
│  Riverpod (state + DI) · GoRouter · Dio · Freezed                │
└───────────────┬────────────────────────────────────────────────┘
                │  HTTPS + Bearer token (Firebase ID token, or dev token)
                ▼
┌────────────────────────────────────────────────────────────────┐
│                    FastAPI Backend (apps/api)                    │
│                                                                  │
│  /health /version         (operational, unversioned)            │
│  /api/v1/auth             Auth (Firebase JWT / dev verifier)     │
│  /api/v1/books            Library (upload, list, get, delete)    │
│  /api/v1/books/{id}       Reader (content, progress, bookmarks)  │
│  /api/v1/books/{id}       Processing (status, reprocess)         │
│  /api/v1/books/{id}/explain                                      │
│        │                                                         │
│        ▼                                                         │
│  Learning Intelligence Engine ── capability pipeline             │
│        │                                                         │
│        ▼                                                         │
│  Explanation Service → Classifier → Strategy → Provider ──► Ollama│
│                                                                  │
│  Storage (local)   Processing pipeline (plain-text → structure)  │
└───────────────┬───────────────────────────────┬─────────────────┘
                ▼                                 ▼
        ┌──────────────┐                  ┌──────────────┐
        │  PostgreSQL  │                  │    Ollama    │
        │  (records)   │                  │  (llama3.2)  │
        └──────────────┘                  └──────────────┘
        Qdrant (provisioned, unused) · Local filesystem (book files)
```

---

## 4. Technology Stack

### Backend (`apps/api`)

| Technology | Version constraint | Role | Status |
| --- | --- | --- | --- |
| Python | 3.12+ | Language | ✅ |
| FastAPI | 0.115–<1.0 | HTTP framework | ✅ |
| Uvicorn | 0.32+ | ASGI server | ✅ |
| Pydantic / pydantic-settings | 2.9+ | Validation & config | ✅ |
| SQLAlchemy (asyncio) | 2.0.36+ | ORM (typed `Mapped[]`) | ✅ |
| asyncpg | 0.30+ | PostgreSQL async driver | ✅ |
| Alembic | 1.14+ | Database migrations | ✅ |
| PyJWT[crypto] | 2.9+ | Firebase ID token verification | ✅ |
| httpx | 0.27+ | Outbound HTTP (Ollama, Google certs) | ✅ |
| python-multipart | 0.0.12+ | Multipart upload parsing | ✅ |

### Frontend (`apps/mobile`)

| Technology | Version | Role | Status |
| --- | --- | --- | --- |
| Flutter | 3.41.2 (Dart 3.11+) | Client SDK | ✅ |
| flutter_riverpod | 3.x | State management + DI | ✅ |
| go_router | 17.x | Declarative navigation | ✅ |
| dio | 5.x | HTTP client | ✅ |
| freezed / freezed_annotation | 3.x | Immutable models | ✅ |
| json_serializable / json_annotation | 6.x / 4.x | (De)serialization | ✅ |
| firebase_auth / firebase_core | 6.x / 4.x | Identity provider | ✅ |
| google_sign_in | 7.x | Google Sign-In flow | ✅ |
| file_picker | 11.x | Book file selection | ✅ |
| intl + flutter_localizations | 0.20.2 | Localization (l10n, `app_en.arb`) | ✅ |

### Datastores, AI, and infrastructure

| Technology | Role | Status |
| --- | --- | --- |
| PostgreSQL | System of record (16 in Docker compose; 18 used in local dev) | ✅ |
| Qdrant | Vector DB — present in compose, not referenced by code | 🚧 Provisioned |
| Ollama (`llama3.2`) | Local LLM for explanations | ✅ |
| Firebase Authentication | Identity provider (production auth path) | ✅ |
| Cloudflare R2 | Cloud object storage | 📅 Planned |
| Docker + Docker Compose | Local stack (api, postgres, qdrant) | ✅ |

### Quality tooling & CI/CD

| Tool | Role | Status |
| --- | --- | --- |
| Ruff | Python lint | ✅ |
| Black | Python format (line length 88) | ✅ |
| isort | Python import ordering (black profile) | ✅ |
| mypy | Python static typing (strict) | ✅ |
| pytest + pytest-asyncio + aiosqlite | Backend tests | ✅ |
| dart format / flutter analyze / flutter_test | Frontend quality & tests | ✅ |
| pre-commit | Local git hooks | ✅ |
| GitHub Actions | Path-scoped `backend-ci` and `frontend-ci` workflows | ✅ |

---

## 5. Folder Structure

### Monorepo root

| Path | Responsibility | Status |
| --- | --- | --- |
| `apps/mobile/` | Flutter client application | ✅ |
| `apps/api/` | FastAPI backend — synchronous orchestration & policy boundary | ✅ |
| `services/workers/` | Asynchronous background processing | 📅 Scaffolded folder only |
| `packages/api-contracts/` | Shared FE/BE request/response shapes | 🚧 Placeholder |
| `packages/prompts/` | Versioned LLM prompt assets | 🚧 Placeholder (prompts currently live in the backend) |
| `infra/docker/` | Dev `docker-compose.yml`; each app carries its own `Dockerfile` | ✅ |
| `docs/` | Architecture, ADRs, standards, runbooks | ✅ |
| `docs/adr/` | Architecture Decision Records (one per decision) | ✅ |
| `tooling/` | Shared developer scripts/config | 🚧 Minimal |

### Backend `apps/api/app`

| Path | Responsibility |
| --- | --- |
| `core/` | Config, logging, error model, lifespan, middleware, storage abstraction |
| `core/storage/` | `StorageService` protocol + `LocalStorageService` + provider |
| `api/` | Top-level router aggregation; `api/routes/system.py` (health/version) |
| `db/` | SQLAlchemy async engine/session (`session.py`) and declarative `base.py` |
| `modules/auth/` | Firebase/dev token verification, user provisioning, `/auth` routes |
| `modules/library/` | Book upload, listing, deletion; `Book` model + status |
| `modules/reader/` | Readable content, reading progress, bookmarks |
| `modules/processing/` | Processing pipeline, structured document model, processors |
| `modules/explanation/` | Selection classifier, strategies, prompt context, Ollama provider |
| `modules/learning/` | Learning Intelligence Engine, capability registry, capabilities |
| `prompts/` | Word / sentence / paragraph prompt templates |
| `schemas/` | Cross-cutting response schemas (system) |
| `main.py` | Application factory & composition root |
| `migrations/` | Alembic environment and versioned migrations |
| `tests/` | Backend test suite (pytest) |

### Frontend `apps/mobile/lib`

| Path | Responsibility |
| --- | --- |
| `core/config/` | `AppConfig` / `AppEnvironment` (dart-defines: API base URL, DEV_AUTH) |
| `core/network/` | Dio client, auth interceptor, error mapper, logging interceptor |
| `core/router/` | GoRouter setup and route definitions |
| `core/theme/` | Colors, theme, theme-mode controller |
| `core/firebase/` | Firebase bootstrap |
| `core/error/` | `AppException` / `Failure` typed error model |
| `core/files/` | File picker service and picked-book model |
| `core/logging/` | App logger |
| `features/auth/` | Login, auth repositories (Firebase + Development), auth state |
| `features/library/` | Library screen, book detail, upload, library controller |
| `features/reader/` | Reader screen, reading settings, progress, bookmarks, selection |
| `features/explanation/` | Explanation sheet and explanation data/domain |
| `features/home/` | Home/shell presentation |
| `shared/formatters/` | Reusable formatters (e.g. byte formatter) |
| `l10n/` | ARB source and generated localizations |
| `app.dart` / `main.dart` | Composition root — routing, theme, providers |

---

## 6. Sprint History

Sprint dating follows the ADRs and repository documentation. Acceptance status
reflects the current, verified state of the code.

### Sprint 0.1 — Architecture Blueprint
- **Objective:** Establish the target system design, entity model, scalability
  stages, and risk register before writing product code.
- **Implemented:** `docs/architecture-overview.md` (system design, module map,
  key principles). No product code.
- **Key decisions:** Separate synchronous reader path from asynchronous
  processing; quarantine model access; anchor to stable offsets; all derived data
  rebuildable.
- **Acceptance:** ✅ Blueprint documented.
- **Lessons:** Writing the mission constraint (preserve reading flow) first made
  later structural decisions (sync vs async) fall out naturally.

### Sprint 0.2 — Engineering Foundation
- **Objective:** Stand up the monorepo, the FastAPI skeleton (health/version),
  the Flutter skeleton, tooling, and CI.
- **Implemented:** Monorepo layout; FastAPI app factory, config, logging,
  middleware, error envelope; health/version endpoints; Flutter feature-first
  scaffold; pre-commit and path-scoped CI.
- **Key decisions:** ADR 0001 (monorepo), ADR 0002 (Flutter feature-first +
  Riverpod + GoRouter), ADR 0003 (AI service abstraction, forward-looking).
- **Acceptance:** ✅ Both apps build; CI green.
- **Lessons:** Standardizing one state/DI solution (Riverpod) early avoided the
  common failure of mixing libraries.

### Sprint 1.0 — Authentication
- **Objective:** Secure identity with Firebase, stateless verification, internal
  user model.
- **Implemented:** `TokenVerifier` protocol + `FirebaseTokenVerifier` (RS256
  against Google certs, cached); just-in-time user provisioning; `/api/v1/auth/me`
  and `/logout`; Flutter `AuthRepository` hiding Firebase from the app layers.
- **Key decisions:** ADR 0004 (internal UUID keyed by `firebase_uid`; stateless
  per-request verification; PyJWT over full firebase-admin; config via
  dart-define).
- **Acceptance:** ✅ Verified on every request; tests inject a fake verifier.
- **Lessons:** Keeping identity behind a contract made the later development-auth
  mode a drop-in verifier rather than a security carve-out.

### Sprint 2.0 — Library Foundation
- **Objective:** Upload, list, get, and delete books with file persistence.
- **Implemented:** `Book` model + `BookStatus`; multipart upload with size/empty
  validation; ownership-enforced CRUD; `StorageService` protocol +
  `LocalStorageService` (path-traversal-safe, threaded I/O).
- **Key decisions:** ADR 0005 (storage abstraction; DB stores only a
  `storage_key`; per-user key namespacing).
- **Acceptance:** ✅ Upload→list→get→delete verified; ownership returns 404 for
  non-owned books.
- **Lessons:** Storing keys, not bytes, kept the database clean and the cloud
  migration a provider change.

### Sprint 3.0 — Reader Foundation
- **Objective:** A premium reading experience over uploaded files with no parsing
  or AI.
- **Implemented:** `BookContentExtractor` seam + `PlainTextContentExtractor`;
  reading progress and bookmarks anchored by stable offsets; Flutter reader with
  adjustable font/spacing, `FutureProvider.family` reads and a `ReaderController`
  for mutations. (The content extractor was later superseded by the processing
  engine — see 3.5.)
- **Key decisions:** ADR 0006 (content behind a seam; stable anchors not page
  numbers; storage gains `read`).
- **Acceptance:** ✅ Reflowable reading for text; non-text reported as
  unsupported.
- **Lessons:** Anchoring position to offsets meant font/layout changes never lose
  the reader's place.

### Sprint 3.5 — Book Processing Engine
- **Objective:** Convert uploads into a structured internal document powering the
  reader and future features.
- **Implemented:** `BookProcessor` protocol + `ProcessorRegistry`;
  `PlainTextProcessor`; structured model (ProcessedBook → Chapter → Section →
  Paragraph → Sentence) with text stored once and deterministic anchors;
  `ProcessingTrigger` seam (inline today); structured failure codes; reader now
  consumes reconstructed structured text.
- **Key decisions:** ADR 0007 (processor registry; store text once; denormalised
  `processed_book_id` for single-query reconstruction; trigger seam for future
  workers).
- **Acceptance:** ✅ Text books structured and readable; other formats recorded as
  `unsupported_format`.
- **Lessons:** A denormalised parent id plus global paragraph ordering made
  large-book reconstruction a single indexed query.

### Sprint 4.1 — Word Explanation
- **Objective:** First AI feature — explain a selected word via Ollama.
- **Implemented:** A `POST /explain/word` endpoint backed by an Ollama provider
  behind a contract. **Superseded by Sprint 4.2** (the dedicated word endpoint no
  longer exists).
- **Key decisions:** Reader never calls the model directly; provider quarantined
  per ADR 0003.
- **Acceptance:** ✅ At the time; replaced by the unified endpoint.
- **Lessons:** Selection-scoped explanation generalized cleanly to sentences and
  paragraphs, motivating the Strategy refactor.

### Sprint 4.2 — Unified Explanation (Word / Sentence / Paragraph)
- **Objective:** One explanation endpoint that classifies the selection and
  chooses a strategy; the client never picks a mode.
- **Implemented:** `SelectionClassifier` (uses the structured document);
  Strategy pattern (`word`, `sentence`, `paragraph` strategies); prompt templates
  with per-type length bounds; `ContextExtractor`; `OllamaExplanationProvider`
  with structured error codes; `POST /api/v1/books/{id}/explain`.
- **Key decisions:** Backend-side classification from structure (not character
  counts alone); provider errors surface as `503 dependency_unavailable`.
- **Acceptance:** ✅ Word/sentence/paragraph classified and explained; provider
  failure returns a retryable 503.
- **Lessons:** Grounding the classifier in the structured document made selection
  typing robust across book sizes.

### Sprint 5.0 — Learning Intelligence Engine (LIE)
- **Objective:** A learner-aware layer above explanations, extensible without
  touching the reader or the explanation service.
- **Implemented:** `LearningIntelligenceEngine`, `CapabilityRegistry`,
  `LearningCapability` protocol, and a deterministic `PrerequisiteCapability`
  (configurable dependency map). The explanation endpoint now delegates to the
  engine; the response gained an optional `prerequisites` field.
- **Key decisions:** ADR 0008 (LIE above the Explanation Service; pluggable
  capabilities via a registry; a failing capability is caught and skipped).
- **Acceptance:** ✅ Prerequisites returned for known terms; empty list otherwise;
  endpoint contract otherwise unchanged.
- **Lessons:** Aggregating capability outcomes and merging into the response kept
  the engine free of feature-specific logic.

### Development Authentication Mode
- **Objective:** A local/demo tool that bypasses Firebase and auto-logs-in a mock
  user, with production untouched.
- **Implemented:** `DEV_AUTH` config (backend + client); backend
  `DevelopmentTokenVerifier` accepts a fixed `development-token` as a deterministic
  mock user; client `DevelopmentAuthRepository` auto-authenticates and shows a
  "Dev Mode" banner; verifier selection lives in one place.
- **Key decisions:** Reuse the existing `TokenVerifier` / `AuthRepository`
  abstractions rather than disabling auth; never weaken production JWT
  verification.
- **Acceptance:** ✅ Dev token accepted only when `DEV_AUTH=true`; rejected when
  false; production path unchanged; logout returns to mock login state.
- **Lessons:** Because auth was already behind a contract, dev mode required no
  changes to business modules.

---

## 7. Current Features

### Authentication
- **Firebase identity + stateless verification** ✅ — Every protected request
  validates a Firebase ID token (issuer, audience, expiry, RS256 signature against
  cached Google certs). Internal user provisioned just-in-time, keyed by
  `firebase_uid`.
- **Development authentication mode** ✅ — When `DEV_AUTH=true`, a fixed
  `development-token` authenticates a deterministic mock user.
- **Limitations:** Revocation is bounded by token lifetime (no server-side session
  store). Real Google Sign-In requires the team's Firebase project and OAuth
  setup.

### Library
- **Upload / list / get / delete** ✅ — Multipart upload with empty-file and
  max-size validation; listing newest-first; ownership enforced (non-owned →
  404). Files persisted via local storage; DB stores only a `storage_key`.
- **Limitations:** Only local filesystem storage; no cloud backend; no
  cover-image or rich metadata extraction; `Book.status` remains `UPLOADED` after
  upload (processing state is tracked separately in `ProcessedBook`).

### Reader
- **Readable content, reading progress, bookmarks** ✅ — Content is reconstructed
  from the structured document; progress and bookmarks are stored against stable
  anchors (character offsets), independent of font/layout. Client supports
  adjustable font size, spacing, and dark mode.
- **Limitations:** Only `COMPLETED`, text-derived books render as `text`; others
  report `unsupported`. The anchor↔scroll mapping is proportional/approximate.

### Processing
- **Structured document pipeline** ✅ — Upload triggers processing (inline);
  `PlainTextProcessor` derives Chapter/Section/Paragraph/Sentence structure from
  `#`/`##` headings, blank-line blocks, and terminal punctuation. Metadata (word
  count, character count, estimated reading minutes) extracted. Status endpoint
  and idempotent reprocess endpoint.
- **Limitations:** Only plain-text / Markdown. PDF, EPUB, DOCX, and OCR are
  documented extension points, not implemented — such files are recorded as
  `unsupported_format`.

### Explanation
- **Unified selection explanation** ✅ — One endpoint classifies a selection as
  word/sentence/paragraph using the structured document, chooses a strategy,
  renders a bounded prompt, and generates an explanation via Ollama. Word
  selections additionally return `meaning` and `example`.
- **Limitations:** Depends on a running Ollama with the configured model; provider
  failures return a retryable `503`. Explanations are generated on demand (no
  pre-computation/caching yet). Small local models can produce occasional
  inaccuracies.

### Learning Intelligence Engine
- **Prerequisite detection** ✅ — A deterministic capability returns prerequisite
  concepts for known terms (configurable dependency map). The engine runs
  registered capabilities, aggregates outcomes, and merges `prerequisites` into
  the explanation response.
- **Limitations:** One capability implemented; the dependency map is small and
  hand-curated (not AI-derived, not book-specific). No learner profile, memory,
  confidence, or recommendations yet.

### Developer Tools
- **Development Mode** ✅ — Backend dev verifier + client dev repository + "Dev
  Mode" banner, toggled by `DEV_AUTH`.
- **Docker compose dev stack** ✅ — api + postgres + qdrant.
- **Quality gates & CI** ✅ — ruff/black/isort/mypy/pytest; dart
  format/analyze/test; path-scoped GitHub Actions; pre-commit hooks.

---

## 8. API Summary

Base URL (local): `http://localhost:8000`. All product endpoints require a bearer
token and enforce per-user ownership (a non-owned or unknown book returns 404).
All errors use a single envelope: `{ "error": { code, message, details,
request_id } }`.

### Operational (unversioned)
| Method | Path | Auth | Purpose | Response |
| --- | --- | --- | --- | --- |
| GET | `/health` | none | Liveness | `{status: ok}` |
| GET | `/health/ready` | none | Readiness (checks dependencies; 503 if degraded) | `{status, dependencies[]}` |
| GET | `/version` | none | Service name/version/environment | `{name, version, environment}` |

### Authentication — `/api/v1/auth`
| Method | Path | Auth | Purpose | Request | Response |
| --- | --- | --- | --- | --- | --- |
| GET | `/me` | required | Return authenticated user (provisioned on first use) | — | User object |
| POST | `/logout` | required | Stateless logout acknowledgement | — | `{detail}` |

### Library — `/api/v1/books`
| Method | Path | Auth | Purpose | Request | Response |
| --- | --- | --- | --- | --- | --- |
| POST | `` | required | Upload a book & create its record | multipart: `file`, optional `title` | 201 Book |
| GET | `` | required | List caller's books, newest first | — | `{items[], total}` |
| GET | `/{book_id}` | required | Get one owned book | — | Book / 404 |
| DELETE | `/{book_id}` | required | Delete owned book + file | — | 204 / 404 |

### Reader — `/api/v1/books/{book_id}`
| Method | Path | Auth | Purpose | Request | Response |
| --- | --- | --- | --- | --- | --- |
| GET | `/content` | required | Readable reconstructed content | — | `{book_id, title, format, content, character_count}` |
| GET | `/progress` | required | Saved reading progress | — | Progress / null |
| PUT | `/progress` | required | Create/update position (adds reading time) | `{current_position, progress_percentage, reading_time_seconds}` | Progress |
| GET | `/bookmarks` | required | List bookmarks | — | `{items[], total}` |
| POST | `/bookmarks` | required | Create bookmark | `{anchor, label?}` | 201 Bookmark |
| DELETE | `/bookmarks/{bookmark_id}` | required | Delete bookmark | — | 204 |

### Processing — `/api/v1/books/{book_id}`
| Method | Path | Auth | Purpose | Response |
| --- | --- | --- | --- | --- |
| GET | `/processing` | required | Processing status + extracted metadata | Status object / 404 |
| POST | `/processing` | required | Re-run processing (idempotent) | Status object |

### Explanation — `/api/v1/books/{book_id}`
| Method | Path | Auth | Purpose | Request | Response |
| --- | --- | --- | --- | --- | --- |
| POST | `/explain` | required | Explain a selection (LIE → Explanation Service → Ollama) | `{anchor, end_anchor?, selected_text}` | `{selection_type, explanation, meaning?, example?, prerequisites[]}` |

Explanation error cases: `401` unauthenticated, `404` unknown/unowned/unprocessed,
`422` selection outside content, `503 dependency_unavailable` on model
timeout/unsupported model/invalid or empty response/provider unavailable.

---

## 9. Database Schema

The schema is managed by Alembic. Four migrations exist: `0001` users, `0002`
books, `0003` reader tables, `0004` processing tables. All primary keys are UUIDs;
timestamps are timezone-aware. Foreign keys cascade on delete.

| Table | Purpose | Key relationships |
| --- | --- | --- |
| `users` | Internal user record keyed to a Firebase identity | `id` (PK); unique `firebase_uid`, unique `email` |
| `books` | Uploaded book metadata (bytes live in storage) | `user_id` → `users.id` (CASCADE); unique `storage_key` |
| `reading_progress` | One reading position per user+book (stable anchor) | `user_id`, `book_id`; unique (`user_id`,`book_id`) |
| `bookmarks` | Saved positions anchored by stable anchor | `user_id`, `book_id` |
| `processed_books` | Document-level processing record + metadata + status | `book_id` → `books.id` (CASCADE), unique |
| `processed_chapters` | Chapters of a processed document | `processed_book_id` → `processed_books.id` |
| `processed_sections` | Sections within a chapter | `processed_book_id`, `chapter_id` |
| `processed_paragraphs` | Paragraphs — **the only rows storing text** | `processed_book_id`, `section_id` |
| `processed_sentences` | Sentences addressed only by offsets (text derived) | `processed_book_id`, `paragraph_id` |
| `alembic_version` | Migration bookkeeping | — |

**Relationship notes.**
- `users` is the root; deleting a user cascades to books, progress, bookmarks, and
  processed content.
- The structured document hierarchy is normalised (Chapter → Section → Paragraph →
  Sentence). Every structural row **also** carries a denormalised
  `processed_book_id` so the reader reconstructs a document with a single indexed,
  ordered query over paragraphs rather than walking the hierarchy.
- Canonical text is stored exactly once, on `processed_paragraphs.text`. Sentences,
  sections, and chapters store only `start_offset` / `end_offset` into the
  canonical text; their text is derived by slicing.
- `books.status` (library lifecycle) and `processed_books.status` (processing
  lifecycle) are intentionally separate. Processing does not mutate `books.status`.

---

## 10. Learning Intelligence Engine (LIE)

**Purpose.** Provide one place for learner-aware decisions that sit *above*
explanation generation, so educational intelligence can grow (prerequisites,
confidence, memory, recommendations, revision) without bloating the Explanation
Service or leaking into the reader.

**Architecture.**
```
Reader → Explanation API → LIE → Capability Pipeline → Explanation Service → Provider
```
The explanation router delegates to the engine. The engine runs registered
capabilities, aggregates their outcomes, delegates explanation generation to the
Explanation Service, then merges the aggregated outcome (currently
`prerequisites`) into the response.

**Capability system.** A `LearningCapability` is a protocol with a stable `name`
and an async `evaluate(context) -> CapabilityOutcome`. Capabilities are registered
in a `CapabilityRegistry` at a single composition point
(`get_capability_registry`). The engine never imports concrete capabilities.
A capability that raises is caught and skipped — it can never break an
explanation.

**Implemented capabilities.**
- ✅ `PrerequisiteCapability` — deterministic. Scans the selection for known terms
  (word-boundary match) against a configurable dependency map and returns
  prerequisite concepts with reasons. Deduplicated across capabilities.

**Future capabilities (📅 planned, not built).** Confidence estimation, spaced
memory/revision, personalized recommendations, and an AI-powered prerequisite
capability. Each would be added by implementing the protocol and registering it —
no engine change.

**Decision pipeline (current).**
1. Build a `CapabilityContext` (`user_id`, `book_id`, `selected_text`).
2. Run each registered capability; collect and deduplicate prerequisites.
3. Delegate to the Explanation Service to generate the explanation.
4. Merge prerequisites into the `ExplanationResponse`.

---

## 11. Book Processing Engine

**Purpose.** Turn every uploaded book into a structured internal document so all
features address structure and stable anchors, never raw files or page numbers.
Strictly non-AI.

**Pipeline.**
```
Upload → Storage → ProcessingTrigger.schedule → ProcessingService.process_book
  → ProcessorRegistry.select → processor.process → persist structure → status
```
Today an `InlineProcessingTrigger` runs synchronously in the upload request; a
`QueuedProcessingTrigger` can enqueue for a worker later with no change at the
call site.

**Processor registry.** A `BookProcessor` protocol (`supports`, `process`) with a
`ProcessorRegistry` that selects by MIME type / extension. Only
`PlainTextProcessor` is implemented. PDF/EPUB/DOCX/OCR are documented extension
points — adding one is registering a class; nothing else changes.

**Structured document model.** ProcessedBook → Chapter → Section → Paragraph →
Sentence. Text is stored once on Paragraph; other levels carry offsets into the
canonical text.

**Stable anchors.** Deterministic and stable across reprocessing of identical
structure: `ch1`, `ch1-sec2`, `ch1-sec2-p3`, `ch1-sec2-p3-s1`.

**Processing status.** `QUEUED → PROCESSING → COMPLETED` on success, or `→ FAILED`
with a structured `error_code` (`unsupported_format`, `malformed_file`,
`empty_document`, `too_large`, `timeout`, `internal_error`). Only `COMPLETED`
books are served by the reader. Failures never break the upload.

---

## 12. Explanation Engine

**Selection classifier.** `SelectionClassifier` consults the structured document
(not arbitrary character counts). It finds paragraphs overlapping the selection's
offset range: more than one paragraph → `PARAGRAPH`; otherwise it counts
overlapping sentences and words to decide `WORD` vs `SENTENCE` vs `PARAGRAPH`. It
also returns the intersecting paragraph text as grounding context. Selections
outside the content raise `422`; unprocessed books raise `404`.

**Strategy pattern.** Each selection type maps to an `ExplanationStrategy`
(`word`, `sentence`, `paragraph`). The service picks the strategy from the
classification; the client never chooses a mode.

**Prompt templates.** Per-type templates live in `app/prompts/` and carry explicit
length constraints (word ≤3, sentence ≤5, paragraph ≤7 sentences). A
`ContextExtractor` bounds and centres the surrounding context around the
selection.

**Provider architecture.** `ExplanationProvider` is a protocol;
`OllamaExplanationProvider` is the only implementation. It calls Ollama's
`/api/generate` with `format=json`, parses `meaning`/`explanation`/`example`, and
raises structured `ExplanationError`s (`timeout`, `unsupported_model`,
`invalid_response`, `unavailable`). The service converts these to a `503
dependency_unavailable` with a `reason`. The reader never touches the provider.

**Current capabilities.** Word, sentence, and paragraph explanations generated on
demand via a local model, with prerequisites merged in by the LIE.

---

## 13. Development Mode

**Why it exists.** A local development and demonstration tool that removes the
Firebase/Google Sign-In dependency so the full app can run on an emulator or a
demo machine without real credentials. It is not a product feature and must never
be enabled in production.

**How it works.**
- **Backend:** with `DEV_AUTH=true`, `get_token_verifier` returns a
  `DevelopmentTokenVerifier` that accepts exactly the fixed bearer token
  `development-token` and resolves it to a deterministic mock user
  (`geo.dev@readme.ai`, "Geo (Development)", uid `development-user`). Production
  Firebase verification is otherwise unchanged.
- **Frontend:** with `DEV_AUTH=true`, `authRepositoryProvider` returns a
  `DevelopmentAuthRepository` that auto-authenticates the mock user; the app skips
  Google Sign-In, navigates to the Library, and shows a "Dev Mode" banner. The
  client sends `Authorization: Bearer development-token`.

**How to enable.** Set `DEV_AUTH=true` in `apps/api/.env` and pass matching
dart-defines to the client: `--dart-define=DEV_AUTH=true
--dart-define=API_BASE_URL=http://10.0.2.2:8000` (the emulator reaches the host
backend via `10.0.2.2`).

**How to disable.** Set `DEV_AUTH=false` (the default) everywhere. Firebase
authentication and production JWT verification are fully restored, unchanged.

**Production safety.** The dev token is accepted only when `DEV_AUTH=true`;
rejected otherwise. The mock user path never weakens production security, and the
selection logic is confined to one provider function per side.

---

## 14. Testing

**Backend (pytest + pytest-asyncio):** 67 tests across
`test_system`, `test_auth`, `test_dev_auth`, `test_library`, `test_storage`,
`test_reader`, `test_processing_unit`, `test_processing_api`, `test_explanation`,
`test_learning`. Tests run against SQLite via `aiosqlite` with foreign keys
enabled; external dependencies (token verifier, storage, explanation provider) are
faked so business logic is deterministic.

**Frontend (flutter_test):** 38 tests covering auth controller and flow, the
development-auth path, library controller and screen, reader controller and
screen, text selection → explanation, and the explanation sheet (word/sentence/
paragraph, prerequisites, loading, error/retry).

**Quality gates (enforced in CI and pre-commit).**
- Backend: `ruff check`, `black --check`, `isort --check-only`, `mypy app`,
  `pytest`, and a Docker image build.
- Frontend: `flutter pub get`, `flutter gen-l10n`, `build_runner`, `dart format
  --set-exit-if-changed`, `flutter analyze`, `flutter test`, and a `flutter build
  web --release` verification.

**Coverage philosophy.** A pragmatic pyramid: heavy unit coverage, focused
integration on boundaries (auth, ownership, processing, explanation), and thin
end-to-end on the critical reading flow. The AI provider is faked in tests, so no
test depends on a running model. No merge without the relevant tests passing.

---

## 15. ADR Summary

| ADR | Title | One-line summary |
| --- | --- | --- |
| 0001 | Multi-package Monorepo | Single monorepo with clear top-level separation for atomic cross-cutting changes and one source of truth for contracts. |
| 0002 | Flutter Architecture | Feature-first layering with Riverpod (state + DI), GoRouter, Dio, and Freezed. |
| 0003 | AI Service Abstraction | All model access is quarantined behind one stable AI/provider contract so the model can change as configuration. |
| 0004 | Authentication | Firebase identity with stateless per-request JWT verification behind a `TokenVerifier`; internal user keyed by UID. |
| 0005 | Storage Abstraction | Uploaded files sit behind a `StorageService` protocol (local today, R2 later); the DB stores only a key. |
| 0006 | Reader Foundation | Content behind a `BookContentExtractor` seam; position/bookmarks anchored to stable offsets, not pages. |
| 0007 | Book Processing Engine | Processor registry + structured document model with stable anchors; text stored once; trigger seam for future workers. |
| 0008 | Learning Intelligence Engine | A pluggable, learner-aware layer above the Explanation Service; capabilities register in a registry, engine stays generic. |

---

## 16. Current Limitations

These are real, verified limitations of the current implementation.

- **PDF/EPUB/DOCX/OCR processing** — not implemented. Only plain-text and Markdown
  are parsed; other formats are stored and reported as `unsupported_format`.
- **Knowledge graph** — none. Prerequisites come from a small hand-curated
  dependency map, not a graph or corpus analysis.
- **Adaptive learning** — none. No learner profile, difficulty adaptation, or
  personalization; the same inputs yield the same behavior for every user.
- **Memory / spaced revision** — none. The system does not remember what a reader
  has seen or struggled with.
- **Confidence engine** — none. Explanations carry no confidence or faithfulness
  score, and there is no answer-validation pass.
- **Cross-book intelligence** — none. Everything is scoped to a single book;
  there are no cross-book citations or connections.
- **Retrieval-augmented generation / embeddings** — none. Qdrant is provisioned in
  the dev stack but no code produces or queries embeddings.
- **Explanation pre-computation / caching** — none. Explanations are generated on
  demand, so the reader waits on the model for each request.
- **Cloud model** — none. Only a local Ollama model is wired; there is no cloud
  provider or fallback.
- **Cloud object storage (R2)** — not implemented; only local filesystem storage.
- **Asynchronous workers** — not implemented; processing runs inline in the upload
  request. `services/workers` is an empty scaffold.
- **Model accuracy** — small local models occasionally produce inaccurate
  explanations (e.g. wrong acronym expansions); there is no verification layer.

---

## 17. Future Roadmap

Planned work, not implemented. Nothing here should be read as available today.

**Short-term (📅)**
- PDF processor behind the existing `BookProcessor` interface.
- Explanation caching/pre-computation to remove on-demand model waits.
- A richer, larger prerequisite dependency map (still deterministic).
- Cloudflare R2 `StorageService` implementation.

**Medium-term (📅)**
- Asynchronous worker tier (`QueuedProcessingTrigger` + `services/workers`) for
  processing and pre-computation.
- Embeddings + Qdrant retrieval and RAG-grounded explanations.
- Additional LIE capabilities: confidence estimation and a faithfulness/answer
  validation pass.
- EPUB/DOCX processors; reading plans and progress analytics.

**Long-term (📅)**
- Adaptive learning (learner profile, difficulty adaptation, recommendations).
- Memory and spaced revision.
- Cross-book intelligence and citations.
- Cloud model provider with cost/latency policy and fallback (per ADR 0003).

---

## 18. Research Contribution

**Current novelty.** ReadMe.ai's distinctive stance is architectural: it treats
*understanding-in-place* as a first-class constraint and encodes it in the system
design rather than in a single feature. Two implemented elements support this.

- **Learning Intelligence Engine.** A generic, pluggable layer that runs
  learner-aware capabilities *before* explanation generation and merges their
  outcomes into the response. It separates "decide what the learner needs" from
  "generate the explanation," giving a clean substrate for educational
  intelligence (prerequisites today; confidence, memory, recommendations later).
- **Structured Document Architecture.** Every book becomes a normalised
  Chapter→Section→Paragraph→Sentence document with deterministic, layout-independent
  anchors and single-source text storage. This gives every feature — reader,
  selection, explanation, and future notes/citations — a stable addressing scheme
  independent of format or device.

**Future research direction.** The combination of a structured document substrate
with a capability-based learning engine is a natural platform for studying
prerequisite discovery, confidence/faithfulness estimation for scoped
explanations, and adaptive, memory-aware reading support.

**Potential publication contribution.** A system and evaluation of
"understanding-preserving" reading support: architecture (structured documents +
capability pipeline), and measurement of explanation faithfulness and
prerequisite usefulness against reader outcomes. This requires the confidence and
evaluation work in Section 17, which is not yet built.

---

## 19. Demo Guide

Expected end-to-end flow in Development Mode (backend + Ollama + emulator
running).

1. **Launch.** Start Ollama (with the configured model), the backend
   (`DEV_AUTH=true`), and the Flutter app on the emulator with the dev
   dart-defines. *Expected:* the splash screen appears.
2. **Authentication.** *Expected:* the app auto-authenticates the mock user
   (`Geo (Development)`), skips Google Sign-In, and shows a "Dev Mode" banner.
3. **Library.** *Expected:* the Library lists the mock user's books newest-first;
   uploading a text/Markdown file adds it and triggers processing to `COMPLETED`.
4. **Reader.** *Expected:* opening a processed book renders reflowable text with
   adjustable font size, spacing, and dark mode; reading position persists via a
   stable anchor.
5. **AI explanations.** *Expected:* selecting a word returns a definition, an
   explanation, and an example; selecting a sentence or paragraph returns a scoped
   explanation. A provider outage surfaces a retryable error, not a crash.
6. **Prerequisites.** *Expected:* when the selection contains a known term from
   the dependency map, a prerequisites section lists concepts to learn first;
   otherwise it is empty (which is valid).
7. **Logout.** *Expected:* logout returns to the mock login state (in dev mode)
   without losing reading position data on the server.

---

## 20. Deployment Guide

### Development
- **Recommended (Docker):** `docker compose -f infra/docker/docker-compose.yml up
  --build` starts `api`, `postgres`, and `qdrant`. Ollama runs on the host.
- **Local (no Docker):** run PostgreSQL and Ollama locally, create the app role
  and database, run Alembic migrations, then `uvicorn app.main:app --reload`. Run
  the client with `flutter run` and the dart-defines above.
- **Migrations:** `alembic upgrade head` (four migrations).

### Production (target; not fully implemented)
- Backend containerized (`apps/api/Dockerfile`), fronted by a managed PostgreSQL.
- `DEV_AUTH=false`; a real Firebase project id configured; explicit CORS origins;
  JSON logs; docs endpoints disabled.
- Cloud storage (R2) and a cloud model provider are required for production but are
  📅 planned, not built.

### Environment variables (backend)
`APP_ENV`, `APP_NAME`, `APP_VERSION`, `APP_DEBUG`; `SERVER_HOST`, `SERVER_PORT`,
`CORS_ALLOW_ORIGINS`; `LOG_LEVEL`, `LOG_FORMAT`; `POSTGRES_*`; `QDRANT_*`
(provisioned, unused); `FIREBASE_PROJECT_ID`; `DEV_AUTH`; `STORAGE_BACKEND`,
`STORAGE_LOCAL_PATH`, `MAX_UPLOAD_SIZE_BYTES`; `OLLAMA_BASE_URL`, `OLLAMA_MODEL`,
`OLLAMA_TIMEOUT_SECONDS`. R2 keys are documented placeholders only.

### Docker / Firebase / Ollama / PostgreSQL
- **Docker:** dev compose for api/postgres/qdrant; each app owns its Dockerfile.
- **Firebase:** identity provider for the production auth path; client config is
  supplied via dart-defines (no credentials committed).
- **Ollama:** local inference server; the configured model must be pulled before
  explanations work.
- **PostgreSQL:** system of record; schema created via Alembic migrations.

---

## 21. Known Risks

**Technical risks.**
- Processing runs inline in the upload request; a large or slow parse blocks that
  request. The trigger seam exists to move this to a worker, but the worker is not
  built.
- Only plain-text/Markdown is parseable, so most real-world formats (PDF/EPUB) are
  not usable end-to-end today.
- The prerequisite dependency map is small and hand-curated; coverage is narrow
  and unrelated to the specific book.

**Scalability.**
- No asynchronous tier and no caching: explanation and processing load fall on the
  request path. Qdrant is provisioned but unused, so retrieval-scale features are
  untested.
- Single local model instance; concurrent explanation load is bounded by Ollama.

**Performance.**
- Explanations are generated on demand, so reader latency depends on model speed —
  in tension with the "preserve reading flow" principle until pre-computation is
  added.
- The anchor↔scroll mapping is approximate for reflowed text.

**AI limitations.**
- Small local models can hallucinate or produce inaccurate explanations; there is
  no confidence score or faithfulness/validation pass.
- Explanation quality varies with the configured model; some models break JSON
  output parsing.

**Security.**
- Development Mode must never be enabled in production; it accepts a fixed token.
  Mitigated by defaulting `DEV_AUTH=false` and confining the switch to one place
  per side.
- Stateless verification means no immediate server-side token revocation
  (bounded by token lifetime).
- Local filesystem storage is single-host and not suitable for production
  durability.

---

## 22. Metrics (Estimates)

These are engineering estimates of progress against the full product/research
vision, not measured coverage numbers.

| Dimension | Estimate | Basis |
| --- | --- | --- |
| Architecture completion | ~90% | Foundational patterns and boundaries established; async tier and vector layer deferred. |
| Backend completion | ~70% | Core modules complete; no PDF, workers, RAG, or cloud storage. |
| Frontend completion | ~65% | Auth, library, reader, explanation complete; no plans, notes, analytics, or offline. |
| AI completion | ~35% | On-demand explanations via local model; no RAG, confidence, memory, or pre-computation. |
| Research completion | ~30% | LIE foundation + structured documents in place; evaluation and adaptive layers not built. |
| Overall MVP scope | ~60% | Core reading + explanation loop is demonstrable end-to-end. |
| Portfolio readiness | High (~85%) | Clean architecture, tests, CI, ADRs, and a working demo. |
| Research-paper readiness | Early (~30%) | Novel architecture exists; needs evaluation and the confidence/adaptive work. |
| Production readiness | Low (~35%) | No cloud storage/model, no workers, dev-oriented run model. |

---

## 23. Next Recommended Sprint

**Recommendation: Sprint 6.0 — PDF Processing.**

**Why.** The single largest gap between the current state and a usable product is
format support: today only plain-text/Markdown books work end-to-end, yet the
majority of real books are PDFs. Every downstream system — the reader, the
structured document model, stable anchors, the selection classifier, the
explanation strategies, and the Learning Intelligence Engine — is already built to
consume structured documents and does not care which processor produced them. A
PDF processor plugs into the existing `BookProcessor` interface and
`ProcessorRegistry` with **no changes to the reader, schema, API, or explanation
path**, so it delivers the most user-visible value for the least architectural
risk. It also exercises the extension point that ADR 0007 was explicitly designed
around, validating the "add a processor, change nothing else" claim.

This sprint should be scoped to parsing and structure extraction only (producing
the same Chapter→Section→Paragraph→Sentence document with stable anchors), keeping
AI, retrieval, and workers out of scope so it remains a clean, testable addition.

---

*End of record.*
