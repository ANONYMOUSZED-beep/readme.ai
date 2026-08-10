# ReadMe.ai

> Help people **understand** books instead of simply reading them.

ReadMe.ai is an AI reading companion that preserves reading flow by removing
confusion exactly when it appears — unknown vocabulary, difficult sentences,
complex concepts, missing prerequisites — without ever replacing the act of
reading.

This repository is a **monorepo** containing the Flutter client, the FastAPI
backend, background workers, shared contracts, infrastructure, and documentation.

> **Status:** Sprint 3.5 — Book Processing Engine.
> Uploaded books are converted into a structured internal document
> (Document → Chapter → Section → Paragraph → Sentence) with stable anchors,
> persisted and status-tracked. The reader now consumes this structured content
> instead of raw files. A clean processor interface supports future PDF/EPUB/
> DOCX/OCR processors without touching the reader. No AI, RAG, embeddings, or
> search.

---

## Repository Layout

```
readme-ai/
├── apps/
│   ├── mobile/        # Flutter client application
│   └── api/           # FastAPI backend (synchronous orchestration layer)
├── services/
│   └── workers/       # Asynchronous background processing (future sprints)
├── packages/
│   ├── api-contracts/ # Single source of truth for FE/BE request/response shapes
│   └── prompts/       # Versioned LLM prompt assets (future sprints)
├── infra/
│   └── docker/        # Dockerfiles and docker-compose for local/dev environments
├── docs/              # Architecture, ADRs, standards, runbooks
└── tooling/           # Shared linters, hooks, and developer scripts
```

A description of every folder lives in [`docs/folder-structure.md`](docs/folder-structure.md).

---

## Quick Start

Prerequisites are listed in [`docs/development-setup.md`](docs/development-setup.md).
The short version:

```bash
# 1. Backend + datastores via Docker (recommended)
cp .env.example .env
docker compose -f infra/docker/docker-compose.yml up --build

# 2. Flutter client
cd apps/mobile
flutter pub get
flutter run
```

Verify the backend is alive:

```bash
curl http://localhost:8000/health
curl http://localhost:8000/version
```

---

## Development Authentication Mode (local/demo only)

A development tool that bypasses Firebase and auto-logs-in a mock user
(`Geo (Development)`, `geo.dev@readme.ai`). **Never enable it in production.**

Enable (both backend and client):

```bash
# Backend: in .env
DEV_AUTH=true

# Client: pass the same flag at build time
flutter run --dart-define=DEV_AUTH=true --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

With `DEV_AUTH=true` the app skips Google Sign-In, navigates straight to the
Library, shows a "Dev Mode" ribbon, and the client sends `Authorization: Bearer
development-token`, which the backend accepts only in this mode. Logout returns
to the mock login state.

Return to production: set `DEV_AUTH=false` (the default) everywhere — Firebase
authentication and production JWT verification are fully restored, unchanged.

## Documentation

| Document | Purpose |
| --- | --- |
| [Development Setup](docs/development-setup.md) | How to install tooling and run everything locally |
| [Architecture Overview](docs/architecture-overview.md) | High-level system design (from Sprint 0.1) |
| [API Reference](docs/api.md) | HTTP endpoints, auth, and error envelope |
| [Processing Pipeline](docs/processing-pipeline.md) | How uploads become structured documents |
| [Internal Document Model](docs/internal-document-model.md) | The structured representation & anchors |
| [Folder Structure](docs/folder-structure.md) | Responsibility of every folder |
| [Coding Standards](docs/coding-standards.md) | Naming, structure, and code conventions |
| [Contributing](docs/contributing.md) | Branch strategy, commit convention, review rules |

---

## License

Proprietary. All rights reserved. © ReadMe.ai
