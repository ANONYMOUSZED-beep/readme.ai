#!/bin/sh
# Container entrypoint for the ReadMe.ai API.
#
# Optionally applies database migrations before handing off to the service
# command (uvicorn by default). Enable with RUN_MIGRATIONS=true for single-
# instance deployments such as the local docker-compose stack; multi-replica
# deployments should run `alembic upgrade head` as a separate release step.
set -eu

if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
    echo "entrypoint: applying database migrations"
    alembic upgrade head
fi

exec "$@"
