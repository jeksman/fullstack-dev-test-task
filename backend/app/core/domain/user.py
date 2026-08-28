"""The user as the authorization layer sees it: an identity carrying a role."""

import uuid
from dataclasses import dataclass
from datetime import datetime

from app.core.domain.rbac import Role


@dataclass(frozen=True)
class User:
    id: uuid.UUID
    email: str
    role: Role
    is_active: bool
    full_name: str | None = None
    created_at: datetime | None = None


@dataclass(frozen=True)
class NewUser:
    """A user to be created. Carries the plaintext password; hashing is the
    repository's business, not the use case's."""

    email: str
    password: str
    role: Role = Role.MEMBER
    is_active: bool = True
    full_name: str | None = None


@dataclass(frozen=True)
class ProfileUpdate:
    """Fields a user may change on their own profile. Deliberately excludes
    `role` and `is_active` — self-service escalation is impossible by type."""

    email: str | None = None
    full_name: str | None = None
