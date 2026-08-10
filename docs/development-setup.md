# Development Setup

This guide gets a new engineer from zero to a running ReadMe.ai development
environment.

## 1. Prerequisites

| Tool | Version | Used by |
| --- | --- | --- |
| Git | 2.40+ | everything |
| Flutter SDK | 3.41+ (Dart 3.11+) | `apps/mobile` |
| Python | 3.12+ | `apps/api`, `services/workers` |
| Docker + Docker Compose | latest stable | local datastores & backend |
| pre-commit | 3.5+ | git hooks |

Verify your toolchain:

```bash
flutter --version
python --version
docker --version
docker compose version
```

## 2. Clone & configure

```bash
git clone <repo-url> readme-ai
cd readme-ai
cp .env.example .env
```

Install git hooks once:

```bash
pip install pre-commit
pre-commit install
```

## 3. Run the backend stack (Docker)

The recommended path. This starts the API, PostgreSQL, and Qdrant together:

```bash
docker compose -f infra/docker/docker-compose.yml up --build
```

Then confirm the service is healthy:

```bash
curl http://localhost:8000/health    # -> {"status":"ok", ...}
curl http://localhost:8000/version   # -> {"name": ..., "version": ...}
```

Interactive API docs (development only): http://localhost:8000/docs

## 4. Run the backend without Docker (optional)

```bash
cd apps/api
python -m venv .venv
# Windows:  .venv\Scripts\activate
# Unix:     source .venv/bin/activate
pip install -e ".[dev]"
uvicorn app.main:app --reload --port 8000
```

You will need PostgreSQL and Qdrant running locally (or via Docker) and the
matching values in your `.env`.

## 5. Run the Flutter client

```bash
cd apps/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates Freezed/JSON code
flutter run
```

## 6. Quality gates (run before pushing)

```bash
# Python
cd apps/api
ruff check . && black --check . && isort --check-only . && mypy app && pytest

# Flutter
cd apps/mobile
dart format --set-exit-if-changed . && flutter analyze && flutter test
```

Or simply let `pre-commit run --all-files` and CI do it for you.
