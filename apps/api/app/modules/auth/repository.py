"""Data-access for the authentication module (repository pattern)."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.auth.models import User, _utcnow
from app.modules.auth.verifier import FirebaseIdentity


class UserRepository:
    """Encapsulates all persistence operations for :class:`User`.

    The repository owns no transaction policy beyond an explicit
    :meth:`commit`; the service decides when a unit of work is complete.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_by_firebase_uid(self, firebase_uid: str) -> User | None:
        """Return the user for a Firebase UID, or ``None`` if not provisioned."""
        result = await self._session.execute(
            select(User).where(User.firebase_uid == firebase_uid)
        )
        return result.scalar_one_or_none()

    async def create(self, identity: FirebaseIdentity) -> User:
        """Provision a new user from a verified identity."""
        user = User(
            firebase_uid=identity.uid,
            email=identity.email,
            display_name=identity.display_name,
            photo_url=identity.photo_url,
            last_login_at=_utcnow(),
        )
        self._session.add(user)
        await self._session.flush()
        return user

    async def sync_profile(self, user: User, identity: FirebaseIdentity) -> None:
        """Refresh mutable profile fields and record this sign-in."""
        user.email = identity.email
        user.display_name = identity.display_name
        user.photo_url = identity.photo_url
        user.last_login_at = _utcnow()

    async def commit(self) -> None:
        """Commit the current unit of work."""
        await self._session.commit()

    async def rollback(self) -> None:
        """Discard the current unit of work (e.g. after a constraint violation)."""
        await self._session.rollback()
