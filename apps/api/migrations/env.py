"""Alembic migration environment (async).

The connection URL and target metadata are sourced from the application itself
(``app.core.config`` and ``app.db.base.Base``) so migrations always match the
running service's configuration and model definitions.

No ORM models exist in the foundation sprint, so ``Base.metadata`` is currently
empty; this environment is ready for the first model-bearing sprint.
"""

from __future__ import annotations

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from app.core.config import get_settings
from app.db.base import Base

# Import model-bearing modules so their tables are registered on Base.metadata
# for Alembic autogeneration.
from app.modules.activity import models as _activity_models  # noqa: F401
from app.modules.auth import models as _auth_models  # noqa: F401
from app.modules.library import models as _library_models  # noqa: F401
from app.modules.processing import models as _processing_models  # noqa: F401
from app.modules.reader import models as _reader_models  # noqa: F401

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

config.set_main_option("sqlalchemy.url", get_settings().database_url)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode (emit SQL without a DB connection)."""
    context.configure(
        url=get_settings().database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def _do_run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    """Run migrations in 'online' mode using an async engine."""
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
    )
    async with connectable.connect() as connection:
        await connection.run_sync(_do_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
