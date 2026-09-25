"""Application configuration.

Settings are loaded from environment variables (and a local ``.env`` during
development) and validated by Pydantic. Configuration is read exactly once and
cached, so the rest of the codebase depends on a single, validated source of
truth rather than reading ``os.environ`` directly.
"""

from __future__ import annotations

from enum import StrEnum
from functools import lru_cache

from pydantic import Field, computed_field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Environment(StrEnum):
    """Supported runtime environments."""

    DEVELOPMENT = "development"
    STAGING = "staging"
    PRODUCTION = "production"


class LogFormat(StrEnum):
    """Supported log output formats."""

    CONSOLE = "console"
    JSON = "json"


class LogLevel(StrEnum):
    """Supported log levels."""

    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class StorageBackend(StrEnum):
    """Supported object-storage backends."""

    LOCAL = "local"
    R2 = "r2"


class Settings(BaseSettings):
    """Validated application settings.

    Field names map to ``UPPER_SNAKE_CASE`` environment variables (case
    insensitive). Unknown variables in the environment are ignored so that
    placeholder values for future sprints do not break startup.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- Application -------------------------------------------------------
    app_env: Environment = Field(default=Environment.DEVELOPMENT, alias="APP_ENV")
    app_name: str = Field(default="ReadMe.ai API", alias="APP_NAME")
    app_version: str = Field(default="0.2.0", alias="APP_VERSION")
    app_debug: bool = Field(default=False, alias="APP_DEBUG")

    # --- HTTP server -------------------------------------------------------
    server_host: str = Field(default="0.0.0.0", alias="SERVER_HOST")
    server_port: int = Field(default=8000, alias="SERVER_PORT")
    cors_allow_origins: str = Field(
        default="http://localhost:3000",
        alias="CORS_ALLOW_ORIGINS",
    )

    # --- Logging -----------------------------------------------------------
    log_level: LogLevel = Field(default=LogLevel.INFO, alias="LOG_LEVEL")
    log_format: LogFormat = Field(default=LogFormat.JSON, alias="LOG_FORMAT")

    # --- PostgreSQL --------------------------------------------------------
    postgres_host: str = Field(default="localhost", alias="POSTGRES_HOST")
    postgres_port: int = Field(default=5432, alias="POSTGRES_PORT")
    postgres_user: str = Field(default="readme", alias="POSTGRES_USER")
    postgres_password: str = Field(default="readme", alias="POSTGRES_PASSWORD")
    postgres_db: str = Field(default="readme_ai", alias="POSTGRES_DB")

    # --- Firebase Authentication -------------------------------------------
    # The project id is used to validate the `aud` and `iss` claims of incoming
    # Firebase ID tokens. Empty in local/test contexts where verification is
    # stubbed; required in any environment that accepts real tokens.
    firebase_project_id: str = Field(default="", alias="FIREBASE_PROJECT_ID")

    # --- Development authentication (NEVER enable in production) ------------
    # When true, a fixed development bearer token authenticates as a mock user,
    # bypassing Firebase. Production JWT verification is unchanged either way.
    dev_auth: bool = Field(default=False, alias="DEV_AUTH")

    # --- Storage -----------------------------------------------------------
    # Selects the StorageService implementation. Only LOCAL is implemented;
    # switching to R2 in a later sprint is a provider change, not a Book-module
    # change.
    storage_backend: StorageBackend = Field(
        default=StorageBackend.LOCAL,
        alias="STORAGE_BACKEND",
    )
    storage_local_path: str = Field(
        default="var/storage",
        alias="STORAGE_LOCAL_PATH",
    )
    # Maximum accepted upload size in bytes (default 50 MiB).
    max_upload_size_bytes: int = Field(
        default=52_428_800,
        gt=0,
        alias="MAX_UPLOAD_SIZE_BYTES",
    )

    # --- LLM (Ollama) ------------------------------------------------------
    # Base URL of the Ollama server and the model used for explanations.
    ollama_base_url: str = Field(
        default="http://localhost:11434",
        alias="OLLAMA_BASE_URL",
    )
    ollama_model: str = Field(default="llama3.2", alias="OLLAMA_MODEL")
    ollama_timeout_seconds: float = Field(
        default=30.0,
        gt=0,
        alias="OLLAMA_TIMEOUT_SECONDS",
    )

    @model_validator(mode="after")
    def _enforce_production_safety(self) -> Settings:
        """Refuse to start a production service with unsafe configuration.

        A misconfigured production deployment fails fast at startup instead of
        silently accepting a public development token or rejecting every user.
        """
        if self.app_env is Environment.PRODUCTION:
            if self.dev_auth:
                raise ValueError("DEV_AUTH must not be enabled in production.")
            if not self.firebase_project_id:
                raise ValueError("FIREBASE_PROJECT_ID is required in production.")
        return self

    @computed_field  # type: ignore[prop-decorator]
    @property
    def is_production(self) -> bool:
        """Whether the service runs in a production-like environment."""
        return self.app_env == Environment.PRODUCTION

    @computed_field  # type: ignore[prop-decorator]
    @property
    def cors_origins(self) -> list[str]:
        """CORS origins parsed from the comma-separated configuration value."""
        return [
            origin.strip()
            for origin in self.cors_allow_origins.split(",")
            if origin.strip()
        ]

    @computed_field  # type: ignore[prop-decorator]
    @property
    def database_url(self) -> str:
        """Async SQLAlchemy connection URL for PostgreSQL (asyncpg driver)."""
        return (
            f"postgresql+asyncpg://{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
        )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the cached, validated application settings.

    Cached so configuration is parsed and validated only once per process.
    Override via FastAPI dependency overrides in tests.
    """
    return Settings()
