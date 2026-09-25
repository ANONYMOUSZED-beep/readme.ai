# syntax=docker/dockerfile:1
# ===========================================================================
# ReadMe.ai backend image — multi-stage build.
#   builder : installs dependencies into an isolated virtual environment
#   runtime : copies the venv + source, runs as a non-root user
# ===========================================================================

# --- builder ---------------------------------------------------------------
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /build

RUN python -m venv "$VIRTUAL_ENV"

# Copy the dependency manifest and sources required to build the project.
# pyproject metadata references README.md, and setuptools needs the package
# sources present to resolve `packages.find`.
COPY pyproject.toml README.md ./
COPY app ./app
RUN pip install --upgrade pip && pip install .

# --- runtime ---------------------------------------------------------------
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

# Create an unprivileged user to run the service.
RUN groupadd --system app && useradd --system --gid app --create-home app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY app ./app
COPY migrations ./migrations
COPY alembic.ini ./alembic.ini
COPY docker-entrypoint.sh ./docker-entrypoint.sh

# The service runs unprivileged, so the local storage root (STORAGE_LOCAL_PATH,
# default var/storage relative to /app) must exist and belong to that user —
# otherwise every upload fails with a permission error. A volume mounted here
# inherits this ownership on first use.
RUN chmod 0755 docker-entrypoint.sh \
    && mkdir -p var/storage \
    && chown -R app:app var

USER app

EXPOSE 8000

# Liveness check used by orchestrators and docker-compose.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; \
sys.exit(0) if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else sys.exit(1)"

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
