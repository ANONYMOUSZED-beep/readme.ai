"""Authentication service — orchestrates verification and provisioning."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy.exc import IntegrityError

from app.core.errors import ConflictError
from app.core.logging import get_logger
from app.modules.auth.models import User
from app.modules.auth.repository import UserRepository
from app.modules.auth.verifier import FirebaseIdentity, TokenVerifier

logger = get_logger(__name__)

# Every authenticated request passes through :meth:`AuthService.authenticate`.
# Recording the sign-in on each one would turn every read into a write, so the
# timestamp is refreshed at most once per interval (profile changes are always
# persisted immediately).
LAST_LOGIN_REFRESH_INTERVAL = timedelta(minutes=5)


class AuthService:
    """Coordinates token verification and internal user provisioning."""

    def __init__(self, repository: UserRepository, verifier: TokenVerifier) -> None:
        self._repository = repository
        self._verifier = verifier

    async def authenticate(self, token: str) -> User:
        """Resolve the user for a bearer token.

        Verifies the token, provisions an internal user on first sight, and
        keeps profile fields and the last-login timestamp current on subsequent
        requests, then returns the persisted user.
        """
        identity = await self._verifier.verify(token)

        user = await self._repository.get_by_firebase_uid(identity.uid)
        if user is None:
            return await self._provision(identity)

        if _needs_sync(user, identity):
            return await self._sync(user, identity)
        return user

    async def _sync(self, user: User, identity: FirebaseIdentity) -> User:
        user_id = user.id  # captured: a rollback expires the instance
        await self._repository.sync_profile(user, identity)
        try:
            await self._repository.commit()
            return user
        except IntegrityError:
            # The provider now reports an email another account already holds.
            # Authentication is still valid, so keep serving the stored profile
            # rather than failing the request.
            await self._repository.rollback()
            logger.warning(
                "auth.profile_sync_conflict", extra={"user_id": str(user_id)}
            )
        refreshed = await self._repository.get_by_firebase_uid(identity.uid)
        if refreshed is None:  # pragma: no cover - deleted concurrently
            raise ConflictError("The account changed during sign-in; retry.")
        return refreshed

    async def _provision(self, identity: FirebaseIdentity) -> User:
        try:
            user = await self._repository.create(identity)
            await self._repository.commit()
            return user
        except IntegrityError:
            await self._repository.rollback()

        # Either a concurrent first request provisioned this identity (resolve
        # to that row), or another identity already owns the email address.
        # Accounts are never merged by email: an unverified email must not be
        # able to take over an existing account.
        existing = await self._repository.get_by_firebase_uid(identity.uid)
        if existing is None:
            raise ConflictError(
                "An account with this email address already exists.",
            )
        return existing


def _needs_sync(user: User, identity: FirebaseIdentity) -> bool:
    if (
        user.email != identity.email
        or user.display_name != identity.display_name
        or user.photo_url != identity.photo_url
    ):
        return True
    last_login = user.last_login_at
    if last_login.tzinfo is None:
        # Some drivers (e.g. SQLite) return naive values for UTC columns.
        last_login = last_login.replace(tzinfo=UTC)
    return datetime.now(tz=UTC) - last_login >= LAST_LOGIN_REFRESH_INTERVAL
